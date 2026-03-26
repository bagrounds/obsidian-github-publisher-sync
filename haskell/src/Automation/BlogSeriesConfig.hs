module Automation.BlogSeriesConfig
  ( BlogSeriesConfig (..)
  , blogSeries
  , blogSeriesMap
  , lookupSeries
  , extraContentDirs
  , backfillContentIds
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
  , bscPostTimeUtc  :: Text
  } deriving (Show, Eq)

autoBlogZero :: BlogSeriesConfig
autoBlogZero = BlogSeriesConfig
  { bscId           = "auto-blog-zero"
  , bscName         = "Auto Blog Zero"
  , bscIcon         = "🤖"
  , bscAuthor       = "[[auto-blog-zero]]"
  , bscBaseUrl      = "https://bagrounds.org/auto-blog-zero"
  , bscPriorityUser = Just "bagrounds"
  , bscNavLink      = "[[index|Home]] > [[auto-blog-zero/index|🤖 Auto Blog Zero]]"
  , bscPostTimeUtc  = "16:00"
  }

chickieLoo :: BlogSeriesConfig
chickieLoo = BlogSeriesConfig
  { bscId           = "chickie-loo"
  , bscName         = "Chickie Loo"
  , bscIcon         = "🐔"
  , bscAuthor       = "[[chickie-loo]]"
  , bscBaseUrl      = "https://bagrounds.org/chickie-loo"
  , bscPriorityUser = Just "ChickieLoo"
  , bscNavLink      = "[[index|Home]] > [[chickie-loo/index|🐔 Chickie Loo]]"
  , bscPostTimeUtc  = "15:00"
  }

systemsForPublicGood :: BlogSeriesConfig
systemsForPublicGood = BlogSeriesConfig
  { bscId           = "systems-for-public-good"
  , bscName         = "Systems for Public Good"
  , bscIcon         = "🏛️"
  , bscAuthor       = "[[systems-for-public-good]]"
  , bscBaseUrl      = "https://bagrounds.org/systems-for-public-good"
  , bscPriorityUser = Just "bagrounds"
  , bscNavLink      = "[[index|Home]] > [[systems-for-public-good/index|🏛️ Systems for Public Good]]"
  , bscPostTimeUtc  = "17:00"
  }

blogSeries :: [BlogSeriesConfig]
blogSeries = [autoBlogZero, chickieLoo, systemsForPublicGood]

blogSeriesMap :: Map Text BlogSeriesConfig
blogSeriesMap = Map.fromList $ fmap (\s -> (bscId s, s)) blogSeries

lookupSeries :: Text -> Either Text BlogSeriesConfig
lookupSeries seriesId =
  maybe (Left errMsg) Right (Map.lookup seriesId blogSeriesMap)
  where
    errMsg = "Unknown blog series: " <> seriesId
      <> ". Available: " <> mconcat (fmap (\s -> bscId s <> " ") blogSeries)

extraContentDirs :: [Text]
extraContentDirs = ["reflections", "ai-blog"]

backfillContentIds :: [Text]
backfillContentIds = extraContentDirs <> fmap bscId blogSeries
