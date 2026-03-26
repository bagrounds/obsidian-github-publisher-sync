module Automation.BlogSeriesConfigTest (tests) where

import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)

import Automation.BlogSeriesConfig

tests :: TestTree
tests = testGroup "BlogSeriesConfig"
  [ testCase "lookupSeries finds chickie-loo" $
      assertBool "should find chickie-loo" $
        case lookupSeries "chickie-loo" of
          Just s  -> bscId s == "chickie-loo"
          Nothing -> False

  , testCase "lookupSeries finds auto-blog-zero" $
      assertBool "should find auto-blog-zero" $
        case lookupSeries "auto-blog-zero" of
          Just s  -> bscId s == "auto-blog-zero"
          Nothing -> False

  , testCase "lookupSeries returns Nothing for unknown" $
      lookupSeries "unknown-series" @?= Nothing

  , testCase "blogSeries has 3 entries" $
      length blogSeries @?= 3

  , testCase "backfillContentIds includes ai-blog" $
      assertBool "should include ai-blog" $
        "ai-blog" `elem` backfillContentIds

  , testCase "chickie-loo has correct icon" $
      case lookupSeries "chickie-loo" of
        Just s  -> bscIcon s @?= "🐣"
        Nothing -> assertBool "should find series" False
  ]
