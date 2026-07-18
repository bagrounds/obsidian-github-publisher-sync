module Automation.Series (allSeries) where

import Automation.BlogSeriesDiscovery (AutoBlogSeries)
import qualified Automation.Series.AutoBlogZero as AutoBlogZero
import qualified Automation.Series.ChickieLoo as ChickieLoo
import qualified Automation.Series.Convergence as Convergence
import qualified Automation.Series.PositivityBias as PositivityBias
import qualified Automation.Series.RelationshipMiniseries as RelationshipMiniseries
import qualified Automation.Series.SystemsForPublicGood as SystemsForPublicGood
import qualified Automation.Series.TheNoise as TheNoise
import qualified Automation.Series.VitalSignals as VitalSignals

allSeries :: [AutoBlogSeries]
allSeries =
  [ AutoBlogZero.series
  , ChickieLoo.series
  , Convergence.series
  , PositivityBias.series
  , RelationshipMiniseries.series
  , SystemsForPublicGood.series
  , TheNoise.series
  , VitalSignals.series
  ]
