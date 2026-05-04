module Automation.Series.ChickieLoo (series, identifier) where

import Data.List.NonEmpty (NonEmpty ((:|)))
import Data.Text (Text)
import Data.Time.LocalTime (TimeOfDay (..))

import qualified Automation.Gemini as Gemini
import Automation.BlogSeriesDiscovery (DiscoveredSeries (..))
import Automation.ContextQuery (defaultContextQueries)

identifier :: Text
identifier = "chickie-loo"

series :: DiscoveredSeries
series = DiscoveredSeries
  { seriesId        = identifier
  , seriesName      = "Chickie Loo"
  , seriesIcon      = "🐔"
  , priorityUser    = Just "ChickieLoo"
  , scheduleTime    = TimeOfDay 7 0 0
  , modelChain      = Gemini.Gemini31FlashLite :| [Gemini.Gemini3Flash]
  , contextQueries  = defaultContextQueries identifier
  , searchGrounding = False
  }
