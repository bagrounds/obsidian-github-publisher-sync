module Automation.EnvTest (tests) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import Data.Time (UTCTime (..), addDays, fromGregorian, secondsToDiffTime)
import System.Environment (setEnv, unsetEnv)
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
  , buildEnvMapTests
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

buildEnvMapTests :: TestTree
buildEnvMapTests = testGroup "buildEnvMap"
  [ testCase "returns empty map for empty key list" $ do
      result <- buildEnvMap []
      result @?= (Map.empty :: Map Text Text)

  , testCase "returns empty string for unset variables" $ do
      unsetEnv "TEST_UNSET_VAR_12345"
      result <- buildEnvMap ["TEST_UNSET_VAR_12345"]
      Map.lookup "TEST_UNSET_VAR_12345" result @?= Just ""

  , testCase "returns value for set variables" $ do
      setEnv "TEST_BUILD_ENV_MAP_VAR" "hello"
      result <- buildEnvMap ["TEST_BUILD_ENV_MAP_VAR"]
      Map.lookup "TEST_BUILD_ENV_MAP_VAR" result @?= Just "hello"
      unsetEnv "TEST_BUILD_ENV_MAP_VAR"

  , testCase "handles mixed set and unset variables" $ do
      setEnv "TEST_SET_VAR" "value1"
      unsetEnv "TEST_UNSET_VAR"
      result <- buildEnvMap ["TEST_SET_VAR", "TEST_UNSET_VAR"]
      Map.lookup "TEST_SET_VAR" result @?= Just "value1"
      Map.lookup "TEST_UNSET_VAR" result @?= Just ""
      unsetEnv "TEST_SET_VAR"

  , testCase "map size equals number of keys" $ do
      result <- buildEnvMap ["A", "B", "C"]
      Map.size result @?= 3
  ]
