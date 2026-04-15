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
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Time.LocalTime (TimeOfDay (..), todHour)
import System.Directory (doesDirectoryExist, listDirectory)
import System.FilePath ((</>), dropExtension, takeExtension)

import qualified Automation.Gemini as Gemini
import Automation.Json (FromValue (..), withObject, (.:), (.:?), eitherDecodeStrict)
import Automation.BlogSeriesConfig (BlogSeriesConfig (..))
import Automation.ContextQuery (ContextQuery, defaultContextQueries)
import Automation.Scheduler (BlogSeriesRunConfig (..), ScheduleEntry (..), TaskId (..))

configDirectoryName :: FilePath
configDirectoryName = "series"

data DiscoveredSeries = DiscoveredSeries
  { dsId                 :: Text
  , dsName               :: Text
  , dsIcon               :: Text
  , dsPriorityUser       :: Maybe Text
  , dsScheduleTime       :: TimeOfDay
  , dsModels             :: NonEmpty Gemini.Model
  , dsContextQueries     :: [ContextQuery]
  } deriving (Show, Eq)

data DiscoveryError
  = JsonParseError FilePath String
  | ValidationError FilePath Text
  deriving (Show)

data RawConfig = RawConfig
  { rcName               :: Text
  , rcIcon               :: Text
  , rcPriorityUser       :: Maybe Text
  , rcScheduleHourPacific :: Int
  , rcModels             :: [Text]
  , rcContextSources     :: Maybe [ContextQuery]
  }

instance FromValue RawConfig where
  fromValue = withObject "series config" $ \obj -> do
    rcName <- obj .: "name"
    rcIcon <- obj .: "icon"
    rcPriorityUser <- obj .:? "priorityUser"
    rcScheduleHourPacific <- obj .: "scheduleHourPacific"
    rcModels <- obj .: "models"
    rcContextSources <- obj .:? "contextSources"
    pure RawConfig{..}

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
        then pure (Right (sortOn dsId successes))
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
validateRawConfig filePath seriesId RawConfig{..} =
  let errors =
        (case rcScheduleHourPacific of
            hour | hour < 0 || hour > 23 ->
              [ValidationError filePath ("scheduleHourPacific must be 0-23, got: " <> T.pack (show hour))]
            _ -> [])
        ++ (case rcModels of
            [] -> [ValidationError filePath "models list must not be empty"]
            _ -> [])
  in if null errors
    then case rcModels of
      (firstModel : restModels) ->
        Right DiscoveredSeries
          { dsId = seriesId
          , dsName = rcName
          , dsIcon = rcIcon
          , dsPriorityUser = rcPriorityUser
          , dsScheduleTime = TimeOfDay rcScheduleHourPacific 0 0
          , dsModels = Gemini.modelFromText firstModel :| fmap Gemini.modelFromText restModels
          , dsContextQueries = maybe defaultContextQueries id rcContextSources
          }
      _ -> Left errors
    else Left errors

deriveBlogSeriesConfig :: DiscoveredSeries -> BlogSeriesConfig
deriveBlogSeriesConfig DiscoveredSeries{..} = BlogSeriesConfig
  { bscId = dsId
  , bscName = dsName
  , bscIcon = dsIcon
  , bscAuthor = deriveAuthor dsId
  , bscBaseUrl = deriveBaseUrl dsId
  , bscPriorityUser = dsPriorityUser
  , bscNavLink = deriveNavLink dsId dsIcon dsName
  , bscScheduleTime = dsScheduleTime
  , bscContextQueries = dsContextQueries
  }

deriveBlogSeriesRunConfig :: DiscoveredSeries -> BlogSeriesRunConfig
deriveBlogSeriesRunConfig DiscoveredSeries{..} = BlogSeriesRunConfig
  { bsrcSeriesId = dsId
  , bsrcModelChain = dsModels
  , bsrcPriorityUserEnvVar = derivePriorityUserEnvVar dsId
  }

deriveScheduleEntry :: DiscoveredSeries -> ScheduleEntry
deriveScheduleEntry DiscoveredSeries{..} = ScheduleEntry
  { seTaskId = deriveTaskId dsId
  , seHoursPacific = [todHour dsScheduleTime]
  , seAtOrAfter = False
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
