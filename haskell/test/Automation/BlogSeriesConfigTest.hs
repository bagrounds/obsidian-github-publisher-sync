module Automation.BlogSeriesConfigTest (tests) where

import qualified Data.Map.Strict as Map
import Data.List.NonEmpty (NonEmpty ((:|)))
import Data.Text (Text)
import Data.Time.LocalTime (TimeOfDay (..))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)

import Automation.BlogSeriesConfig
import Automation.BlogSeriesDiscovery
import qualified Automation.Gemini as Gemini

testSeries :: [DiscoveredSeries]
testSeries =
  [ DiscoveredSeries
      { dsId = "chickie-loo", dsName = "Chickie Loo", dsIcon = "🐔"
      , dsPriorityUser = Just "ChickieLoo", dsScheduleTime = TimeOfDay 7 0 0
      , dsModels = Gemini.Gemini31FlashLite :| [Gemini.Gemini3Flash]
      , dsCrossSeries = False
      }
  , DiscoveredSeries
      { dsId = "auto-blog-zero", dsName = "Auto Blog Zero", dsIcon = "🤖"
      , dsPriorityUser = Just "bagrounds", dsScheduleTime = TimeOfDay 8 0 0
      , dsModels = Gemini.Gemini31FlashLite :| [Gemini.Gemini3Flash]
      , dsCrossSeries = False
      }
  , DiscoveredSeries
      { dsId = "systems-for-public-good", dsName = "Systems for Public Good", dsIcon = "🏛️"
      , dsPriorityUser = Just "bagrounds", dsScheduleTime = TimeOfDay 9 0 0
      , dsModels = Gemini.Gemini25Flash :| [Gemini.Gemini25FlashLite, Gemini.Gemini31FlashLite]
      , dsCrossSeries = False
      }
  ]

testSeriesConfigs :: [BlogSeriesConfig]
testSeriesConfigs = fmap deriveBlogSeriesConfig testSeries

testSeriesMap :: Map.Map Text BlogSeriesConfig
testSeriesMap = Map.fromList (fmap (\config -> (bscId config, config)) testSeriesConfigs)

tests :: TestTree
tests = testGroup "BlogSeriesConfig"
  [ testCase "lookupSeriesIn finds chickie-loo" $
      assertBool "should find chickie-loo" $
        case lookupSeriesIn testSeriesMap "chickie-loo" of
          Right s -> bscId s == "chickie-loo"
          Left _  -> False

  , testCase "lookupSeriesIn finds auto-blog-zero" $
      assertBool "should find auto-blog-zero" $
        case lookupSeriesIn testSeriesMap "auto-blog-zero" of
          Right s -> bscId s == "auto-blog-zero"
          Left _  -> False

  , testCase "lookupSeriesIn returns Left for unknown" $
      assertBool "should return Left for unknown" $
        case lookupSeriesIn testSeriesMap "unknown-series" of
          Left _  -> True
          Right _ -> False

  , testCase "derived series has 3 entries" $
      length testSeriesConfigs @?= 3

  , testCase "backfillContentIdsFrom includes ai-blog" $
      assertBool "should include ai-blog" $
        "ai-blog" `elem` backfillContentIdsFrom testSeriesConfigs

  , testCase "chickie-loo has correct icon" $
      case lookupSeriesIn testSeriesMap "chickie-loo" of
        Right s -> bscIcon s @?= "🐔"
        Left _  -> assertBool "should find series" False
  ]
