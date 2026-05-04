module Automation.Series.TheNoise (series) where

import Data.List.NonEmpty (NonEmpty ((:|)))
import Data.Time.LocalTime (TimeOfDay (..))

import qualified Automation.Gemini as Gemini
import Automation.BlogSeriesDiscovery (DiscoveredSeries (..))
import Automation.ContextQuery (defaultContextQueries)

series :: DiscoveredSeries
series = DiscoveredSeries
  { seriesId        = "the-noise"
  , seriesName      = "The Noise"
  , seriesIcon      = "📰"
  , priorityUser    = Just "bagrounds"
  , scheduleTime    = TimeOfDay 6 0 0
  , modelChain      = Gemini.Gemini25Flash :| [Gemini.Gemini25FlashLite, Gemini.Gemini31FlashLite]
  , contextQueries  = defaultContextQueries "the-noise"
  , searchGrounding = True
  }
