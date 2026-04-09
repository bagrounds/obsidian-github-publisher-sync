module Automation.TestGenerators
  ( genUTCTime
  , testUrl
  , testTitle
  , testRelativePath
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import qualified Test.QuickCheck as QC

import Automation.Types (Url, mkUrl, Title, mkTitle, RelativePath, mkRelativePath)

genUTCTime :: QC.Gen UTCTime
genUTCTime = do
  year <- QC.choose (2000, 2030)
  month <- QC.choose (1, 12)
  day <- QC.choose (1, 28)
  secs <- QC.choose (0, 86399)
  pure $ UTCTime (fromGregorian year month day) (secondsToDiffTime secs)

testUrl :: Text -> Url
testUrl = either (error . T.unpack) id . mkUrl

testTitle :: Text -> Title
testTitle = either (error . T.unpack) id . mkTitle

testRelativePath :: Text -> RelativePath
testRelativePath = either (error . T.unpack) id . mkRelativePath
