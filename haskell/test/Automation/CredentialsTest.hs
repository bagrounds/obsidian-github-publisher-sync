module Automation.CredentialsTest (tests) where

import qualified Data.Text as T
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)

import qualified Automation.Gemini as Gemini

tests :: TestTree
tests = testGroup "Gemini"
  [ geminiModelTests
  ]

geminiModelTests :: TestTree
geminiModelTests = testGroup "Gemini model constants"
  [ testCase "Gemini.defaultModel is non-empty" $
      assertBool "Gemini.defaultModel should be non-empty" (not (T.null Gemini.defaultModel))

  , testCase "Gemini.defaultQuestionModel is non-empty" $
      assertBool "Gemini.defaultQuestionModel should be non-empty" (not (T.null Gemini.defaultQuestionModel))

  , testCase "Gemini.gemini3Flash is non-empty" $
      assertBool "Gemini.gemini3Flash should be non-empty" (not (T.null Gemini.gemini3Flash))

  , testCase "Gemini.flashFallback is non-empty" $
      assertBool "Gemini.flashFallback should be non-empty" (not (T.null Gemini.flashFallback))

  , testCase "Gemini.modelFallback returns Just for question model" $
      Gemini.modelFallback Gemini.defaultQuestionModel @?= Just Gemini.flashFallback

  , testCase "Gemini.modelFallback returns Nothing for unknown model" $
      Gemini.modelFallback "unknown-model" @?= Nothing

  , testCase "all model names are distinct" $
      let models = [Gemini.defaultModel, Gemini.defaultQuestionModel, Gemini.gemini3Flash, Gemini.flashFallback]
      in assertBool "all models should be unique" (length models == length (nub models))
  ]
  where
    nub = foldl (\acc x -> if x `elem` acc then acc else acc <> [x]) []
