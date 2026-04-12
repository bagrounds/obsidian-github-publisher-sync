module Automation.PacificTimeTest (tests) where

import Data.Time (Day, UTCTime (..), fromGregorian, secondsToDiffTime)
import qualified Data.Text as T
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import Test.Tasty.QuickCheck (testProperty)
import qualified Test.QuickCheck as QC

import Automation.PacificTime
import Automation.TestGenerators (genUTCTime)

tests :: TestTree
tests = testGroup "PacificTime"
  [ formatDayTests
  , formatDayHumanTests
  , pacificHourTests
  , pacificToUtcHourTests
  ]

formatDayTests :: TestTree
formatDayTests = testGroup "formatDay"
  [ testCase "formats Day as YYYY-MM-DD" $
      formatDay (fromGregorian 2026 3 28) @?= "2026-03-28"

  , testCase "zero-pads single-digit month and day" $
      formatDay (fromGregorian 2026 1 5) @?= "2026-01-05"
  ]

formatDayHumanTests :: TestTree
formatDayHumanTests = testGroup "formatDayHuman"
  [ testCase "Saturday April 11 2026" $
      formatDayHuman (fromGregorian 2026 4 11) @?= "Saturday, April 11, 2026"

  , testCase "Monday January 5 2026" $
      formatDayHuman (fromGregorian 2026 1 5) @?= "Monday, January 5, 2026"

  , testCase "Monday March 2 2026" $
      formatDayHuman (fromGregorian 2026 3 2) @?= "Monday, March 2, 2026"

  , testCase "Wednesday December 31 2025" $
      formatDayHuman (fromGregorian 2025 12 31) @?= "Wednesday, December 31, 2025"

  , testCase "Friday February 27 2026" $
      formatDayHuman (fromGregorian 2026 2 27) @?= "Friday, February 27, 2026"

  , testCase "includes day of week name" $
      assertBool "should include Saturday" $
        T.isInfixOf "Saturday" (formatDayHuman (fromGregorian 2026 4 11))
  ]

pacificHourTests :: TestTree
pacificHourTests = testGroup "pacificHour"
  [ testProperty "result is always 0-23" $
      QC.forAll genUTCTime $ \utc ->
        let hour = pacificHour utc
        in hour >= 0 && hour <= 23

  , testCase "PST: midnight UTC on Jan 1 is 4pm previous day" $
      pacificHour (UTCTime (fromGregorian 2026 1 1) 0) @?= 16

  , testCase "PST: noon UTC on Jan 15 is 4am Pacific" $
      pacificHour (UTCTime (fromGregorian 2026 1 15) (secondsToDiffTime (12 * 3600))) @?= 4

  , testCase "PDT: noon UTC on Jul 15 is 5am Pacific" $
      pacificHour (UTCTime (fromGregorian 2026 7 15) (secondsToDiffTime (12 * 3600))) @?= 5

  , testCase "PDT: midnight UTC on Jul 1 is 5pm previous day" $
      pacificHour (UTCTime (fromGregorian 2026 7 1) 0) @?= 17
  ]

pacificToUtcHourTests :: TestTree
pacificToUtcHourTests = testGroup "pacificToUtcHour"
  [ testProperty "result is always 0-23" $
      QC.forAll ((,) <$> QC.choose (0, 23) <*> genDay) $ \(hour, day) ->
        let result = pacificToUtcHour hour day
        in result >= 0 && result <= 23

  , testCase "PST: 6 AM Pacific on Jan 15 is 14 UTC" $
      pacificToUtcHour 6 (fromGregorian 2026 1 15) @?= 14

  , testCase "PDT: 6 AM Pacific on Jul 15 is 13 UTC" $
      pacificToUtcHour 6 (fromGregorian 2026 7 15) @?= 13

  , testCase "PST: 8 AM Pacific on Jan 15 is 16 UTC" $
      pacificToUtcHour 8 (fromGregorian 2026 1 15) @?= 16

  , testCase "PDT: 8 AM Pacific on Jul 15 is 15 UTC" $
      pacificToUtcHour 8 (fromGregorian 2026 7 15) @?= 15

  , testCase "PST: midnight Pacific on Jan 15 is 8 UTC" $
      pacificToUtcHour 0 (fromGregorian 2026 1 15) @?= 8

  , testCase "PDT: midnight Pacific on Jul 15 is 7 UTC" $
      pacificToUtcHour 0 (fromGregorian 2026 7 15) @?= 7

  , testProperty "PST dates add 8 hours" $
      QC.forAll (QC.choose (0, 15)) $ \hour ->
        pacificToUtcHour hour (fromGregorian 2026 1 15) == hour + 8

  , testProperty "PDT dates add 7 hours" $
      QC.forAll (QC.choose (0, 16)) $ \hour ->
        pacificToUtcHour hour (fromGregorian 2026 7 15) == hour + 7
  ]

genDay :: QC.Gen Day
genDay = do
  year <- QC.choose (2020, 2030)
  month <- QC.choose (1, 12)
  day <- QC.choose (1, 28)
  pure (fromGregorian year month day)
