module Automation.Series (allSeries) where

import Data.List (sortOn)

import Automation.BlogSeriesDiscovery (DiscoveredSeries (..))
import qualified Automation.Series.AutoBlogZero as AutoBlogZero
import qualified Automation.Series.ChickieLoo as ChickieLoo
import qualified Automation.Series.Convergence as Convergence
import qualified Automation.Series.PositivityBias as PositivityBias
import qualified Automation.Series.SystemsForPublicGood as SystemsForPublicGood
import qualified Automation.Series.TheNoise as TheNoise

allSeries :: [DiscoveredSeries]
allSeries = sortOn seriesId
  [ AutoBlogZero.series
  , ChickieLoo.series
  , Convergence.series
  , PositivityBias.series
  , SystemsForPublicGood.series
  , TheNoise.series
  ]
