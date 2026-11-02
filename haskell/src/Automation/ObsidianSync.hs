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
  , EmbedWriteOutcome (..)
  , writeEmbedsToNote
  , appendEmbedsToObsidianNote
  , countVaultFiles
  , vaultFileCountPath
  ) where

import Control.Concurrent (threadDelay)
import Control.Exception (SomeException, catch, throwIO, try)
import Control.Monad (void, when)
import Data.List (intercalate)
import Data.List.NonEmpty (NonEmpty (..))
import qualified Data.List.NonEmpty as NonEmpty
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Data.Time (NominalDiffTime, diffUTCTime, getCurrentTime)
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
import qualified Automation.GitHubStepSummary as StepSummary
import qualified Automation.ObsidianSync.Report as Report
import qualified Automation.ObsidianSync.Retry as Retry
import System.Posix.Process (getProcessID)
import System.Process
  ( proc
  , readProcess
  , readCreateProcessWithExitCode
  , readProcessWithExitCode
  , CreateProcess (..)
  )
import System.Random (randomRIO)

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
    joinLines = foldr (\first rest -> first <> "\n" <> rest) ""

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
    Right pids -> filter (\pid -> not (null pid) && pid /= myPid) $ lines pids

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

runObSyncWithRetry :: Report.Direction -> [String] -> [(String, String)] -> FilePath
  -> IO (Either (Report.Report, SomeException) Report.Report)
runObSyncWithRetry direction args env vaultDirectory = do
  startedAt <- getCurrentTime
  runAttempt startedAt []
  where
    runAttempt startedAt previousAttempts = do
      attemptStartedAt <- getCurrentTime
      filesBefore <- Retry.FileCount <$> countVaultFiles vaultDirectory
      result <- try $ runObCommand args Nothing env :: IO (Either SomeException (String, String))
      filesAfter <- Retry.FileCount <$> countVaultFiles vaultDirectory
      finishedAt <- getCurrentTime
      jitter <- Retry.mkJitter <$> randomRIO (0, 1)
      let attempt = Retry.Attempt
            { Retry.outcome = either (Retry.Failed . Retry.classifySyncFailure . T.pack . show) (const Retry.Succeeded) result
            , Retry.filesBefore
            , Retry.filesAfter
            , Retry.duration = diffUTCTime finishedAt attemptStartedAt
            }
          attempts = NonEmpty.prependList previousAttempts (attempt :| [])
          elapsed = diffUTCTime finishedAt startedAt
          report stopReason = Report.Report { Report.direction = direction, Report.attempts, Report.stopReason, Report.elapsed }
      case Retry.decide Retry.syncPolicy jitter elapsed attempts of
        Retry.RetryAfter delay -> do
          TIO.putStrLn $ describeRetry attempt (NonEmpty.length attempts) elapsed delay
          ensureSyncClean vaultDirectory
          threadDelay (round (delay * 1000000))
          runAttempt startedAt (NonEmpty.toList attempts)
        Retry.Stop stopReason ->
          pure $ either (\failure -> Left (report stopReason, failure)) (const (Right (report stopReason))) result

describeRetry :: Retry.Attempt -> Int -> NominalDiffTime -> NominalDiffTime -> Text
describeRetry attempt@Retry.Attempt { Retry.outcome, Retry.filesAfter = Retry.FileCount filesOnDisk, Retry.duration } attemptNumber elapsed delay =
  Report.describeOutcome outcome
    <> " on attempt " <> Report.formatCount attemptNumber
    <> " after " <> Report.formatDuration duration
    <> " (" <> Report.formatGain (Retry.filesGained attempt) <> " files, "
    <> Report.formatCount filesOnDisk <> " on disk, "
    <> Report.formatDuration elapsed <> " elapsed), resuming in "
    <> Report.formatDuration delay <> "..."

publishSyncReport :: Report.Report -> IO ()
publishSyncReport report = do
  TIO.putStrLn (Report.headline report)
  written <- StepSummary.locateSummaryFile
    >>= either (pure . Left) (`StepSummary.appendMarkdown` Report.render report)
  TIO.putStrLn $ either StepSummary.describeError (const "📝 Sync report appended to the job summary") written

syncWithReport :: Report.Direction -> FilePath -> [(String, String)] -> IO ()
syncWithReport direction vaultDirectory env = do
  result <- runObSyncWithRetry direction ["sync", "--path", vaultDirectory] env vaultDirectory
  publishSyncReport (either fst id result)
  either (throwIO . snd) (const (pure ())) result

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
  syncWithReport Report.Pull vaultDirectory env
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
  syncWithReport Report.Push vaultDirectory env
  threadDelay 1000000
  ensureSyncClean vaultDirectory

validatePrePushFileCount :: FilePath -> Int -> IO ()
validatePrePushFileCount vaultDirectory currentCount = do
  let markerPath = vaultFileCountPath vaultDirectory
  markerExists <- doesFileExist markerPath
  if markerExists
    then do
      baselineContent <- readFile markerPath
      let mBaseline = case reads baselineContent of
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

data EmbedWriteOutcome
  = EmbedsAppended
  | NoNewEmbeds
  | NoteMissing
  deriving (Show, Eq)

writeEmbedsToNote :: FilePath -> [(Text, Text, Text -> Text -> Text)] -> IO EmbedWriteOutcome
writeEmbedsToNote filePath sections = do
  exists <- doesFileExist filePath
  if exists
    then do
      content <- TIO.readFile filePath
      let (modified, newContent) = foldr applySection (False, content) sections
      if modified
        then TIO.writeFile filePath newContent >> pure EmbedsAppended
        else putStrLn "No new sections to add to note" >> pure NoNewEmbeds
    else do
      putStrLn $ "⚠️ Note not found, skipping embed write: " <> filePath
      pure NoteMissing
  where
    applySection (header, embedHtml, buildSection) (anyMod, currentContent) =
      if T.isInfixOf header currentContent
        then (anyMod, currentContent)
        else (True, currentContent <> buildSection currentContent embedHtml)

appendEmbedsToObsidianNote :: FilePath -> [(Text, Text, Text -> Text -> Text)] -> ObsidianCredentials -> IO ()
appendEmbedsToObsidianNote notePath sections creds = do
  vaultDirectory <- syncObsidianVault creds
  void (writeEmbedsToNote (vaultDirectory </> notePath) sections)
  pushObsidianVault vaultDirectory (ocAuthToken creds)
