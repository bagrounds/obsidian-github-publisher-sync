{-# LANGUAGE OverloadedStrings #-}

module Automation.InternalLinking.GeminiTest (tests) where

import Automation.InternalLinking.Gemini (buildIdentificationPrompt)
import Automation.InternalLinking.CandidateDiscovery (ContentEntry (..))
import Automation.TestGenerators (testTitle, testRelativePath)
import qualified Data.Text as T
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase)

tests :: TestTree
tests = testGroup "InternalLinking.Gemini"
  [ buildIdentificationPromptTests
  ]

sampleEntry :: ContentEntry
sampleEntry = ContentEntry
  (testRelativePath "books/thinking-fast.md")
  (testTitle "🤔 Thinking, Fast and Slow")
  (testTitle "Thinking, Fast and Slow")

dddEntry :: ContentEntry
dddEntry = ContentEntry
  (testRelativePath "books/ddd.md")
  (testTitle "Domain-Driven Design: Tackling Complexity in the Heart of Software")
  (testTitle "Domain-Driven Design: Tackling Complexity in the Heart of Software")

buildIdentificationPromptTests :: TestTree
buildIdentificationPromptTests = testGroup "buildIdentificationPrompt"
  [ testCase "includes book titles" $
      let prompt = buildIdentificationPrompt "body" [sampleEntry]
      in assertBool "has title" (T.isInfixOf "Thinking, Fast and Slow" prompt)
  , testCase "includes document body" $
      let prompt = buildIdentificationPrompt "My document content" [sampleEntry]
      in assertBool "has body" (T.isInfixOf "My document content" prompt)
  , testCase "includes JSON instruction" $
      let prompt = buildIdentificationPrompt "body" [sampleEntry]
      in assertBool "has JSON instruction" (T.isInfixOf "JSON array" prompt)
  , testCase "includes relative paths" $
      let prompt = buildIdentificationPrompt "body" [sampleEntry]
      in assertBool "has path" (T.isInfixOf "books/thinking-fast.md" prompt)
  , testCase "handles multiple entries" $
      let entry2 = ContentEntry (testRelativePath "books/other.md") (testTitle "Other") (testTitle "Other")
          prompt = buildIdentificationPrompt "body" [sampleEntry, entry2]
      in do
        assertBool "has first" (T.isInfixOf "Thinking, Fast and Slow" prompt)
        assertBool "has second" (T.isInfixOf "Other" prompt)
  , testCase "handles empty entries" $
      let prompt = buildIdentificationPrompt "body" []
      in assertBool "still has system prompt" (T.isInfixOf "editorial assistant" prompt)
  , testCase "includes also-known-as for entries with subtitles" $
      let prompt = buildIdentificationPrompt "body" [dddEntry]
      in assertBool "has also known as" (T.isInfixOf "also known as \"Domain-Driven Design\"" prompt)
  , testCase "does not include also-known-as for entries without subtitles" $
      let prompt = buildIdentificationPrompt "body" [sampleEntry]
      in assertBool "no also known as" (not (T.isInfixOf "also known as" prompt))
  , testCase "includes also-known-as for single-word main title entries" $
      let antifragileEntry = ContentEntry
            (testRelativePath "books/antifragile.md")
            (testTitle "Antifragile: Things That Gain from Disorder")
            (testTitle "Antifragile: Things That Gain from Disorder")
          prompt = buildIdentificationPrompt "body" [antifragileEntry]
      in assertBool "has also known as" (T.isInfixOf "also known as \"Antifragile\"" prompt)
  , testCase "includes also-known-as for dash-separated subtitle entries" $
      let dashEntry = ContentEntry
            (testRelativePath "books/system-design.md")
            (testTitle "System Design Interview - An Insider's Guide")
            (testTitle "System Design Interview - An Insider's Guide")
          prompt = buildIdentificationPrompt "body" [dashEntry]
      in assertBool "has also known as" (T.isInfixOf "also known as \"System Design Interview\"" prompt)
  , testCase "includes system instructions about conservative matching" $
      let prompt = buildIdentificationPrompt "body" [sampleEntry]
      in assertBool "has conservative instruction" (T.isInfixOf "conservative" prompt)
  , testCase "includes empty array fallback instruction" $
      let prompt = buildIdentificationPrompt "body" []
      in assertBool "has empty array" (T.isInfixOf "[]" prompt)
  ]
