{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE LambdaCase #-}

module Automation.ObsidianSync
  ( ObsidianCredentials (..)
  , SyncResult (..)
  , runObCommand
  , removeSyncLock
  , killObProcesses
  , ensureSyncClean
  , runObSyncWithRetry
  , syncObsidianVault
  , pushObsidianVault
  , validatePrePushFileCount
  , writeEmbedsToNote
  , appendEmbedsToObsidianNote
  , countVaultFiles
  , vaultFileCountPath
  ) where

import Control.Concurrent (threadDelay)
import Control.Exception (SomeException, catch, throwIO, try)
import Control.Monad (void, when)
import Data.List (intercalate)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Directory
  ( doesDirectoryExist
  , doesFileExist
  , listDirectory
  , removeDirectoryRecursive
  , createDirectoryIfMissing
  )
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import Automation.Secret (Secret (..))
import System.Posix.Process (getProcessID)
import System.Process
  ( proc
  , readProcess
  , readCreateProcessWithExitCode
  , readProcessWithExitCode
  , CreateProcess (..)
  )

data ObsidianCredentials = ObsidianCredentials
  { ocAuthToken     :: Secret
  , ocVaultName     :: Text
  , ocVaultPassword :: Maybe Secret
  } deriving (Show, Eq)

data SyncResult = SyncResult
  { srVaultDirectory :: FilePath
  , srSuccess  :: Bool
  } deriving (Show, Eq)

runObCommand :: [String] -> Maybe FilePath -> [(String, String)] -> IO (String, String)
runObCommand args mCwd extraEnv = do
  parentEnv <- getEnvironment
  let mergedEnv = parentEnv <> extraEnv
      cp = (proc "ob" args) { cwd = mCwd, env = Just mergedEnv }
  (exitCode, stdout, stderr) <- readCreateProcessWithExitCode cp ""
  case exitCode of
    ExitSuccess -> pure (stdout, stderr)
    ExitFailure code -> throwIO $ userError $ joinLines
      [ "Command: ob " <> unwords args
      , "Exit code: " <> show code
      , "Stdout: " <> stdout
      , "Stderr: " <> stderr
      ]
  where
    joinLines = foldr (\a b -> a <> "\n" <> b) ""

removeSyncLock :: FilePath -> IO ()
removeSyncLock vaultDirectory = do
  let lockPath = vaultDirectory </> ".obsidian" </> ".sync.lock"
  exists <- doesDirectoryExist lockPath
  when exists $ do
    putStrLn "🔓 Removing stale .sync.lock from vault"
    removeDirectoryRecursive lockPath

findObProcesses :: Maybe FilePath -> IO [String]
findObProcesses mVaultDirectory = do
  myPid <- show <$> getProcessID
  let patterns = ["obsidian-headless"] <> maybe [] pure mVaultDirectory
      grepPattern = intercalate "|" patterns
  result <- try $ readProcess "bash" ["-c",
    "ps -u $(id -u) -o pid,args 2>/dev/null | grep -E '" <> grepPattern <> "' | grep -v grep | awk '{print $1}'"
    ] "" :: IO (Either SomeException String)
  pure $ case result of
    Left _     -> []
    Right pids -> filter (\p -> not (null p) && p /= myPid) $ lines pids

killObProcesses :: Maybe FilePath -> IO ()
killObProcesses mVaultDirectory = do
  pids <- findObProcesses mVaultDirectory
  case pids of
    [] -> pure ()
    _  -> do
      putStrLn $ "🔪 Killing " <> show (length pids) <> " lingering ob process(es): " <> unwords pids
      mapM_ (sendSignal "SIGTERM") pids
      threadDelay 2000000
      mapM_ (sendSignal "SIGKILL") pids
      threadDelay 500000
  where
    sendSignal sig pid =
      catch
        (void $ readProcessWithExitCode "kill" ["-s", sig, pid] "")
        (\(_ :: SomeException) -> pure ())

ensureSyncClean :: FilePath -> IO ()
ensureSyncClean vaultDirectory = do
  killObProcesses (Just vaultDirectory)
  removeSyncLock vaultDirectory
  let lockPath = vaultDirectory </> ".obsidian" </> ".sync.lock"
  stillExists <- doesDirectoryExist lockPath
  when stillExists $ do
    putStrLn "⚠️ Lock still exists after cleanup, removing again"
    removeDirectoryRecursive lockPath

runObSyncWithRetry :: [String] -> [(String, String)] -> FilePath -> Int -> IO ()
runObSyncWithRetry args env vaultDirectory maxRetries = runAttempt 0
  where
    runAttempt attempt = do
      result <- try $ runObCommand args Nothing env :: IO (Either SomeException (String, String))
      case result of
        Right _ -> pure ()
        Left failure ->
          let message = show failure
              isLockContention = "Another sync instance" `T.isInfixOf` T.pack message
              canRetry = attempt < maxRetries
          in case (isLockContention, canRetry) of
            (True, True) -> do
              let delayMs = 2000 * (2 ^ attempt)
              putStrLn $ "⚠️ Sync lock contention (retry " <> show (attempt + 1) <> "/" <> show maxRetries
                <> "), retrying in " <> show (delayMs `div` 1000) <> "s..."
              ensureSyncClean vaultDirectory
              threadDelay (delayMs * 1000)
              runAttempt (attempt + 1)
            _ -> throwIO failure

syncObsidianVault :: ObsidianCredentials -> IO FilePath
syncObsidianVault creds = do
  pid <- show <$> getProcessID
  let vaultDirectory = "/tmp/obsidian-vault-" <> pid
      env = [("OBSIDIAN_AUTH_TOKEN", T.unpack $ unSecret $ ocAuthToken creds)]
  coldCacheSync creds vaultDirectory env

coldCacheSync :: ObsidianCredentials -> FilePath -> [(String, String)] -> IO FilePath
coldCacheSync creds vaultDirectory env = do
  createDirectoryIfMissing True vaultDirectory
  let setupArgs = ["sync-setup", "--vault", T.unpack $ ocVaultName creds, "--path", vaultDirectory]
        <> maybe [] (\pw -> ["--password", T.unpack (unSecret pw)]) (ocVaultPassword creds)
  putStrLn $ "🔧 Setting up Obsidian Sync for vault: " <> T.unpack (ocVaultName creds)
  _ <- runObCommand setupArgs Nothing env
  removeSyncLock vaultDirectory
  putStrLn "📥 Pulling latest vault content..."
  runObSyncWithRetry ["sync", "--path", vaultDirectory] env vaultDirectory 5
  fileCount <- countVaultFiles vaultDirectory
  putStrLn $ "📊 Vault file count after pull: " <> show fileCount
  writeFile (vaultFileCountPath vaultDirectory) (show fileCount)
  pure vaultDirectory

pushObsidianVault :: FilePath -> Secret -> IO ()
pushObsidianVault vaultDirectory authToken = do
  let env = [("OBSIDIAN_AUTH_TOKEN", T.unpack (unSecret authToken))]
  prePushFileCount <- countVaultFiles vaultDirectory
  putStrLn $ "📊 Pre-push file count: " <> show prePushFileCount
  validatePrePushFileCount vaultDirectory prePushFileCount
  ensureSyncClean vaultDirectory
  putStrLn "📤 Pushing changes to Obsidian Sync..."
  runObSyncWithRetry ["sync", "--path", vaultDirectory] env vaultDirectory 5
  threadDelay 1000000
  ensureSyncClean vaultDirectory

validatePrePushFileCount :: FilePath -> Int -> IO ()
validatePrePushFileCount vaultDirectory currentCount = do
  let markerPath = vaultFileCountPath vaultDirectory
  markerExists <- doesFileExist markerPath
  if markerExists
    then do
      baselineStr <- readFile markerPath
      let mBaseline = case reads baselineStr of
            [(n, _)] -> Just (n :: Int)
            _        -> Nothing
      case mBaseline of
        Nothing -> putStrLn "⚠️ Could not parse baseline file count — skipping deletion check"
        Just baseline -> do
          let lost = baseline - currentCount
          putStrLn $ "📊 Baseline: " <> show baseline <> ", Current: " <> show currentCount
            <> " (delta: " <> show (currentCount - baseline) <> ")"
          when (currentCount < baseline) $ do
            let message = "🛑 CIRCUIT BREAKER: Vault lost " <> show lost
                  <> " file(s) (baseline: " <> show baseline <> ", current: "
                  <> show currentCount <> ")."
                  <> " This system only creates or edits files — any deletion is anomalous."
                  <> " Refusing to push to prevent catastrophic data loss."
            putStrLn message
            throwIO $ userError message
    else do
      putStrLn "⚠️ No baseline file count marker found — skipping circuit breaker (first sync)"
      when (currentCount < minSafeFileCount) $ do
        let message = "🛑 CIRCUIT BREAKER: Vault has only " <> show currentCount
              <> " files (minimum safe threshold: " <> show minSafeFileCount
              <> "). Refusing to push to prevent potential data loss."
        putStrLn message
        throwIO $ userError message

minSafeFileCount :: Int
minSafeFileCount = 50

countVaultFiles :: FilePath -> IO Int
countVaultFiles directory = do
  exists <- doesDirectoryExist directory
  if exists
    then countFilesRecursive directory
    else pure 0

countFilesRecursive :: FilePath -> IO Int
countFilesRecursive directory = do
  entries <- listDirectory directory
  let visible = filter (\case '.':_ -> False; _ -> True) entries
  counts <- mapM (\entry -> do
    let fullPath = directory </> entry
    isDirectory <- doesDirectoryExist fullPath
    if isDirectory
      then countFilesRecursive fullPath
      else pure 1
    ) visible
  pure (sum counts)

vaultFileCountPath :: FilePath -> FilePath
vaultFileCountPath vaultDirectory = vaultDirectory </> ".vault-sync-file-count"

writeEmbedsToNote :: FilePath -> [(Text, Text, Text -> Text -> Text)] -> IO ()
writeEmbedsToNote filePath sections = do
  exists <- doesFileExist filePath
  if exists
    then do
      content <- TIO.readFile filePath
      let (modified, newContent) = foldr applySection (False, content) sections
      if modified
        then TIO.writeFile filePath newContent
        else putStrLn "No new sections to add to note"
    else putStrLn $ "⚠️ Note not found, skipping embed write: " <> filePath
  where
    applySection (header, embedHtml, buildSection) (anyMod, currentContent) =
      if T.isInfixOf header currentContent
        then (anyMod, currentContent)
        else (True, currentContent <> buildSection currentContent embedHtml)

appendEmbedsToObsidianNote :: FilePath -> [(Text, Text, Text -> Text -> Text)] -> ObsidianCredentials -> IO ()
appendEmbedsToObsidianNote notePath sections creds = do
  vaultDirectory <- syncObsidianVault creds
  writeEmbedsToNote (vaultDirectory </> notePath) sections
  pushObsidianVault vaultDirectory (ocAuthToken creds)
