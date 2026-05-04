module Automation.Series.PositivityBias (series) where

import Data.List.NonEmpty (NonEmpty ((:|)))
import Data.Time.LocalTime (TimeOfDay (..))

import qualified Automation.Gemini as Gemini
import Automation.BlogSeriesDiscovery (DiscoveredSeries (..))
import Automation.ContextQuery (defaultContextQueries)

series :: DiscoveredSeries
series = DiscoveredSeries
  { seriesId        = "positivity-bias"
  , seriesName      = "Positivity Bias"
  , seriesIcon      = "🌟"
  , priorityUser    = Just "bagrounds"
  , scheduleTime    = TimeOfDay 6 0 0
  , modelChain      = Gemini.Gemini25Flash :| [Gemini.Gemini25FlashLite, Gemini.Gemini31FlashLite]
  , contextQueries  = defaultContextQueries "positivity-bias"
  , searchGrounding = True
  }
