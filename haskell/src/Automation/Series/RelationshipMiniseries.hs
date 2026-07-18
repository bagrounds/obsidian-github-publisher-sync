module Automation.Series.RelationshipMiniseries (series) where

import Data.List.NonEmpty (NonEmpty ((:|)))
import Data.Text (Text)
import Data.Time.LocalTime (TimeOfDay (..))

import qualified Automation.Gemini as Gemini
import Automation.BlogSeriesDiscovery (AutoBlogSeries (..))
import Automation.ContextQuery (defaultContextQueries)

identifier :: Text
identifier = "relationship-miniseries"

series :: AutoBlogSeries
series = AutoBlogSeries
  { seriesId        = identifier
  , seriesName      = "Relationship Miniseries"
  , seriesIcon      = "💑"
  , priorityUser    = Just "bagrounds"
  , scheduleTime    = TimeOfDay 10 0 0
  , modelChain      = Gemini.Gemini31FlashLite :| [Gemini.Gemini3Flash]
  , contextQueries  = defaultContextQueries identifier
  , searchGrounding = False
  }
