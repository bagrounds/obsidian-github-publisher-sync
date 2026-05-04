module Automation.Series.Convergence (series) where

import Data.List.NonEmpty (NonEmpty ((:|)))
import Data.Text (Text)
import Data.Time.LocalTime (TimeOfDay (..))

import qualified Automation.Gemini as Gemini
import Automation.BlogSeriesDiscovery (DiscoveredSeries (..))
import Automation.ContextQuery (ContextQuery (..), OrderBy (..), Field (..), SortDirection (..))

latestPosts :: [Text] -> Maybe Int -> Maybe Int -> ContextQuery
latestPosts directories' globalLimit perSourceLimit = ContextQuery
  { directories    = directories'
  , conditions     = []
  , orderBy        = OrderBy Filename Descending
  , limit          = globalLimit
  , limitPerSource = perSourceLimit
  }

series :: DiscoveredSeries
series = DiscoveredSeries
  { seriesId        = "convergence"
  , seriesName      = "Convergence"
  , seriesIcon      = "🔀"
  , priorityUser    = Just "bagrounds"
  , scheduleTime    = TimeOfDay 16 0 0
  , modelChain      = Gemini.Gemini25Flash :| [Gemini.Gemini25FlashLite, Gemini.Gemini31FlashLite]
  , contextQueries  =
      [ latestPosts ["convergence"] (Just 7) Nothing
      , latestPosts ["auto-blog-zero", "chickie-loo", "the-noise", "positivity-bias", "systems-for-public-good"] Nothing (Just 1)
      ]
  , searchGrounding = True
  }
