module Automation.Series.Convergence (series) where

import Data.List.NonEmpty (NonEmpty ((:|)))
import Data.Time.LocalTime (TimeOfDay (..))

import qualified Automation.Gemini as Gemini
import Automation.BlogSeriesDiscovery (DiscoveredSeries (..))
import Automation.ContextQuery (ContextQuery (..), OrderBy (..), Field (..), SortDirection (..))

series :: DiscoveredSeries
series = DiscoveredSeries
  { seriesId        = "convergence"
  , seriesName      = "Convergence"
  , seriesIcon      = "🔀"
  , priorityUser    = Just "bagrounds"
  , scheduleTime    = TimeOfDay 16 0 0
  , modelChain      = Gemini.Gemini25Flash :| [Gemini.Gemini25FlashLite, Gemini.Gemini31FlashLite]
  , contextQueries  =
      [ ContextQuery
          { directories    = ["convergence"]
          , conditions     = []
          , orderBy        = OrderBy Filename Descending
          , limit          = Just 7
          , limitPerSource = Nothing
          }
      , ContextQuery
          { directories    = ["auto-blog-zero", "chickie-loo", "the-noise", "positivity-bias", "systems-for-public-good"]
          , conditions     = []
          , orderBy        = OrderBy Filename Descending
          , limit          = Nothing
          , limitPerSource = Just 1
          }
      ]
  , searchGrounding = True
  }
