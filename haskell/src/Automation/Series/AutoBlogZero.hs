module Automation.Series.AutoBlogZero (series, identifier) where

import Data.List.NonEmpty (NonEmpty ((:|)))
import Data.Text (Text)
import Data.Time.LocalTime (TimeOfDay (..))

import qualified Automation.Gemini as Gemini
import Automation.BlogSeriesDiscovery (DiscoveredSeries (..))
import Automation.ContextQuery (defaultContextQueries)

identifier :: Text
identifier = "auto-blog-zero"

series :: DiscoveredSeries
series = DiscoveredSeries
  { seriesId        = identifier
  , seriesName      = "Auto Blog Zero"
  , seriesIcon      = "🤖"
  , priorityUser    = Just "bagrounds"
  , scheduleTime    = TimeOfDay 8 0 0
  , modelChain      = Gemini.Gemini31FlashLite :| [Gemini.Gemini3Flash]
  , contextQueries  = defaultContextQueries identifier
  , searchGrounding = False
  }
