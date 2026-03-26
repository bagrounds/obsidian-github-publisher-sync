module Automation.RetryTest (tests) where

import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)

import Automation.Retry

tests :: TestTree
tests = testGroup "Retry"
  [ testCase "isTransientError detects 429" $
      isTransientError (HttpCodeException 429) @?= True

  , testCase "isTransientError detects 503" $
      isTransientError (HttpCodeException 503) @?= True

  , testCase "isTransientError rejects 400" $
      isTransientError (HttpCodeException 400) @?= False

  , testCase "isTransientError rejects 404" $
      isTransientError (HttpCodeException 404) @?= False

  , testCase "extractHttpCode gets code" $
      extractHttpCode (HttpCodeException 502) @?= Just 502

  , testCase "withRetry succeeds on first try" $ do
      result <- withRetry (pure "ok") defaultRetryOptions
      result @?= ("ok" :: String)

  , testCase "transientHttpCodes contains expected codes" $
      assertBool "should contain 429, 502, 503, 504" $
        all (`elem` transientHttpCodes) [429, 502, 503, 504]
  ]
