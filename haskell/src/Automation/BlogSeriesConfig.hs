module Automation.BlogSeriesConfig
  ( BlogSeriesConfig (..)
  , lookupSeriesIn
  , extraContentDirs
  , backfillContentIdsFrom
  , imageBackfillContentIdsFrom
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)

data BlogSeriesConfig = BlogSeriesConfig
  { bscId           :: Text
  , bscName         :: Text
  , bscIcon         :: Text
  , bscAuthor       :: Text
  , bscBaseUrl      :: Text
  , bscPriorityUser :: Maybe Text
  , bscNavLink      :: Text
  , bscScheduleHourPacific :: Int
  } deriving (Show, Eq)

lookupSeriesIn :: Map Text BlogSeriesConfig -> Text -> Either Text BlogSeriesConfig
lookupSeriesIn seriesMap seriesId =
  maybe (Left errMsg) Right (Map.lookup seriesId seriesMap)
  where
    errMsg = "Unknown blog series: " <> seriesId
      <> ". Available: " <> mconcat (fmap (<> " ") (Map.keys seriesMap))

extraContentDirs :: [Text]
extraContentDirs = ["reflections", "ai-blog"]

backfillContentIdsFrom :: [BlogSeriesConfig] -> [Text]
backfillContentIdsFrom allSeries = extraContentDirs <> fmap bscId allSeries

libraryContentDirs :: [Text]
libraryContentDirs =
  [ "articles", "books", "bot-chats", "games"
  , "products", "software", "tools", "topics"
  ]

imageBackfillContentIdsFrom :: [BlogSeriesConfig] -> [Text]
imageBackfillContentIdsFrom allSeries = backfillContentIdsFrom allSeries <> libraryContentDirs
