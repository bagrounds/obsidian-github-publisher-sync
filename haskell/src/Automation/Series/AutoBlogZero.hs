module Automation.Series.AutoBlogZero (series) where

import Data.List.NonEmpty (NonEmpty ((:|)))
import Data.Time.LocalTime (TimeOfDay (..))

import qualified Automation.Gemini as Gemini
import Automation.BlogSeriesDiscovery (DiscoveredSeries (..))
import Automation.ContextQuery (defaultContextQueries)

series :: DiscoveredSeries
series = DiscoveredSeries
  { seriesId        = "auto-blog-zero"
  , seriesName      = "Auto Blog Zero"
  , seriesIcon      = "🤖"
  , priorityUser    = Just "bagrounds"
  , scheduleTime    = TimeOfDay 8 0 0
  , modelChain      = Gemini.Gemini31FlashLite :| [Gemini.Gemini3Flash]
  , contextQueries  = defaultContextQueries "auto-blog-zero"
  , searchGrounding = False
  }
