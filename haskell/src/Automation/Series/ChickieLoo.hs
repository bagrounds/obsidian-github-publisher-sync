module Automation.Series.ChickieLoo (series) where

import Data.List.NonEmpty (NonEmpty ((:|)))
import Data.Time.LocalTime (TimeOfDay (..))

import qualified Automation.Gemini as Gemini
import Automation.BlogSeriesDiscovery (DiscoveredSeries (..))
import Automation.ContextQuery (defaultContextQueries)

series :: DiscoveredSeries
series = DiscoveredSeries
  { seriesId        = "chickie-loo"
  , seriesName      = "Chickie Loo"
  , seriesIcon      = "🐔"
  , priorityUser    = Just "ChickieLoo"
  , scheduleTime    = TimeOfDay 7 0 0
  , modelChain      = Gemini.Gemini31FlashLite :| [Gemini.Gemini3Flash]
  , contextQueries  = defaultContextQueries "chickie-loo"
  , searchGrounding = False
  }
