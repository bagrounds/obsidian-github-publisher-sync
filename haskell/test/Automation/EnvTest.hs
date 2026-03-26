module Automation.EnvTest (tests) where

import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))

import Automation.Env

tests :: TestTree
tests = testGroup "Env"
  [ testCase "isPlatformDisabledValue returns False for Nothing" $
      isPlatformDisabledValue Nothing @?= False

  , testCase "isPlatformDisabledValue returns True for 'true'" $
      isPlatformDisabledValue (Just "true") @?= True

  , testCase "isPlatformDisabledValue returns True for '1'" $
      isPlatformDisabledValue (Just "1") @?= True

  , testCase "isPlatformDisabledValue returns True for 'YES'" $
      isPlatformDisabledValue (Just "YES") @?= True

  , testCase "isPlatformDisabledValue returns False for 'no'" $
      isPlatformDisabledValue (Just "no") @?= False

  , testCase "isPlatformDisabledValue returns True for '  True  '" $
      isPlatformDisabledValue (Just "  True  ") @?= True
  ]
