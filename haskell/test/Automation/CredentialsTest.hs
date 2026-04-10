module Automation.CredentialsTest (tests) where

import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)

import qualified Automation.Gemini as Gemini

tests :: TestTree
tests = testGroup "Gemini"
  [ geminiModelTests
  ]

geminiModelTests :: TestTree
geminiModelTests = testGroup "Gemini model constants"
  [ testCase "Gemini.defaultModel is Gemma3" $
      Gemini.defaultModel @?= Gemini.Gemma3

  , testCase "Gemini.defaultQuestionModel is Gemini31FlashLite" $
      Gemini.defaultQuestionModel @?= Gemini.Gemini31FlashLite

  , testCase "Gemini.gemini3Flash is Gemini3Flash" $
      Gemini.gemini3Flash @?= Gemini.Gemini3Flash

  , testCase "Gemini.flashFallback is Gemini25Flash" $
      Gemini.flashFallback @?= Gemini.Gemini25Flash

  , testCase "Gemini.modelFallback returns Just for Gemini31FlashLite" $
      Gemini.modelFallback Gemini.Gemini31FlashLite @?= Just Gemini.Gemini25Flash

  , testCase "Gemini.modelFallback returns Nothing for Custom model" $
      Gemini.modelFallback (Gemini.Custom "unknown-model") @?= Nothing

  , testCase "all known models are distinct" $
      let models = Gemini.knownModels
      in assertBool "all models should be unique" (length models == length (nub models))
  ]
  where
    nub = foldl (\acc x -> if x `elem` acc then acc else acc <> [x]) []
