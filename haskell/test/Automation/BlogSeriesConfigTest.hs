module Automation.BlogSeriesConfigTest (tests) where

import qualified Data.Map.Strict as Map
import Data.List.NonEmpty (NonEmpty ((:|)))
import Data.Text (Text)
import Data.Time.LocalTime (TimeOfDay (..))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)

import Automation.BlogSeriesConfig (BlogSeriesConfig, lookupSeriesIn, backfillContentIdsFrom)
import qualified Automation.BlogSeriesConfig as BSC
import Automation.BlogSeriesDiscovery
import qualified Automation.Gemini as Gemini

testSeries :: [DiscoveredSeries]
testSeries =
  [ DiscoveredSeries
      { seriesId = "chickie-loo", seriesName = "Chickie Loo", seriesIcon = "🐔"
      , priorityUser = Just "ChickieLoo", scheduleTime = TimeOfDay 7 0 0
      , modelChain = Gemini.Gemini31FlashLite :| [Gemini.Gemini3Flash]
      , contextQueries = [], searchGrounding = False
      }
  , DiscoveredSeries
      { seriesId = "auto-blog-zero", seriesName = "Auto Blog Zero", seriesIcon = "🤖"
      , priorityUser = Just "bagrounds", scheduleTime = TimeOfDay 8 0 0
      , modelChain = Gemini.Gemini31FlashLite :| [Gemini.Gemini3Flash]
      , contextQueries = [], searchGrounding = False
      }
  , DiscoveredSeries
      { seriesId = "systems-for-public-good", seriesName = "Systems for Public Good", seriesIcon = "🏛️"
      , priorityUser = Just "bagrounds", scheduleTime = TimeOfDay 9 0 0
      , modelChain = Gemini.Gemini25Flash :| [Gemini.Gemini25FlashLite, Gemini.Gemini31FlashLite]
      , contextQueries = [], searchGrounding = False
      }
  ]

testSeriesConfigs :: [BlogSeriesConfig]
testSeriesConfigs = fmap deriveBlogSeriesConfig testSeries

testSeriesMap :: Map.Map Text BlogSeriesConfig
testSeriesMap = Map.fromList (fmap (\config -> (BSC.seriesId config, config)) testSeriesConfigs)

tests :: TestTree
tests = testGroup "BlogSeriesConfig"
  [ testCase "lookupSeriesIn finds chickie-loo" $
      assertBool "should find chickie-loo" $
        case lookupSeriesIn testSeriesMap "chickie-loo" of
          Right s -> BSC.seriesId s == "chickie-loo"
          Left _  -> False

  , testCase "lookupSeriesIn finds auto-blog-zero" $
      assertBool "should find auto-blog-zero" $
        case lookupSeriesIn testSeriesMap "auto-blog-zero" of
          Right s -> BSC.seriesId s == "auto-blog-zero"
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
        Right s -> BSC.icon s @?= "🐔"
        Left _  -> assertBool "should find series" False
  ]
