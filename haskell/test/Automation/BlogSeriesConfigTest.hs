module Automation.BlogSeriesConfigTest (tests) where

import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)

import Automation.BlogSeriesConfig

tests :: TestTree
tests = testGroup "BlogSeriesConfig"
  [ testCase "lookupSeries finds chickie-loo" $
      assertBool "should find chickie-loo" $
        case lookupSeries "chickie-loo" of
          Right s -> bscId s == "chickie-loo"
          Left _  -> False

  , testCase "lookupSeries finds auto-blog-zero" $
      assertBool "should find auto-blog-zero" $
        case lookupSeries "auto-blog-zero" of
          Right s -> bscId s == "auto-blog-zero"
          Left _  -> False

  , testCase "lookupSeries returns Left for unknown" $
      assertBool "should return Left for unknown" $
        case lookupSeries "unknown-series" of
          Left _  -> True
          Right _ -> False

  , testCase "blogSeries has 3 entries" $
      length blogSeries @?= 3

  , testCase "backfillContentIds includes ai-blog" $
      assertBool "should include ai-blog" $
        "ai-blog" `elem` backfillContentIds

  , testCase "chickie-loo has correct icon" $
      case lookupSeries "chickie-loo" of
        Right s -> bscIcon s @?= "🐔"
        Left _  -> assertBool "should find series" False
  ]
