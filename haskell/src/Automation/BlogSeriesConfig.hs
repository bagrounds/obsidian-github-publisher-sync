module Automation.BlogSeriesConfig
  ( BlogSeriesConfig (..)
  , lookupSeriesIn
  , extraContentDirs
  , backfillContentIdsFrom
  , imageBackfillContentDirsFrom
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import Data.Time.LocalTime (TimeOfDay)

import Automation.BlogImage.ContentDirectory (ContentDirectory (..), contentDirectoryFromText, contentDirectoryToText)
import Automation.ContextQuery (ContextQuery)

data BlogSeriesConfig = BlogSeriesConfig
  { bscId             :: Text
  , bscName           :: Text
  , bscIcon           :: Text
  , bscAuthor         :: Text
  , bscBaseUrl        :: Text
  , bscPriorityUser   :: Maybe Text
  , bscNavLink        :: Text
  , bscScheduleTime   :: TimeOfDay
  , bscContextQueries :: [ContextQuery]
  } deriving (Show, Eq)

lookupSeriesIn :: Map Text BlogSeriesConfig -> Text -> Either Text BlogSeriesConfig
lookupSeriesIn seriesMap seriesId =
  maybe (Left errMsg) Right (Map.lookup seriesId seriesMap)
  where
    errMsg = "Unknown blog series: " <> seriesId
      <> ". Available: " <> mconcat (fmap (<> " ") (Map.keys seriesMap))

extraContentDirs :: [ContentDirectory]
extraContentDirs = [Reflections, AiBlog]

backfillContentIdsFrom :: [BlogSeriesConfig] -> [Text]
backfillContentIdsFrom allSeries =
  fmap contentDirectoryToText extraContentDirs <> fmap bscId allSeries

libraryContentDirs :: [ContentDirectory]
libraryContentDirs =
  [ Articles, Books, BotChats, Games
  , Products, Software, Tools, Topics
  ]

imageBackfillContentDirsFrom :: [BlogSeriesConfig] -> [ContentDirectory]
imageBackfillContentDirsFrom allSeries =
  extraContentDirs
    <> fmap (contentDirectoryFromText . bscId) allSeries
    <> libraryContentDirs
