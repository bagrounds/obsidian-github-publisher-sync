module Automation.BlogSeriesConfig
  ( BlogSeriesConfig (..)
  , lookupSeriesIn
  , extraContentDirectories
  , backfillContentIdsFrom
  , imageBackfillContentDirectoriesFrom
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import Data.Time.LocalTime (TimeOfDay)

import Automation.BlogImage.ContentDirectory (ContentDirectory (..), contentDirectoryFromText, contentDirectoryToText)
import Automation.ContextQuery (ContextQuery)

data BlogSeriesConfig = BlogSeriesConfig
  { identifier      :: Text
  , name            :: Text
  , icon            :: Text
  , author          :: Text
  , baseUrl         :: Text
  , priorityUser    :: Maybe Text
  , navLink         :: Text
  , scheduleTime    :: TimeOfDay
  , contextQueries  :: [ContextQuery]
  } deriving (Show, Eq)

lookupSeriesIn :: Map Text BlogSeriesConfig -> Text -> Either Text BlogSeriesConfig
lookupSeriesIn seriesMap seriesId =
  maybe (Left errorMessage) Right (Map.lookup seriesId seriesMap)
  where
    errorMessage = "Unknown blog series: " <> seriesId
      <> ". Available: " <> mconcat (fmap (<> " ") (Map.keys seriesMap))

extraContentDirectories :: [ContentDirectory]
extraContentDirectories = [Reflections, AiBlog]

backfillContentIdsFrom :: [BlogSeriesConfig] -> [Text]
backfillContentIdsFrom allSeries =
  fmap contentDirectoryToText extraContentDirectories <> fmap identifier allSeries

libraryContentDirectories :: [ContentDirectory]
libraryContentDirectories =
  [ Articles, Books, BotChats, Games
  , Products, Software, Tools, Topics
  ]

imageBackfillContentDirectoriesFrom :: [BlogSeriesConfig] -> [ContentDirectory]
imageBackfillContentDirectoriesFrom allSeries =
  extraContentDirectories
    <> fmap (contentDirectoryFromText . identifier) allSeries
    <> libraryContentDirectories
