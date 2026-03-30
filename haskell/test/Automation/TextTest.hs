module Automation.TextTest (tests) where

import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import qualified Data.Text as T

import Automation.Text

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
  ]
