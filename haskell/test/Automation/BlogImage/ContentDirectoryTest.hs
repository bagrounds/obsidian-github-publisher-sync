module Automation.BlogImage.ContentDirectoryTest (tests) where

import qualified Data.Text as T
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import Test.Tasty.QuickCheck (testProperty)

import Automation.BlogImage.ContentDirectory

tests :: TestTree
tests = testGroup "BlogImage.ContentDirectory"
  [ testGroup "contentDirectoryToText"
      [ testCase "Reflections maps to reflections" $
          contentDirectoryToText Reflections @?= "reflections"
      , testCase "AiBlog maps to ai-blog" $
          contentDirectoryToText AiBlog @?= "ai-blog"
      , testCase "Articles maps to articles" $
          contentDirectoryToText Articles @?= "articles"
      , testCase "BotChats maps to bot-chats" $
          contentDirectoryToText BotChats @?= "bot-chats"
      , testCase "AutoBlogSeries preserves name" $
          contentDirectoryToText (AutoBlogSeries "my-new-series") @?= "my-new-series"
      , testCase "auto-blog-zero routes through AutoBlogSeries" $
          contentDirectoryToText (AutoBlogSeries "auto-blog-zero") @?= "auto-blog-zero"
      , testCase "chickie-loo routes through AutoBlogSeries" $
          contentDirectoryToText (AutoBlogSeries "chickie-loo") @?= "chickie-loo"
      , testCase "systems-for-public-good routes through AutoBlogSeries" $
          contentDirectoryToText (AutoBlogSeries "systems-for-public-good") @?= "systems-for-public-good"
      ]
  , testGroup "contentDirectoryFromText"
      [ testCase "parses reflections" $
          contentDirectoryFromText "reflections" @?= Reflections
      , testCase "parses ai-blog" $
          contentDirectoryFromText "ai-blog" @?= AiBlog
      , testCase "auto-blog-zero becomes AutoBlogSeries" $
          contentDirectoryFromText "auto-blog-zero" @?= AutoBlogSeries "auto-blog-zero"
      , testCase "chickie-loo becomes AutoBlogSeries" $
          contentDirectoryFromText "chickie-loo" @?= AutoBlogSeries "chickie-loo"
      , testCase "systems-for-public-good becomes AutoBlogSeries" $
          contentDirectoryFromText "systems-for-public-good" @?= AutoBlogSeries "systems-for-public-good"
      , testCase "unknown directory becomes AutoBlogSeries" $
          contentDirectoryFromText "unknown-dir" @?= AutoBlogSeries "unknown-dir"
      , testCase "empty string becomes AutoBlogSeries" $
          contentDirectoryFromText "" @?= AutoBlogSeries ""
      , testCase "capitalized variant becomes AutoBlogSeries" $
          contentDirectoryFromText "Reflections" @?= AutoBlogSeries "Reflections"
      ]
  , testGroup "round-trip"
      [ testCase "all known directories round-trip through toText and fromText" $
          assertBool "all round-trip" $
            all (\directory -> contentDirectoryFromText (contentDirectoryToText directory) == directory)
              knownDirectories
      , testProperty "toText produces non-empty text for known directories" $
          \idx -> not (T.null (contentDirectoryToText (knownDirectories !! (idx `mod` length knownDirectories))))
      , testCase "AutoBlogSeries round-trips" $
          contentDirectoryFromText (contentDirectoryToText (AutoBlogSeries "my-series")) @?= AutoBlogSeries "my-series"
      ]
  , testGroup "knownDirectories"
      [ testCase "there are 10 known content directories" $
          length knownDirectories @?= 10
      , testCase "first is Reflections" $
          take 1 knownDirectories @?= [Reflections]
      , testCase "last is Topics" $
          drop (length knownDirectories - 1) knownDirectories @?= [Topics]
      ]
  ]
