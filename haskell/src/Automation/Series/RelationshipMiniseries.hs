module Automation.Series.RelationshipMiniseries (series) where

import Data.List.NonEmpty (NonEmpty ((:|)))
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import Data.Time (DayOfWeek (..))
import Data.Time.LocalTime (TimeOfDay (..))

import qualified Automation.Gemini as Gemini
import Automation.BlogSeriesDiscovery (AutoBlogSeries (..))
import Automation.ContextQuery (defaultContextQueries)
import Automation.Scheduler (DayConfig (..))

identifier :: Text
identifier = "relationship-miniseries"

researchDayConfig :: DayConfig
researchDayConfig = DayConfig
  { dayModelChain      = Gemini.Gemini25Flash :| [Gemini.Gemini25FlashLite, Gemini.Gemini31FlashLite]
  , daySearchGrounding = True
  }

researchDayOverrides :: Map DayOfWeek DayConfig
researchDayOverrides = Map.fromList
  [ (Monday,  researchDayConfig)
  , (Tuesday, researchDayConfig)
  ]

series :: AutoBlogSeries
series = AutoBlogSeries
  { seriesId        = identifier
  , seriesName      = "Relationship Miniseries"
  , seriesIcon      = "💑"
  , priorityUser    = Just "bagrounds"
  , scheduleTime    = TimeOfDay 10 0 0
  , modelChain      = Gemini.Gemini31FlashLite :| [Gemini.Gemini3Flash]
  , contextQueries  = defaultContextQueries identifier
  , searchGrounding = False
  , dayOverrides    = researchDayOverrides
  }
