module Automation.BlogSeriesDiscovery
  ( AutoBlogSeries (..)
  , deriveBlogSeriesConfig
  , deriveBlogSeriesRunConfig
  , deriveScheduleEntry
  , deriveTaskId
  , derivePriorityUserEnvVar
  , deriveAuthor
  , deriveBaseUrl
  , deriveNavLink
  ) where

import Data.List.NonEmpty (NonEmpty (..))
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.LocalTime (TimeOfDay (..), todHour)

import qualified Automation.Gemini as Gemini
import Automation.BlogSeriesConfig (BlogSeriesConfig (..))
import Automation.ContextQuery (ContextQuery)
import Automation.Scheduler (BlogSeriesRunConfig (BlogSeriesRunConfig), ScheduleEntry (..), TaskId (..))
import qualified Automation.Scheduler as Scheduler

data AutoBlogSeries = AutoBlogSeries
  { seriesId             :: Text
  , seriesName           :: Text
  , seriesIcon           :: Text
  , priorityUser         :: Maybe Text
  , scheduleTime         :: TimeOfDay
  , modelChain           :: NonEmpty Gemini.Model
  , contextQueries       :: [ContextQuery]
  , searchGrounding      :: Bool
  } deriving (Show, Eq)

deriveBlogSeriesConfig :: AutoBlogSeries -> BlogSeriesConfig
deriveBlogSeriesConfig AutoBlogSeries{..} = BlogSeriesConfig
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

deriveBlogSeriesRunConfig :: AutoBlogSeries -> BlogSeriesRunConfig
deriveBlogSeriesRunConfig AutoBlogSeries{..} = BlogSeriesRunConfig
  { Scheduler.seriesId          = seriesId
  , Scheduler.modelChain        = modelChain
  , Scheduler.priorityUserEnvVar = derivePriorityUserEnvVar seriesId
  , Scheduler.searchGrounding   = searchGrounding
  }

deriveScheduleEntry :: AutoBlogSeries -> ScheduleEntry
deriveScheduleEntry AutoBlogSeries{..} = ScheduleEntry
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
