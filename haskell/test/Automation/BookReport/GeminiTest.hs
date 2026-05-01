module Automation.BookReport.GeminiTest (tests) where

import Automation.BookReport.Gemini
  ( buildFindMentionsPrompt
  , buildReportPrompt
  , buildAmazonSearchPrompt
  , parseMentionsList
  )
import qualified Data.Text as T
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertEqual, assertBool, testCase)

tests :: TestTree
tests = testGroup "BookReport.Gemini"
  [ buildFindMentionsPromptTests
  , parseMentionsListTests
  , buildReportPromptTests
  , buildAmazonSearchPromptTests
  ]

buildFindMentionsPromptTests :: TestTree
buildFindMentionsPromptTests = testGroup "buildFindMentionsPrompt"
  [ testCase "includes the document body in the prompt" $ do
      let body = "I recently read The Great Gatsby and loved it."
          prompt = buildFindMentionsPrompt body
      assertBool "body in prompt" (T.isInfixOf body prompt)

  , testCase "instructs Gemini to return a JSON array" $
      assertBool "JSON array instruction" $
        T.isInfixOf "JSON array" (buildFindMentionsPrompt "some text")

  , testCase "instructs to exclude wikilinked titles" $
      assertBool "wikilink exclusion instruction" $
        T.isInfixOf "[[" (buildFindMentionsPrompt "text")

  , testCase "instructs to return empty array when none found" $
      assertBool "empty array fallback" $
        T.isInfixOf "[]" (buildFindMentionsPrompt "text")

  , testCase "returns non-empty prompt for non-empty body" $
      assertBool "non-empty prompt" $
        not (T.null (buildFindMentionsPrompt "test body"))
  ]

parseMentionsListTests :: TestTree
parseMentionsListTests = testGroup "parseMentionsList"
  [ testCase "parses a simple JSON array of book titles" $
      assertEqual ""
        ["The Hitchhiker's Guide to the Galaxy", "Thinking, Fast and Slow"]
        (parseMentionsList "[\"The Hitchhiker's Guide to the Galaxy\", \"Thinking, Fast and Slow\"]")

  , testCase "returns empty list for empty JSON array" $
      assertEqual "" [] (parseMentionsList "[]")

  , testCase "returns empty list for invalid JSON" $
      assertEqual "" [] (parseMentionsList "not json")

  , testCase "handles trailing whitespace in response" $
      assertEqual ""
        ["Dune"]
        (parseMentionsList "  [\"Dune\"]  ")

  , testCase "handles code fence wrapping" $
      assertEqual ""
        ["1984"]
        (parseMentionsList "```json\n[\"1984\"]\n```")

  , testCase "handles plain code fence" $
      assertEqual ""
        ["Sapiens"]
        (parseMentionsList "```\n[\"Sapiens\"]\n```")

  , testCase "handles single title" $
      assertEqual ""
        ["Brave New World"]
        (parseMentionsList "[\"Brave New World\"]")

  , testCase "handles text before JSON array" $
      assertEqual ""
        ["The Road"]
        (parseMentionsList "Here are the books: [\"The Road\"]")

  , testCase "preserves title as found in text" $ do
      let titles = parseMentionsList "[\"The Master and Margarita\"]"
      assertEqual "" ["The Master and Margarita"] titles
  ]

buildReportPromptTests :: TestTree
buildReportPromptTests = testGroup "buildReportPrompt"
  [ testCase "includes the book title" $ do
      let prompt = buildReportPrompt "Dune"
      assertBool "title in prompt" (T.isInfixOf "Dune" prompt)

  , testCase "instructs to begin each line with a relevant emoji" $
      assertBool "emoji instruction" $
        T.isInfixOf "emoji" (buildReportPrompt "Test Book")

  , testCase "requests book recommendations" $
      assertBool "recommendations instruction" $
        T.isInfixOf "Recommendations" (buildReportPrompt "Test Book")

  , testCase "includes AI Summary section header" $
      assertBool "AI Summary section" $
        T.isInfixOf "AI Summary" (buildReportPrompt "Test Book")

  , testCase "instructs not to quote or italicize titles" $
      assertBool "no quote/italicize instruction" $
        T.isInfixOf "italicize" (buildReportPrompt "Test Book")

  , testCase "includes Evaluation section" $
      assertBool "Evaluation section" $
        T.isInfixOf "Evaluation" (buildReportPrompt "Test Book")

  , testCase "includes FAQ section" $
      assertBool "FAQ section" $
        T.isInfixOf "FAQ" (buildReportPrompt "Test Book")

  , testCase "includes What Do You Think section" $
      assertBool "What Do You Think section" $
        T.isInfixOf "What Do You Think" (buildReportPrompt "Test Book")

  , testCase "requests emojified title on first line" $
      assertBool "emojified title instruction" $
        T.isInfixOf "emojified" (buildReportPrompt "Test Book")
  ]

buildAmazonSearchPromptTests :: TestTree
buildAmazonSearchPromptTests = testGroup "buildAmazonSearchPrompt"
  [ testCase "includes the book title in quotes" $ do
      let prompt = buildAmazonSearchPrompt "Ender's Game"
      assertBool "title in prompt" (T.isInfixOf "Ender's Game" prompt)

  , testCase "instructs to return Amazon.com URL" $
      assertBool "amazon.com instruction" $
        T.isInfixOf "https://www.amazon.com/" (buildAmazonSearchPrompt "Test")

  , testCase "instructs to include ASIN via /dp/ path" $
      assertBool "/dp/ instruction" $
        T.isInfixOf "/dp/" (buildAmazonSearchPrompt "Test")

  , testCase "instructs to return NOT_FOUND when not available" $
      assertBool "NOT_FOUND fallback" $
        T.isInfixOf "NOT_FOUND" (buildAmazonSearchPrompt "Test")
  ]
