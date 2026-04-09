module Automation.CredentialsTest (tests) where

import qualified Data.Text as T
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)

import Automation.Credentials
  ( defaultGeminiModel
  , defaultQuestionModel
  , gemini3Flash
  , geminiFlashFallback
  , geminiModelFallback
  )

tests :: TestTree
tests = testGroup "Credentials"
  [ geminiModelTests
  ]

geminiModelTests :: TestTree
geminiModelTests = testGroup "Gemini model constants"
  [ testCase "defaultGeminiModel is non-empty" $
      assertBool "defaultGeminiModel should be non-empty" (not (T.null defaultGeminiModel))

  , testCase "defaultQuestionModel is non-empty" $
      assertBool "defaultQuestionModel should be non-empty" (not (T.null defaultQuestionModel))

  , testCase "gemini3Flash is non-empty" $
      assertBool "gemini3Flash should be non-empty" (not (T.null gemini3Flash))

  , testCase "geminiFlashFallback is non-empty" $
      assertBool "geminiFlashFallback should be non-empty" (not (T.null geminiFlashFallback))

  , testCase "geminiModelFallback returns Just for question model" $
      geminiModelFallback defaultQuestionModel @?= Just geminiFlashFallback

  , testCase "geminiModelFallback returns Nothing for unknown model" $
      geminiModelFallback "unknown-model" @?= Nothing

  , testCase "all model names are distinct" $
      let models = [defaultGeminiModel, defaultQuestionModel, gemini3Flash, geminiFlashFallback]
      in assertBool "all models should be unique" (length models == length (nub models))
  ]
  where
    nub = foldl (\acc x -> if x `elem` acc then acc else acc <> [x]) []
