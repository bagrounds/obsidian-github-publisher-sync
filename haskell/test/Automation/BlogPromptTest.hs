module Automation.BlogPromptTest (tests) where

import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import qualified Data.Text as T

import Automation.BlogPrompt

tests :: TestTree
tests = testGroup "BlogPrompt"
  [ testCase "stripEmbedSections removes tweet section" $
      let body = "Content here\n\n## 🐦 Tweet\n\nSome embed"
      in stripEmbedSections body @?= "Content here"

  , testCase "stripEmbedSections preserves content without embeds" $
      let body = "Just normal content"
      in stripEmbedSections body @?= "Just normal content"

  , testCase "quoteForYaml wraps in double quotes" $
      assertBool "should be quoted" $
        T.head (quoteForYaml "hello") == '"'

  , testCase "quoteForYaml escapes internal quotes" $
      assertBool "should escape" $
        "\\\"" `T.isInfixOf` quoteForYaml "say \"hi\""

  , testCase "buildBackLink produces wiki link" $
      let result = buildBackLink "chickie-loo" "2026-03-25-test"
      in assertBool "should be wiki link with back emoji" $
           "⏮️" `T.isInfixOf` result && "[[" `T.isPrefixOf` result

  , testCase "buildForwardLink produces wiki link" $
      let result = buildForwardLink "chickie-loo" "2026-03-27-test.md"
      in assertBool "should be wiki link with forward emoji" $
           "⏭️" `T.isInfixOf` result && "[[" `T.isPrefixOf` result
  ]
