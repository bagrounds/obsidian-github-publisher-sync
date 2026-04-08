module Automation.TestGenerators (genUTCTime) where

import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import qualified Test.QuickCheck as QC

genUTCTime :: QC.Gen UTCTime
genUTCTime = do
  year <- QC.choose (2000, 2030)
  month <- QC.choose (1, 12)
  day <- QC.choose (1, 28)
  secs <- QC.choose (0, 86399)
  pure $ UTCTime (fromGregorian year month day) (secondsToDiffTime secs)
