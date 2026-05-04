module Automation.Series.TheNoise (series) where

import Data.List.NonEmpty (NonEmpty ((:|)))
import Data.Text (Text)
import Data.Time.LocalTime (TimeOfDay (..))

import qualified Automation.Gemini as Gemini
import Automation.BlogSeriesDiscovery (AutoBlogSeries (..))
import Automation.ContextQuery (defaultContextQueries)

identifier :: Text
identifier = "the-noise"

series :: AutoBlogSeries
series = AutoBlogSeries
  { seriesId        = identifier
  , seriesName      = "The Noise"
  , seriesIcon      = "📰"
  , priorityUser    = Just "bagrounds"
  , scheduleTime    = TimeOfDay 6 0 0
  , modelChain      = Gemini.Gemini25Flash :| [Gemini.Gemini25FlashLite, Gemini.Gemini31FlashLite]
  , contextQueries  = defaultContextQueries identifier
  , searchGrounding = True
  }
