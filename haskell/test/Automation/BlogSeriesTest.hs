module Automation.BlogSeriesTest (tests) where

import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import qualified Data.Map.Strict as Map
import qualified Data.Text as T
import Data.Time (fromGregorian)
import Data.Time.LocalTime (TimeOfDay (..))

import Automation.BlogSeries
import Automation.BlogSeriesConfig (BlogSeriesConfig (..))

tests :: TestTree
tests = testGroup "BlogSeries"
  [ testCase "extractSlug strips date prefix" $
      extractSlug "2026-03-26-my-post.md" @?= "my-post"

  , testCase "extractSlug handles no date prefix" $
      extractSlug "my-post.md" @?= "my-post"

  , testCase "parseGeneratedPost extracts title and body" $
      let raw = "## My Great Title\n\nSome content here that is long enough to pass the minimum length check. " <>
                T.replicate 20 "More content to reach the 200 char minimum. "
          result = parseGeneratedPost raw
      in case result of
           Just (body, title) -> do
             assertBool "title should match" $ "My Great Title" `T.isInfixOf` title
             assertBool "body should be non-empty" $ not (T.null body)
           Nothing -> assertBool "should parse successfully" False

  , testCase "parseGeneratedPost rejects short content" $
      parseGeneratedPost "## Title\nShort" @?= Nothing

  , testCase "appendModelSignature adds attribution" $
      let result = appendModelSignature "Post body" "gemini-2.5-flash"
      in assertBool "should contain model name" $
           "gemini-2.5-flash" `T.isInfixOf` result
  , generateSeriesIndexTests
  , buildBlogContextTests
  ]

sampleSeries :: BlogSeriesConfig
sampleSeries = BlogSeriesConfig
  { bscId = "the-noise"
  , bscName = "The Noise"
  , bscIcon = "\128240"
  , bscAuthor = "[[the-noise]]"
  , bscBaseUrl = "https://bagrounds.org/the-noise"
  , bscPriorityUser = Just "bagrounds"
  , bscNavLink = "[[index|Home]] > [[the-noise/index|\128240 The Noise]]"
  , bscScheduleTime = TimeOfDay 6 0 0
  }

generateSeriesIndexTests :: TestTree
generateSeriesIndexTests = testGroup "generateSeriesIndex"
  [ testCase "includes share true" $
      assertBool "should contain share: true" $
        T.isInfixOf "share: true" (generateSeriesIndex sampleSeries)

  , testCase "includes aliases with display name" $
      assertBool "should contain aliases" $
        T.isInfixOf "aliases:" (generateSeriesIndex sampleSeries)

  , testCase "includes title with icon and name" $
      assertBool "should contain title" $
        T.isInfixOf "The Noise" (generateSeriesIndex sampleSeries)

  , testCase "includes URL" $
      assertBool "should contain URL" $
        T.isInfixOf "https://bagrounds.org/the-noise" (generateSeriesIndex sampleSeries)

  , testCase "includes backlinks false" $
      assertBool "should contain backlinks: false" $
        T.isInfixOf "backlinks: false" (generateSeriesIndex sampleSeries)

  , testCase "includes home breadcrumb" $
      assertBool "should contain home link" $
        T.isInfixOf "[[index|" (generateSeriesIndex sampleSeries)

  , testCase "includes dataview query" $
      assertBool "should contain dataview" $
        T.isInfixOf "```dataview" (generateSeriesIndex sampleSeries)

  , testCase "includes FROM clause with series ID" $
      assertBool "should contain FROM the-noise" $
        T.isInfixOf "FROM \"the-noise\"" (generateSeriesIndex sampleSeries)

  , testCase "includes inline page count" $
      assertBool "should contain dv.pages" $
        T.isInfixOf "dv.pages" (generateSeriesIndex sampleSeries)

  , testCase "uses LIST query format" $
      assertBool "should contain LIST WITHOUT ID" $
        T.isInfixOf "LIST WITHOUT ID" (generateSeriesIndex sampleSeries)

  , testCase "filters out this file" $
      assertBool "should filter this.file.name" $
        T.isInfixOf "this.file.name" (generateSeriesIndex sampleSeries)
  ]

buildBlogContextTests :: TestTree
buildBlogContextTests = testGroup "buildBlogContext"
  [ testCase "returns Left for nonexistent series ID" $ do
      let today = fromGregorian 2026 6 1
      result <- buildBlogContext Map.empty "nonexistent-series-id" "." [] today
      case result of
        Left reason -> assertBool "error mentions unknown series" $
          T.isInfixOf "Unknown blog series" reason
        Right _ -> assertBool "should return Left for invalid series ID" False

  , testCase "returns Left for empty series ID" $ do
      let today = fromGregorian 2026 6 1
      result <- buildBlogContext Map.empty "" "." [] today
      case result of
        Left reason -> assertBool "error mentions unknown series" $
          T.isInfixOf "Unknown blog series" reason
        Right _ -> assertBool "should return Left for empty series ID" False
  ]
