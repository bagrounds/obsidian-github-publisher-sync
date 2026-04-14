module Automation.WikilinkTest (tests) where

import qualified Data.Text as T
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))
import Test.Tasty.QuickCheck (testProperty)
import qualified Test.QuickCheck as QC

import Automation.Wikilink (formatWikilink)

tests :: TestTree
tests = testGroup "Wikilink"
  [ formatWikilinkTests
  , propertyTests
  ]

formatWikilinkTests :: TestTree
formatWikilinkTests = testGroup "formatWikilink"
  [ testCase "formats basic wikilink" $
      formatWikilink "books/test" "Test Book" @?= "[[books/test|Test Book]]"
  , testCase "formats wikilink with emoji alias" $
      formatWikilink "books/thinking-fast-and-slow" "🤔🐇🐢 Thinking, Fast and Slow"
        @?= "[[books/thinking-fast-and-slow|🤔🐇🐢 Thinking, Fast and Slow]]"
  , testCase "formats nav back link" $
      formatWikilink "reflections/2026-04-01" "⏮️" @?= "[[reflections/2026-04-01|⏮️]]"
  , testCase "formats nav forward link" $
      formatWikilink "reflections/2026-04-02" "⏭️" @?= "[[reflections/2026-04-02|⏭️]]"
  , testCase "formats series index link" $
      formatWikilink "auto-blog-zero/index" "🤖 Auto Blog Zero"
        @?= "[[auto-blog-zero/index|🤖 Auto Blog Zero]]"
  , testCase "formats blog post link with full display title" $
      formatWikilink "the-noise/2026-04-14-my-post" "2026-04-14 | 📰 My Post 📰"
        @?= "[[the-noise/2026-04-14-my-post|2026-04-14 | 📰 My Post 📰]]"
  ]

propertyTests :: TestTree
propertyTests = testGroup "properties"
  [ testProperty "formatWikilink starts with [[ and ends with ]]" $
      \(QC.ASCIIString target) (QC.ASCIIString alias) ->
        let result = formatWikilink (T.pack target) (T.pack alias)
        in T.isPrefixOf "[[" result && T.isSuffixOf "]]" result
  , testProperty "formatWikilink contains pipe separator" $
      \(QC.ASCIIString target) (QC.ASCIIString alias) ->
        T.isInfixOf "|" (formatWikilink (T.pack target) (T.pack alias))
  , testProperty "formatWikilink contains target and alias" $
      \(QC.ASCIIString target) (QC.ASCIIString alias) ->
        let result = formatWikilink (T.pack target) (T.pack alias)
        in T.isInfixOf (T.pack target) result && T.isInfixOf (T.pack alias) result
  ]
