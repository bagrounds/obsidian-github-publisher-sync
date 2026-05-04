module Automation.Series.Convergence (series) where

import Data.List.NonEmpty (NonEmpty ((:|)))
import Data.Text (Text)
import Data.Time.LocalTime (TimeOfDay (..))

import qualified Automation.Gemini as Gemini
import Automation.BlogSeriesDiscovery (AutoBlogSeries (..), seriesId)
import Automation.ContextQuery (ContextQuery (..), OrderBy (..), Field (..), SortDirection (..))
import qualified Automation.Series.AutoBlogZero as AutoBlogZero
import qualified Automation.Series.ChickieLoo as ChickieLoo
import qualified Automation.Series.PositivityBias as PositivityBias
import qualified Automation.Series.SystemsForPublicGood as SystemsForPublicGood
import qualified Automation.Series.TheNoise as TheNoise

identifier :: Text
identifier = "convergence"

series :: AutoBlogSeries
series = AutoBlogSeries
  { seriesId        = identifier
  , seriesName      = "Convergence"
  , seriesIcon      = "🔀"
  , priorityUser    = Just "bagrounds"
  , scheduleTime    = TimeOfDay 16 0 0
  , modelChain      = Gemini.Gemini25Flash :| [Gemini.Gemini25FlashLite, Gemini.Gemini31FlashLite]
  , contextQueries  =
      [ ContextQuery
          { directories    = [identifier]
          , conditions     = []
          , orderBy        = OrderBy Filename Descending
          , limit          = Just 7
          , limitPerSource = Nothing
          }
      , ContextQuery
          { directories    = [ seriesId AutoBlogZero.series
                              , seriesId ChickieLoo.series
                              , seriesId TheNoise.series
                              , seriesId PositivityBias.series
                              , seriesId SystemsForPublicGood.series
                              ]
          , conditions     = []
          , orderBy        = OrderBy Filename Descending
          , limit          = Nothing
          , limitPerSource = Just 1
          }
      ]
  , searchGrounding = True
  }
