module Main where

import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Network.HTTP.Client (newManager)
import Network.HTTP.Client.TLS (tlsManagerSettings)
import System.Environment (getArgs, lookupEnv)
import System.Exit (exitFailure)
import System.FilePath ((</>))
import System.IO (hSetBuffering, stdout, stderr, BufferMode(..))

import Automation.BlogSeriesConfig
  ( BlogSeriesConfig (..)
  , imageBackfillContentDirsFrom
  )
import Automation.BlogSeriesDiscovery
  ( DiscoveredSeries (..)
  , DiscoveryError (..)
  , deriveBlogSeriesConfig
  , deriveBlogSeriesRunConfig
  , deriveScheduleEntry
  , discoverSeries
  )
import Automation.CliArgs (CliArgs (..), parseCliArgs)
import qualified Automation.Context as Context
import Automation.Env (requireEnv, getObsidianCreds)
import Automation.ObsidianSync
  ( ObsidianCredentials (..)
  , syncObsidianVault
  , pushObsidianVault
  )
import Automation.Scheduler
  ( ScheduleEntry (..)
  , buildBlogSeriesRunConfigs
  , buildSchedule
  , getScheduledTasks
  , isValidTaskId
  , nowPacificHour
  , taskIdFromText
  , taskIdToText
  )
import Automation.Secret (Secret (..))
import Automation.TaskRunner (inferenceDashboards, runTasks, logMsg)
import Automation.TaskRunners (taskRunners)

main :: IO ()
main = do
  hSetBuffering stdout LineBuffering

  args <- parseCliArgs <$> getArgs
  hourPacific <- maybe nowPacificHour pure (cliHourOverride args)

  mRepoRoot <- lookupEnv "REPO_ROOT"
  mWorkspace <- lookupEnv "GITHUB_WORKSPACE"
  let repoRoot = case mRepoRoot of
        Just r  -> r
        Nothing -> fromMaybe "." mWorkspace
  manager <- newManager tlsManagerSettings

  let haskellDir = repoRoot </> "haskell"
  discoveryResult <- discoverSeries haskellDir
  discovered <- case discoveryResult of
    Right series -> do
      logMsg $ "📋 Discovered " <> T.pack (show (length series)) <> " blog series: "
        <> T.intercalate ", " (fmap seriesId series)
      pure series
    Left errors -> do
      TIO.hPutStrLn stderr "❌ Blog series discovery errors:"
      mapM_ (\case
        JsonParseError path err -> TIO.hPutStrLn stderr $ "  📄 " <> T.pack path <> ": " <> T.pack err
        ValidationError path msg -> TIO.hPutStrLn stderr $ "  ⚠️  " <> T.pack path <> ": " <> msg
        ) errors
      exitFailure

  let seriesConfigs = fmap deriveBlogSeriesConfig discovered
      seriesMap = Map.fromList (fmap (\config -> (bscId config, config)) seriesConfigs)
      runConfigs = buildBlogSeriesRunConfigs (fmap deriveBlogSeriesRunConfig discovered)
      dynamicScheduleEntries = fmap deriveScheduleEntry discovered
      fullSchedule = buildSchedule dynamicScheduleEntries
      contentDirs = imageBackfillContentDirsFrom seriesConfigs

  tasks <- case cliTaskOverride args of
    Just taskStr ->
      if isValidTaskId fullSchedule taskStr
        then case taskIdFromText (fmap taskId dynamicScheduleEntries) taskStr of
          Just tid -> pure [tid]
          Nothing  -> do
            TIO.hPutStrLn stderr $ "❌ Unknown task: " <> taskStr
            exitFailure
        else do
          TIO.hPutStrLn stderr $ "❌ Unknown task: " <> taskStr
          exitFailure
    Nothing -> pure $ getScheduledTasks fullSchedule hourPacific

  let taskNames = T.intercalate ", " (fmap taskIdToText tasks)
  logMsg $ "Scheduler start — hour " <> T.pack (show hourPacific) <> " Pacific, "
    <> T.pack (show (length tasks)) <> " task(s): " <> taskNames
  TIO.putStrLn "📊 Inference dashboards:"
  mapM_ (\(name, url) -> TIO.putStrLn $ "   " <> name <> ": " <> url) inferenceDashboards

  case tasks of
    [] -> do
      logMsg "  ⏭️  No tasks scheduled for this hour"
      pure ()
    _ -> do
      creds <- getObsidianCreds
      logMsg "📥 Pulling Obsidian vault..."
      vaultDir <- syncObsidianVault creds
      logMsg $ "📂 Vault ready at " <> T.pack vaultDir

      geminiApiKey <- Secret <$> requireEnv "GEMINI_API_KEY"
      context <- case Context.mkAppContext manager vaultDir repoRoot geminiApiKey creds of
        Right ctx -> pure ctx
        Left err -> do
          TIO.hPutStrLn stderr $ "❌ Invalid context: " <> T.pack err
          exitFailure
      let runners = taskRunners context seriesMap runConfigs contentDirs discovered
      results <- runTasks runners tasks

      logMsg "📤 Pushing Obsidian vault..."
      pushObsidianVault vaultDir (authToken creds)
      logMsg "📤 Vault pushed"

      let succeeded = length (filter (\(_, success, _) -> success) results)
          total = length results

      TIO.putStrLn "\n--- Run Summary ---"
      mapM_ (\(taskIdentifier, success, errorMessage) ->
        let icon = if success then "✅" else "❌"
            errorSuffix = maybe "" (" — " <>) errorMessage
        in TIO.putStrLn $ "  " <> icon <> " " <> taskIdToText taskIdentifier <> errorSuffix
        ) results
      TIO.putStrLn $ "  📊 " <> T.pack (show succeeded) <> "/" <> T.pack (show total) <> " succeeded"
      TIO.putStrLn "-------------------\n"
