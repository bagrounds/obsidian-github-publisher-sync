{-# LANGUAGE OverloadedStrings #-}

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
  , appendEmbedsToObsidianNote
  , countVaultFiles
  , vaultFileCountPath
  ) where

import Control.Concurrent (threadDelay)
import Control.Exception (SomeException, catch, throwIO, try)
import Control.Monad (when)
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
import System.Posix.Process (getProcessID)
import System.Process
  ( CreateProcess (..)
  , StdStream (..)
  , createProcess
  , proc
  , readProcess
  , readCreateProcessWithExitCode
  , readProcessWithExitCode
  , waitForProcess
  )

data ObsidianCredentials = ObsidianCredentials
  { ocAuthToken     :: Text
  , ocVaultName     :: Text
  , ocVaultPassword :: Maybe Text
  } deriving (Show, Eq)

data SyncResult = SyncResult
  { srVaultDir :: FilePath
  , srSuccess  :: Bool
  } deriving (Show, Eq)

data EmbedSection = EmbedSection
  { esHeader       :: Text
  , esEmbedHtml    :: Text
  , esBuildSection :: Text -> Text -> Text
  }

runObCommand :: [String] -> Maybe FilePath -> [(String, String)] -> IO (String, String)
runObCommand args mCwd extraEnv = do
  parentEnv <- getEnvironment
  let mergedEnv = parentEnv <> extraEnv
      cp = (proc "ob" args) { cwd = mCwd, env = Just mergedEnv }
  (exitCode, stdout, stderr) <- readCreateProcessWithExitCode cp ""
  case exitCode of
    ExitSuccess -> pure (stdout, stderr)
    ExitFailure code -> throwIO $ userError $ unlines
      [ "Command: ob " <> unwords args
      , "Exit code: " <> show code
      , "Stdout: " <> stdout
      , "Stderr: " <> stderr
      ]
  where
    unlines = foldr (\a b -> a <> "\n" <> b) ""

removeSyncLock :: FilePath -> IO ()
removeSyncLock vaultDir = do
  let lockPath = vaultDir </> ".obsidian" </> ".sync.lock"
  exists <- doesDirectoryExist lockPath
  when exists $ do
    putStrLn "🔓 Removing stale .sync.lock from vault"
    removeDirectoryRecursive lockPath

findObProcesses :: Maybe FilePath -> IO [String]
findObProcesses mVaultDir = do
  myPid <- show <$> getProcessID
  let patterns = ["obsidian-headless"] <> maybe [] pure mVaultDir
      grepPattern = intercalate "|" patterns
  result <- try $ readProcess "bash" ["-c",
    "ps -u $(id -u) -o pid,args 2>/dev/null | grep -E '" <> grepPattern <> "' | grep -v grep | awk '{print $1}'"
    ] "" :: IO (Either SomeException String)
  pure $ case result of
    Left _     -> []
    Right pids -> filter (\p -> not (null p) && p /= myPid) $ lines pids

killObProcesses :: Maybe FilePath -> IO ()
killObProcesses mVaultDir = do
  pids <- findObProcesses mVaultDir
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
        (readProcessWithExitCode "kill" ["-s", sig, pid] "" >> pure ())
        (\(_ :: SomeException) -> pure ())

ensureSyncClean :: FilePath -> IO ()
ensureSyncClean vaultDir = do
  killObProcesses (Just vaultDir)
  removeSyncLock vaultDir
  let lockPath = vaultDir </> ".obsidian" </> ".sync.lock"
  stillExists <- doesDirectoryExist lockPath
  when stillExists $ do
    putStrLn "⚠️ Lock still exists after cleanup, removing again"
    removeDirectoryRecursive lockPath

