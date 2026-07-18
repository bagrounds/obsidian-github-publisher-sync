module Automation.Series.VitalSignals (series) where

import Data.List.NonEmpty (NonEmpty ((:|)))
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import Data.Time.LocalTime (TimeOfDay (..))

import qualified Automation.Gemini as Gemini
import Automation.BlogSeriesDiscovery (AutoBlogSeries (..))
import Automation.ContextQuery (defaultContextQueries)

identifier :: Text
identifier = "vital-signals"

series :: AutoBlogSeries
series = AutoBlogSeries
  { seriesId        = identifier
  , seriesName      = "Vital Signals"
  , seriesIcon      = "⚡"
  , priorityUser    = Just "bagrounds"
  , scheduleTime    = TimeOfDay 5 0 0
  , modelChain      = Gemini.Gemini25Flash :| [Gemini.Gemini25FlashLite, Gemini.Gemini31FlashLite]
  , contextQueries  = defaultContextQueries identifier
  , searchGrounding = True
  , dayOverrides    = Map.empty
  }
