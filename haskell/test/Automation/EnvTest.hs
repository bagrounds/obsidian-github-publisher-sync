module Automation.EnvTest (tests) where

import Data.Text (Text)
import Data.Time (Day, UTCTime (..), addDays, fromGregorian, secondsToDiffTime)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))
import Test.Tasty.QuickCheck (testProperty)
import qualified Test.QuickCheck as QC

import Automation.Env
import Automation.TestGenerators (genUTCTime)

tests :: TestTree
tests = testGroup "Env"
  [ testCase "isPlatformDisabledValue returns False for Nothing" $
      isPlatformDisabledValue (Nothing :: Maybe Text) @?= False

  , testCase "isPlatformDisabledValue returns True for 'true'" $
      isPlatformDisabledValue (Just "true") @?= True

  , testCase "isPlatformDisabledValue returns True for '1'" $
      isPlatformDisabledValue (Just "1") @?= True

  , testCase "isPlatformDisabledValue returns True for 'YES'" $
      isPlatformDisabledValue (Just "YES") @?= True

  , testCase "isPlatformDisabledValue returns False for 'no'" $
      isPlatformDisabledValue (Just "no") @?= False

  , testCase "isPlatformDisabledValue returns True for '  True  '" $
      isPlatformDisabledValue (Just "  True  ") @?= True

  , yesterdayDateTests
  ]

yesterdayDateTests :: TestTree
yesterdayDateTests = testGroup "yesterdayDate"
  [ testProperty "result is always predecessor of UTC day" $
      QC.forAll genUTCTime $ \utc ->
        yesterdayDate utc == addDays (-1) (utctDay utc)

  , testCase "yesterday of Jan 1 is Dec 31" $
      yesterdayDate (UTCTime (fromGregorian 2026 1 1) 0)
        @?= fromGregorian 2025 12 31

  , testCase "yesterday of Mar 1 non-leap is Feb 28" $
      yesterdayDate (UTCTime (fromGregorian 2026 3 1) 0)
        @?= fromGregorian 2026 2 28

  , testCase "yesterday of Mar 1 leap year is Feb 29" $
      yesterdayDate (UTCTime (fromGregorian 2024 3 1) 0)
        @?= fromGregorian 2024 2 29

  , testCase "time-of-day does not affect result" $
      yesterdayDate (UTCTime (fromGregorian 2026 4 8) (secondsToDiffTime 86399))
        @?= fromGregorian 2026 4 7
  ]