runObSyncWithRetry :: [String] -> [(String, String)] -> FilePath -> Int -> IO ()
runObSyncWithRetry args env vaultDir maxRetries = go 0
  where
    go attempt = do
      result <- try $ runObCommand args Nothing env :: IO (Either SomeException (String, String))
      case result of
        Right _ -> pure ()
        Left err ->
          let msg = show err
              isLockContention = "Another sync instance" `T.isInfixOf` T.pack msg
              canRetry = attempt < maxRetries
          in case (isLockContention, canRetry) of
            (True, True) -> do
              let delayMs = 2000 * (2 ^ attempt)
              putStrLn $ "⚠️ Sync lock contention (retry " <> show (attempt + 1) <> "/" <> show maxRetries
                <> "), retrying in " <> show (delayMs `div` 1000) <> "s..."
              ensureSyncClean vaultDir
              threadDelay (delayMs * 1000)
              go (attempt + 1)
            _ -> throwIO err

syncObsidianVault :: ObsidianCredentials -> Maybe FilePath -> IO FilePath
syncObsidianVault creds mCacheDir = do
  let vaultDir = case mCacheDir of
        Just d  -> d
        Nothing -> "obsidian-vault-sync"

  let isWarmCache = case mCacheDir of
        Just _ -> True
        Nothing -> False

  createDirectoryIfMissing True vaultDir

  warmCacheValid <- case isWarmCache of
    True  -> doesDirectoryExist (vaultDir </> ".obsidian")
    False -> pure False

  let env = [("OBSIDIAN_AUTH_TOKEN", T.unpack $ ocAuthToken creds)]

  ensureSyncClean vaultDir

  case warmCacheValid of
    True -> do
      putStrLn $ "♻️  Re-using cached vault at " <> vaultDir <> " (incremental sync)"
      putStrLn "📥 Pulling latest vault content (warm cache fast path)..."
      result <- try $ runObSyncWithRetry ["sync", "--path", vaultDir] env vaultDir 5 :: IO (Either SomeException ())
      case result of
        Right () -> do
          fileCount <- countVaultFiles vaultDir
          putStrLn $ "📊 Vault file count after pull: " <> show fileCount
          writeFile (vaultFileCountPath vaultDir) (show fileCount)
          pure vaultDir
        Left err -> do
          let msg = show err
              needsSetup = any (`T.isInfixOf` T.pack msg)
                [ "No sync configuration"
                , "Encryption key not found"
                , "sync-setup"
                ]
          case needsSetup of
            True -> do
              putStrLn "⚠️ Warm cache missing config, falling back to sync-setup..."
              ensureSyncClean vaultDir
              coldCacheSync creds vaultDir env
            False -> throwIO err
    False -> coldCacheSync creds vaultDir env

coldCacheSync :: ObsidianCredentials -> FilePath -> [(String, String)] -> IO FilePath
coldCacheSync creds vaultDir env = do
  putStrLn "🧹 Clearing vault directory for clean sync-setup (data loss prevention)..."
  exists <- doesDirectoryExist vaultDir
  when exists $ removeDirectoryRecursive vaultDir
  createDirectoryIfMissing True vaultDir
  let setupArgs = ["sync-setup", "--vault", T.unpack $ ocVaultName creds, "--path", vaultDir]
        <> maybe [] (\pw -> ["--password", T.unpack pw]) (ocVaultPassword creds)
  putStrLn $ "🔧 Setting up Obsidian Sync for vault: " <> T.unpack (ocVaultName creds)
  _ <- runObCommand setupArgs Nothing env
  removeSyncLock vaultDir
  putStrLn "📥 Pulling latest vault content..."
  runObSyncWithRetry ["sync", "--path", vaultDir] env vaultDir 5
  fileCount <- countVaultFiles vaultDir
  putStrLn $ "📊 Vault file count after pull: " <> show fileCount
  writeFile (vaultFileCountPath vaultDir) (show fileCount)
  pure vaultDir

pushObsidianVault :: FilePath -> Text -> IO ()
pushObsidianVault vaultDir authToken = do
  let env = [("OBSIDIAN_AUTH_TOKEN", T.unpack authToken)]
  prePushFileCount <- countVaultFiles vaultDir
  putStrLn $ "📊 Pre-push file count: " <> show prePushFileCount
  validatePrePushFileCount vaultDir prePushFileCount
  ensureSyncClean vaultDir
  putStrLn "📤 Pushing changes to Obsidian Sync..."
  runObSyncWithRetry ["sync", "--path", vaultDir] env vaultDir 5
  threadDelay 1000000
  ensureSyncClean vaultDir

