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
  ) where

import Control.Concurrent (threadDelay)
import Control.Exception (SomeException, catch, throwIO, try)
import Control.Monad (filterM, when)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Directory
  ( doesDirectoryExist
  , doesFileExist
  , removeDirectoryRecursive
  , createDirectoryIfMissing
  )
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.Process
  ( CreateProcess (..)
  , StdStream (..)
  , createProcess
  , proc
  , readProcess
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
  (exitCode, stdout, stderr) <- readProcessWithExitCode "ob" args ""
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
  let patterns = ["obsidian-headless"] <> maybe [] pure mVaultDir
  let grepPattern = foldr (\a b -> a <> "|" <> b) "" patterns
  result <- try $ readProcess "bash" ["-c",
    "ps -u $(id -u) -o pid,args 2>/dev/null | grep -E '" <> grepPattern <> "' | grep -v grep | awk '{print $1}'"
    ] "" :: IO (Either SomeException String)
  pure $ case result of
    Left _     -> []
    Right pids -> filter (not . null) $ lines pids

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
        Right () -> pure vaultDir
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
  let setupArgs = ["sync-setup", "--vault", T.unpack $ ocVaultName creds, "--path", vaultDir]
        <> maybe [] (\pw -> ["--password", T.unpack pw]) (ocVaultPassword creds)
  putStrLn $ "🔧 Setting up Obsidian Sync for vault: " <> T.unpack (ocVaultName creds)
  _ <- runObCommand setupArgs Nothing env
  removeSyncLock vaultDir
  putStrLn "📥 Pulling latest vault content..."
  runObSyncWithRetry ["sync", "--path", vaultDir] env vaultDir 5
  pure vaultDir

pushObsidianVault :: FilePath -> Text -> IO ()
pushObsidianVault vaultDir authToken = do
  let env = [("OBSIDIAN_AUTH_TOKEN", T.unpack authToken)]
  ensureSyncClean vaultDir
  putStrLn "📤 Pushing changes to Obsidian Sync..."
  runObSyncWithRetry ["sync", "--path", vaultDir] env vaultDir 5
  threadDelay 1000000
  ensureSyncClean vaultDir

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
