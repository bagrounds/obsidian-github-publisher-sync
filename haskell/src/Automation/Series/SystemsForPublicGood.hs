module Automation.Series.SystemsForPublicGood (series, identifier) where

import Data.List.NonEmpty (NonEmpty ((:|)))
import Data.Text (Text)
import Data.Time.LocalTime (TimeOfDay (..))

import qualified Automation.Gemini as Gemini
import Automation.BlogSeriesDiscovery (DiscoveredSeries (..))
import Automation.ContextQuery (defaultContextQueries)

identifier :: Text
identifier = "systems-for-public-good"

series :: DiscoveredSeries
series = DiscoveredSeries
  { seriesId        = identifier
  , seriesName      = "Systems for Public Good"
  , seriesIcon      = "🏛️"
  , priorityUser    = Just "bagrounds"
  , scheduleTime    = TimeOfDay 9 0 0
  , modelChain      = Gemini.Gemini25Flash :| [Gemini.Gemini25FlashLite, Gemini.Gemini31FlashLite]
  , contextQueries  = defaultContextQueries identifier
  , searchGrounding = True
  }
