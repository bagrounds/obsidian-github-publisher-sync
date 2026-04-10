module Automation.BlogSeriesTest (tests) where

import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import qualified Data.Text as T
import Data.Time (fromGregorian)

import Automation.BlogSeries

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
  , buildBlogContextTests
  ]

-- --------------------------------------------------------------------------
-- buildBlogContext
-- --------------------------------------------------------------------------

buildBlogContextTests :: TestTree
buildBlogContextTests = testGroup "buildBlogContext"
  [ testCase "returns Left for nonexistent series ID" $ do
      let today = fromGregorian 2026 6 1
      result <- buildBlogContext "nonexistent-series-id" "." [] today
      case result of
        Left reason -> assertBool "error mentions unknown series" $
          T.isInfixOf "Unknown blog series" reason
        Right _ -> assertBool "should return Left for invalid series ID" False

  , testCase "returns Left for empty series ID" $ do
      let today = fromGregorian 2026 6 1
      result <- buildBlogContext "" "." [] today
      case result of
        Left reason -> assertBool "error mentions unknown series" $
          T.isInfixOf "Unknown blog series" reason
        Right _ -> assertBool "should return Left for empty series ID" False
  ]
