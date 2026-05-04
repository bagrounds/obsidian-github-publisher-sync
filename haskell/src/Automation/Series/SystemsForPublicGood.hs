module Automation.Series.SystemsForPublicGood (series) where

import Data.List.NonEmpty (NonEmpty ((:|)))
import Data.Time.LocalTime (TimeOfDay (..))

import qualified Automation.Gemini as Gemini
import Automation.BlogSeriesDiscovery (DiscoveredSeries (..))
import Automation.ContextQuery (defaultContextQueries)

series :: DiscoveredSeries
series = DiscoveredSeries
  { seriesId        = "systems-for-public-good"
  , seriesName      = "Systems for Public Good"
  , seriesIcon      = "🏛️"
  , priorityUser    = Just "bagrounds"
  , scheduleTime    = TimeOfDay 9 0 0
  , modelChain      = Gemini.Gemini25Flash :| [Gemini.Gemini25FlashLite, Gemini.Gemini31FlashLite]
  , contextQueries  = defaultContextQueries "systems-for-public-good"
  , searchGrounding = True
  }
