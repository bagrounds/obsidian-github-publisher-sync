module Automation.PacificTimeTest (tests) where

import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime, LocalTime (..), TimeOfDay (..), diffDays, todHour)
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
  , toPacificLocalTimeTests
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

toPacificLocalTimeTests :: TestTree
toPacificLocalTimeTests = testGroup "toPacificLocalTime"
  [ testCase "PST: noon UTC on Jan 15 is 4:00 AM Pacific" $
      toPacificLocalTime (UTCTime (fromGregorian 2026 1 15) (secondsToDiffTime (12 * 3600)))
        @?= LocalTime (fromGregorian 2026 1 15) (TimeOfDay 4 0 0)

  , testCase "PDT: noon UTC on Jul 15 is 5:00 AM Pacific" $
      toPacificLocalTime (UTCTime (fromGregorian 2026 7 15) (secondsToDiffTime (12 * 3600)))
        @?= LocalTime (fromGregorian 2026 7 15) (TimeOfDay 5 0 0)

  , testCase "PST: midnight UTC on Jan 1 is 4:00 PM Dec 31 Pacific" $
      toPacificLocalTime (UTCTime (fromGregorian 2026 1 1) 0)
        @?= LocalTime (fromGregorian 2025 12 31) (TimeOfDay 16 0 0)

  , testCase "PDT: midnight UTC on Jul 1 is 5:00 PM Jun 30 Pacific" $
      toPacificLocalTime (UTCTime (fromGregorian 2026 7 1) 0)
        @?= LocalTime (fromGregorian 2026 6 30) (TimeOfDay 17 0 0)

  , testCase "PST: 2:00 PM UTC on Jan 15 is 6:00 AM Pacific" $
      toPacificLocalTime (UTCTime (fromGregorian 2026 1 15) (secondsToDiffTime (14 * 3600)))
        @?= LocalTime (fromGregorian 2026 1 15) (TimeOfDay 6 0 0)

  , testCase "PDT: 1:00 PM UTC on Jul 15 is 6:00 AM Pacific" $
      toPacificLocalTime (UTCTime (fromGregorian 2026 7 15) (secondsToDiffTime (13 * 3600)))
        @?= LocalTime (fromGregorian 2026 7 15) (TimeOfDay 6 0 0)

  , testProperty "result day is within 1 day of UTC day" $
      QC.forAll genUTCTime $ \utcTime ->
        let LocalTime pacDay _ = toPacificLocalTime utcTime
            utcDay = utctDay utcTime
        in abs (diffDays pacDay utcDay) <= 1

  , testProperty "PST offset is -8 hours" $
      QC.forAll (QC.choose (8, 23)) $ \hourUtc ->
        let utcTime = UTCTime (fromGregorian 2026 1 15) (secondsToDiffTime (fromIntegral hourUtc * 3600))
            LocalTime _ pacificTimeOfDay = toPacificLocalTime utcTime
        in todHour pacificTimeOfDay == hourUtc - 8

  , testProperty "PDT offset is -7 hours" $
      QC.forAll (QC.choose (7, 23)) $ \hourUtc ->
        let utcTime = UTCTime (fromGregorian 2026 7 15) (secondsToDiffTime (fromIntegral hourUtc * 3600))
            LocalTime _ pacificTimeOfDay = toPacificLocalTime utcTime
        in todHour pacificTimeOfDay == hourUtc - 7
  ]
