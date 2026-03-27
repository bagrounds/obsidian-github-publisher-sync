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
  ]
