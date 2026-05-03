module Automation.BlogSeriesDiscovery
  ( DiscoveredSeries (..)
  , DiscoveryError (..)
  , parseSeriesConfig
  , discoverSeries
  , deriveBlogSeriesConfig
  , deriveBlogSeriesRunConfig
  , deriveScheduleEntry
  , deriveTaskId
  , derivePriorityUserEnvVar
  , deriveAuthor
  , deriveBaseUrl
  , deriveNavLink
  , configDirectoryName
  ) where

import qualified Data.ByteString as BS
import Data.List (sortOn)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Time.LocalTime (TimeOfDay (..), todHour)
import System.Directory (doesDirectoryExist, listDirectory)
import System.FilePath ((</>), dropExtension, takeExtension)

import qualified Automation.Gemini as Gemini
import Automation.Json (eitherDecodeStrict)
import Automation.BlogSeriesConfig (BlogSeriesConfig (..))
import Automation.BlogSeriesDiscovery.RawConfig (RawConfig (..))
import Automation.ContextQuery (ContextQuery, defaultContextQueries)
import Automation.Scheduler (BlogSeriesRunConfig (BlogSeriesRunConfig), ScheduleEntry (..), TaskId (..))
import qualified Automation.Scheduler as Scheduler

configDirectoryName :: FilePath
configDirectoryName = "series"

data DiscoveredSeries = DiscoveredSeries
  { seriesId             :: Text
  , seriesName           :: Text
  , seriesIcon           :: Text
  , priorityUser         :: Maybe Text
  , scheduleTime         :: TimeOfDay
  , modelChain           :: NonEmpty Gemini.Model
  , contextQueries       :: [ContextQuery]
  , searchGrounding      :: Bool
  } deriving (Show, Eq)

data DiscoveryError
  = JsonParseError FilePath String
  | ValidationError FilePath Text
  deriving (Show)

discoverSeries :: FilePath -> IO (Either [DiscoveryError] [DiscoveredSeries])
discoverSeries baseDir = do
  let seriesDir = baseDir </> configDirectoryName
  exists <- doesDirectoryExist seriesDir
  if not exists
    then pure (Right [])
    else do
      entries <- listDirectory seriesDir
      let jsonFiles = filter isJsonFile entries
      results <- traverse (parseSeriesFile seriesDir) jsonFiles
      let errors = concatMap (\case Left errs -> errs; Right _ -> []) results
          successes = concatMap (\case Right series -> [series]; Left _ -> []) results
      if null errors
        then pure (Right (sortOn seriesId successes))
        else pure (Left errors)

isJsonFile :: FilePath -> Bool
isJsonFile path = takeExtension path == ".json"

parseSeriesFile :: FilePath -> FilePath -> IO (Either [DiscoveryError] DiscoveredSeries)
parseSeriesFile seriesDir filename = do
  let filePath = seriesDir </> filename
      seriesId = T.pack (dropExtension filename)
  content <- BS.readFile filePath
  pure $ case eitherDecodeStrict content of
    Left parseError -> Left [JsonParseError filePath parseError]
    Right rawConfig -> validateRawConfig filePath seriesId rawConfig

parseSeriesConfig :: Text -> Text -> Either [DiscoveryError] DiscoveredSeries
parseSeriesConfig seriesId content =
  case eitherDecodeStrict (TE.encodeUtf8 content) of
    Left parseError -> Left [JsonParseError "<input>" parseError]
    Right rawConfig -> validateRawConfig "<input>" seriesId rawConfig

validateRawConfig :: FilePath -> Text -> RawConfig -> Either [DiscoveryError] DiscoveredSeries
validateRawConfig filePath seriesIdValue RawConfig{..} =
  let errors =
        (case scheduleHourPacific of
            hour | hour < 0 || hour > 23 ->
              [ValidationError filePath ("scheduleHourPacific must be 0-23, got: " <> T.pack (show hour))]
            _ -> [])
        ++ (case models of
            [] -> [ValidationError filePath "models list must not be empty"]
            _ -> [])
  in if null errors
    then case models of
      (firstModel : restModels) ->
        Right DiscoveredSeries
          { seriesId = seriesIdValue
          , seriesName = name
          , seriesIcon = icon
          , priorityUser = priorityUser
          , scheduleTime = TimeOfDay scheduleHourPacific 0 0
          , modelChain = Gemini.modelFromText firstModel :| fmap Gemini.modelFromText restModels
          , contextQueries = fromMaybe (defaultContextQueries seriesIdValue) contextSources
          , searchGrounding = enableGrounding
          }
      _ -> Left errors
    else Left errors

deriveBlogSeriesConfig :: DiscoveredSeries -> BlogSeriesConfig
deriveBlogSeriesConfig DiscoveredSeries{..} = BlogSeriesConfig
  { identifier     = seriesId
  , name           = seriesName
  , icon           = seriesIcon
  , author         = deriveAuthor seriesId
  , baseUrl        = deriveBaseUrl seriesId
  , priorityUser   = priorityUser
  , navLink        = deriveNavLink seriesId seriesIcon seriesName
  , scheduleTime   = scheduleTime
  , contextQueries = contextQueries
  }

deriveBlogSeriesRunConfig :: DiscoveredSeries -> BlogSeriesRunConfig
deriveBlogSeriesRunConfig DiscoveredSeries{..} = BlogSeriesRunConfig
  { Scheduler.seriesId          = seriesId
  , Scheduler.modelChain        = modelChain
  , Scheduler.priorityUserEnvVar = derivePriorityUserEnvVar seriesId
  , Scheduler.searchGrounding   = searchGrounding
  }

deriveScheduleEntry :: DiscoveredSeries -> ScheduleEntry
deriveScheduleEntry DiscoveredSeries{..} = ScheduleEntry
  { taskId = deriveTaskId seriesId
  , hoursPacific = [todHour scheduleTime]
  , atOrAfter = False
  }

deriveTaskId :: Text -> TaskId
deriveTaskId = BlogSeries

deriveAuthor :: Text -> Text
deriveAuthor seriesId = "[[" <> seriesId <> "]]"

deriveBaseUrl :: Text -> Text
deriveBaseUrl seriesId = "https://bagrounds.org/" <> seriesId

deriveNavLink :: Text -> Text -> Text -> Text
deriveNavLink seriesId icon name =
  "[[index|Home]] > [[" <> seriesId <> "/index|" <> icon <> " " <> name <> "]]"

derivePriorityUserEnvVar :: Text -> Text
derivePriorityUserEnvVar seriesId =
  T.map toEnvChar (T.toUpper seriesId) <> "_PRIORITY_USER"
  where
    toEnvChar '-' = '_'
    toEnvChar c   = c
