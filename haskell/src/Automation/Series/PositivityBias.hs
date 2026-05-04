module Automation.Series.PositivityBias (series) where

import Data.List.NonEmpty (NonEmpty ((:|)))
import Data.Text (Text)
import Data.Time.LocalTime (TimeOfDay (..))

import qualified Automation.Gemini as Gemini
import Automation.BlogSeriesDiscovery (AutoBlogSeries (..))
import Automation.ContextQuery (defaultContextQueries)

identifier :: Text
identifier = "positivity-bias"

series :: AutoBlogSeries
series = AutoBlogSeries
  { seriesId        = identifier
  , seriesName      = "Positivity Bias"
  , seriesIcon      = "🌟"
  , priorityUser    = Just "bagrounds"
  , scheduleTime    = TimeOfDay 6 0 0
  , modelChain      = Gemini.Gemini25Flash :| [Gemini.Gemini25FlashLite, Gemini.Gemini31FlashLite]
  , contextQueries  = defaultContextQueries identifier
  , searchGrounding = True
  }
