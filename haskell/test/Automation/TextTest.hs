module Automation.TextTest (tests) where

import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import qualified Data.Text as T

import Automation.Text
import Automation.Types (PlatformLimits (..), twitterLimits, twitterUrlLength, blueskyLimits, mastodonLimits)

tests :: TestTree
tests = testGroup "Text"
  [ testCase "countGraphemes counts correctly" $
      countGraphemes "hello" @?= 5

  , testCase "truncateToGraphemeLimit within limit" $
      truncateToGraphemeLimit "hi" 10 @?= "hi"

  , testCase "truncateToGraphemeLimit truncates" $
      assertBool "should be at most limit" $
        T.length (truncateToGraphemeLimit "hello world" 5) <= 5

  , testCase "calculateTweetLength plain text" $
      calculateTweetLength "hello" @?= 5

  , testCase "validateTweetLength short" $
      fst (validateTweetLength "hello") @?= True

  , testCase "fitPostToLimit within limit" $
      fitPostToLimit "hello" 100 @?= "hello"

  , testCase "calculateTweetLength counts URL as 23 chars" $
      calculateTweetLength "check https://example.com/very/long/path out" @?=
        T.length "check https://example.com/very/long/path out"
          + (23 - T.length "https://example.com/very/long/path")

  , testCase "calculateTweetLength counts short URL as 23 chars" $
      calculateTweetLength "see https://x.co done" @?=
        T.length "see https://x.co done" + (23 - T.length "https://x.co")

  , testCase "calculateTweetLength no URL returns text length" $
      calculateTweetLength "no urls here at all" @?= 19

  , testCase "truncateToGraphemeLimit adds ellipsis" $
      let result = truncateToGraphemeLimit "hello world" 6
      in assertBool "should end with ellipsis" $ T.isSuffixOf "…" result

  , testCase "truncateToGraphemeLimit exact boundary" $
      truncateToGraphemeLimit "hello" 5 @?= "hello"

  , testCase "fitPostToLimit truncates long text" $
      assertBool "should fit" $
        T.length (fitPostToLimit (T.replicate 500 "x") 100) <= 100

  , testCase "fitPostToLimit removes tags before truncating" $
      let post = "Title\n\ntopic1 | topic2 | topic3\nhttps://example.com"
          result = fitPostToLimit post 60
      in assertBool "should fit within limit" $
           countGraphemes result <= 60

  -- wordJaccardSimilarity tests
  , testCase "identical texts have similarity 1.0" $
      wordJaccardSimilarity "hello world" "hello world" @?= 1.0

  , testCase "completely different texts have similarity 0.0" $
      wordJaccardSimilarity "alpha beta" "gamma delta" @?= 0.0

  , testCase "empty texts have similarity 1.0" $
      wordJaccardSimilarity "" "" @?= 1.0

  , testCase "one empty text has similarity 0.0" $
      wordJaccardSimilarity "hello" "" @?= 0.0

  , testCase "half-overlapping word sets have similarity 0.33" $
      -- words A: {hello, world}  words B: {hello, there}
      -- intersection: {hello} = 1, union: {hello, world, there} = 3
      let sim = wordJaccardSimilarity "hello world" "hello there"
      in assertBool ("expected ~0.33, got " <> show sim) (abs (sim - 1/3) < 0.01)

  , testCase "similarity is case-insensitive" $
      wordJaccardSimilarity "Hello World" "hello world" @?= 1.0

  , testCase "modified blog post scores above 0.25" $
      -- Simulates a post that was edited (title changed, some content modified)
      let original = "---\ntitle: The Big Fix\n---\n# The Big Fix\n\nWe found and fixed a major bug in the deployment pipeline.\n\n## The Investigation\n\nThe logs showed errors starting at 3am."
          modified = "---\ntitle: 2026-04-01 | The Big Fix\naliases:\n  - The Big Fix\n---\n# 2026-04-01 | The Big Fix\n\nWe found and fixed a major bug in the deployment pipeline.\n\n## The Investigation\n\nThe logs showed errors starting at 3am.\n\n## 📚 Book Recommendations"
          sim = wordJaccardSimilarity original modified
      in assertBool ("modified post should score > 0.25, got " <> show sim) (sim > 0.25)

  , testCase "completely different blog post scores below 0.25" $
      let post1 = "---\ntitle: Fixing the Cache\n---\n# Fixing the Cache\n\nThe cache invalidation bug caused stale data to persist across deployments."
          post2 = "---\ntitle: Porting to Haskell\n---\n# Porting to Haskell\n\nWe migrated the automation pipeline from TypeScript to a strongly-typed functional language."
          sim = wordJaccardSimilarity post1 post2
      in assertBool ("different posts should score < 0.25, got " <> show sim) (sim < 0.25)

  -- calculatePostLength / validatePostLength tests
  , testCase "calculatePostLength with twitterLimits adjusts URLs" $
      calculatePostLength twitterLimits "check https://example.com/very/long/path out" @?=
        T.length "check https://example.com/very/long/path out"
          + (twitterUrlLength - T.length "https://example.com/very/long/path")

  , testCase "calculatePostLength with blueskyLimits does not adjust URLs" $
      calculatePostLength blueskyLimits "check https://example.com/very/long/path out" @?=
        T.length "check https://example.com/very/long/path out"

  , testCase "calculatePostLength with mastodonLimits does not adjust URLs" $
      calculatePostLength mastodonLimits "hello world" @?= 11

  , testCase "validatePostLength with blueskyLimits accepts short text" $
      fst (validatePostLength blueskyLimits "hello") @?= True

  , testCase "validatePostLength with blueskyLimits rejects text over 300" $
      fst (validatePostLength blueskyLimits (T.replicate 301 "x")) @?= False

  , testCase "validatePostLength with mastodonLimits accepts 500 chars" $
      fst (validatePostLength mastodonLimits (T.replicate 500 "x")) @?= True

  , testCase "calculatePostLength with no URL count returns text length" $
      calculatePostLength (PlatformLimits 100 Nothing) "hello" @?= 5

  , testCase "calculatePostLength with custom URL count adjusts" $
      let customUrlCount = 10
          customLimits = PlatformLimits 100 (Just customUrlCount)
      in calculatePostLength customLimits "see https://example.com" @?=
        T.length "see https://example.com" + (customUrlCount - T.length "https://example.com")
  ]
