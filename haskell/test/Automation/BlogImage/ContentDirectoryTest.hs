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
      , testCase "AutoBlogZero maps to auto-blog-zero" $
          contentDirectoryToText AutoBlogZero @?= "auto-blog-zero"
      , testCase "ChickieLoo maps to chickie-loo" $
          contentDirectoryToText ChickieLoo @?= "chickie-loo"
      , testCase "SystemsForPublicGood maps to systems-for-public-good" $
          contentDirectoryToText SystemsForPublicGood @?= "systems-for-public-good"
      , testCase "Articles maps to articles" $
          contentDirectoryToText Articles @?= "articles"
      , testCase "BotChats maps to bot-chats" $
          contentDirectoryToText BotChats @?= "bot-chats"
      ]
  , testGroup "contentDirectoryFromText"
      [ testCase "parses reflections" $
          contentDirectoryFromText "reflections" @?= Just Reflections
      , testCase "parses ai-blog" $
          contentDirectoryFromText "ai-blog" @?= Just AiBlog
      , testCase "rejects unknown directory" $
          contentDirectoryFromText "unknown-dir" @?= Nothing
      , testCase "rejects empty string" $
          contentDirectoryFromText "" @?= Nothing
      , testCase "rejects capitalized variant" $
          contentDirectoryFromText "Reflections" @?= Nothing
      ]
  , testGroup "round-trip"
      [ testCase "all directories round-trip through toText and fromText" $
          assertBool "all round-trip" $
            all (\directory -> contentDirectoryFromText (contentDirectoryToText directory) == Just directory)
              [minBound .. maxBound]
      , testProperty "toText produces non-empty text" $
          \directory -> not (T.null (contentDirectoryToText (toEnum (directory `mod` 13) :: ContentDirectory)))
      ]
  , testGroup "Bounded and Enum"
      [ testCase "minBound is Reflections" $
          (minBound :: ContentDirectory) @?= Reflections
      , testCase "maxBound is Topics" $
          (maxBound :: ContentDirectory) @?= Topics
      , testCase "there are 13 content directories" $
          length [minBound .. maxBound :: ContentDirectory] @?= 13
      ]
  ]