validatePrePushFileCount :: FilePath -> Int -> IO ()
validatePrePushFileCount vaultDir currentCount = do
  let markerPath = vaultFileCountPath vaultDir
  markerExists <- doesFileExist markerPath
  case markerExists of
    False -> do
      putStrLn "⚠️ No baseline file count marker found — skipping circuit breaker (first sync)"
      when (currentCount < minSafeFileCount) $ do
        let msg = "🛑 CIRCUIT BREAKER: Vault has only " <> show currentCount
              <> " files (minimum safe threshold: " <> show minSafeFileCount
              <> "). Refusing to push to prevent potential data loss."
        putStrLn msg
        throwIO $ userError msg
    True -> do
      baselineStr <- readFile markerPath
      let mBaseline = case reads baselineStr of
            [(n, _)] -> Just (n :: Int)
            _        -> Nothing
      case mBaseline of
        Nothing -> putStrLn "⚠️ Could not parse baseline file count — skipping percentage check"
        Just baseline -> do
          let dropPercent = case baseline of
                0 -> 0.0 :: Double
                _ -> fromIntegral (baseline - currentCount) / fromIntegral baseline * 100.0
          putStrLn $ "📊 Baseline: " <> show baseline <> ", Current: " <> show currentCount
            <> " (change: " <> show (negate (round dropPercent :: Int)) <> "%)"
          when (dropPercent > maxFileDropPercent) $ do
            let msg = "🛑 CIRCUIT BREAKER: Vault lost " <> show (round dropPercent :: Int)
                  <> "% of files (baseline: " <> show baseline <> ", current: "
                  <> show currentCount <> ", threshold: "
                  <> show (round maxFileDropPercent :: Int) <> "%)."
                  <> " Refusing to push to prevent catastrophic data loss."
            putStrLn msg
            throwIO $ userError msg

minSafeFileCount :: Int
minSafeFileCount = 50

maxFileDropPercent :: Double
maxFileDropPercent = 30.0

countVaultFiles :: FilePath -> IO Int
countVaultFiles dir = do
  exists <- doesDirectoryExist dir
  case exists of
    False -> pure 0
    True  -> countFilesRecursive dir

countFilesRecursive :: FilePath -> IO Int
countFilesRecursive dir = do
  entries <- listDirectory dir
  let visible = filter (\e -> case e of { '.':_ -> False; _ -> True }) entries
  counts <- mapM (\entry -> do
    let fullPath = dir </> entry
    isDir <- doesDirectoryExist fullPath
    case isDir of
      True  -> countFilesRecursive fullPath
      False -> pure 1
    ) visible
  pure (sum counts)

vaultFileCountPath :: FilePath -> FilePath
vaultFileCountPath vaultDir = vaultDir </> ".vault-sync-file-count"

appendEmbedsToObsidianNote :: FilePath -> [(Text, Text, Text -> Text -> Text)] -> ObsidianCredentials -> IO ()
appendEmbedsToObsidianNote notePath sections creds = do
  vaultDir <- syncObsidianVault creds Nothing
  let filePath = vaultDir </> notePath
  exists <- doesFileExist filePath
  case exists of
    False -> throwIO $ userError $ "Note not found in Obsidian vault: " <> notePath <> " (looked at " <> filePath <> ")"
    True -> do
      content <- TIO.readFile filePath
      let (modified, newContent) = foldr (applySection content) (False, content) sections
      case modified of
        False -> putStrLn "No new sections to add to Obsidian note"
        True -> do
          TIO.writeFile filePath newContent
          pushObsidianVault vaultDir (ocAuthToken creds)
  where
    applySection _origContent (header, embedHtml, buildSection) (anyMod, currentContent) =
      case T.isInfixOf header currentContent of
        True  -> (anyMod, currentContent)
        False -> (True, currentContent <> buildSection currentContent embedHtml)
