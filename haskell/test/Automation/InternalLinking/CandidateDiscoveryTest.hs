{-# LANGUAGE OverloadedStrings #-}

module Automation.InternalLinking.CandidateDiscoveryTest (tests) where

import Automation.InternalLinking.CandidateDiscovery
  ( ContentEntry (..)
  , LinkCandidate (..)
  , linkableDirs
  , escapeRegex
  , formatContentEntryWikilink
  , extractContext
  , extractMainTitle
  , contentAlreadyLinksTo
  , findLinkCandidates
  )
import Automation.InternalLinking.Masking (maskProtectedRegions)
import Automation.Text (stripEmojis)
import Automation.TestGenerators (testTitle, testRelativePath)
import qualified Data.Text as T
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertEqual, assertBool, testCase)
import Test.Tasty.QuickCheck (testProperty)
import qualified Test.QuickCheck as QC

tests :: TestTree
tests = testGroup "InternalLinking.CandidateDiscovery"
  [ linkableDirsTests
  , stripEmojisTests
  , escapeRegexTests
  , formatContentEntryWikilinkTests
  , extractContextTests
  , extractMainTitleTests
  , contentAlreadyLinksToTests
  , findLinkCandidatesTests
  , propertyTests
  ]

linkableDirsTests :: TestTree
linkableDirsTests = testGroup "linkableDirs"
  [ testCase "contains books" $
      assertBool "books in linkableDirs" ("books" `elem` linkableDirs)
  , testCase "has expected count" $
      assertEqual "one entry" 1 (length linkableDirs)
  ]

stripEmojisTests :: TestTree
stripEmojisTests = testGroup "stripEmojis"
  [ testCase "strips emoji from title" $
      assertEqual "" "Thinking, Fast and Slow" (stripEmojis "🤔🐇🐢 Thinking, Fast and Slow")
  , testCase "returns plain text unchanged" $
      assertEqual "" "Hello World" (stripEmojis "Hello World")
  , testCase "handles empty string" $
      assertEqual "" "" (stripEmojis "")
  , testCase "strips leading and trailing emojis" $
      assertEqual "" "Hello" (stripEmojis "🎉 Hello 🎊")
  , testCase "collapses multiple spaces from emoji removal" $
      assertEqual "" "A B" (stripEmojis "A   B")
  ]

escapeRegexTests :: TestTree
escapeRegexTests = testGroup "escapeRegex"
  [ testCase "escapes dot" $
      assertEqual "" "hello\\.world" (escapeRegex "hello.world")
  , testCase "escapes multiple special chars" $
      assertBool "contains backslash" (T.isInfixOf "\\" (escapeRegex "foo+bar*baz"))
  , testCase "leaves plain text alone" $
      assertEqual "" "hello" (escapeRegex "hello")
  , testCase "escapes parentheses" $
      assertEqual "" "f\\(x\\)" (escapeRegex "f(x)")
  , testCase "escapes brackets" $
      assertEqual "" "a\\[b\\]" (escapeRegex "a[b]")
  ]

formatContentEntryWikilinkTests :: TestTree
formatContentEntryWikilinkTests = testGroup "formatContentEntryWikilink"
  [ testCase "formats basic wikilink" $
      let entry = ContentEntry (testRelativePath "books/test.md") (testTitle "Test Book") (testTitle "Test Book")
      in assertEqual "" "[[books/test|Test Book]]" (formatContentEntryWikilink entry)
  , testCase "strips .md from path" $
      let entry = ContentEntry (testRelativePath "books/foo.md") (testTitle "Foo") (testTitle "Foo")
      in assertBool "no .md in link" (not (T.isInfixOf ".md" (formatContentEntryWikilink entry)))
  , testCase "uses full title with emoji" $
      let entry = ContentEntry (testRelativePath "books/bar.md") (testTitle "📖 Bar Book") (testTitle "Bar Book")
      in assertBool "has emoji title" (T.isInfixOf "📖 Bar Book" (formatContentEntryWikilink entry))
  ]

extractContextTests :: TestTree
extractContextTests = testGroup "extractContext"
  [ testCase "extracts context around position" $
      let ctx = extractContext "Hello World" 6 5
      in assertBool "contains World" (T.isInfixOf "World" ctx)
  , testCase "handles start of text" $
      assertEqual "" "Hello" (extractContext "Hello" 0 5)
  , testCase "adds ellipsis for long text" $
      let content = T.replicate 300 "x"
          ctx = extractContext content 150 5
      in do
        assertBool "has leading ellipsis" (T.isPrefixOf "..." ctx)
        assertBool "has trailing ellipsis" (T.isSuffixOf "..." ctx)
  , testCase "no ellipsis for short text" $
      let ctx = extractContext "short" 0 5
      in do
        assertBool "no leading ellipsis" (not (T.isPrefixOf "..." ctx))
        assertBool "no trailing ellipsis" (not (T.isSuffixOf "..." ctx))
  ]

extractMainTitleTests :: TestTree
extractMainTitleTests = testGroup "extractMainTitle"
  [ testCase "extracts main title before colon-space" $
      assertEqual "" (Just "Domain-Driven Design")
        (extractMainTitle "Domain-Driven Design: Tackling Complexity in the Heart of Software")
  , testCase "returns Nothing when no subtitle separator" $
      assertEqual "" Nothing (extractMainTitle "Thinking, Fast and Slow")
  , testCase "returns Nothing when main title too short" $
      assertEqual "" Nothing (extractMainTitle "AI 2041: Ten Visions for Our Future")
  , testCase "extracts single-word main title" $
      assertEqual "" (Just "Abundance") (extractMainTitle "Abundance: The Inner Path to Wealth")
  , testCase "extracts single-word main title for distinctive books" $
      assertEqual "" (Just "Antifragile") (extractMainTitle "Antifragile: Things That Gain from Disorder")
  , testCase "extracts main title from dash-separated subtitle" $
      assertEqual "" (Just "System Design Interview")
        (extractMainTitle "System Design Interview - An Insider's Guide")
  , testCase "prefers colon separator over dash separator" $
      assertEqual "" (Just "Factfulness")
        (extractMainTitle "Factfulness: Ten Reasons We're Wrong About the World - and Why Things Are Better Than You Think")
  , testCase "returns Nothing for colon without space" $
      assertEqual "" Nothing (extractMainTitle "Title:NoSpace")
  ]

contentAlreadyLinksToTests :: TestTree
contentAlreadyLinksToTests = testGroup "contentAlreadyLinksTo"
  [ testCase "detects wikilink" $
      let entry = ContentEntry (testRelativePath "books/test.md") (testTitle "Test") (testTitle "Test")
      in assertBool "found link" (contentAlreadyLinksTo "see [[books/test|Test]] here" entry)
  , testCase "detects path with pipe" $
      let entry = ContentEntry (testRelativePath "books/test.md") (testTitle "Test") (testTitle "Test")
      in assertBool "found link" (contentAlreadyLinksTo "[[books/test|alias]]" entry)
  , testCase "detects path with hash" $
      let entry = ContentEntry (testRelativePath "books/test.md") (testTitle "Test") (testTitle "Test")
      in assertBool "found link" (contentAlreadyLinksTo "[[books/test#section]]" entry)
  , testCase "returns false when no link" $
      let entry = ContentEntry (testRelativePath "books/test.md") (testTitle "Test") (testTitle "Test")
      in assertBool "no link" (not (contentAlreadyLinksTo "no links here" entry))
  ]

sampleEntry :: ContentEntry
sampleEntry = ContentEntry
  (testRelativePath "books/thinking-fast.md")
  (testTitle "🤔 Thinking, Fast and Slow")
  (testTitle "Thinking, Fast and Slow")

findLinkCandidatesTests :: TestTree
findLinkCandidatesTests = testGroup "findLinkCandidates"
  [ testCase "finds title in content" $
      let content = "I recommend reading Thinking, Fast and Slow for insights"
          candidates = findLinkCandidates [sampleEntry] content content (testRelativePath "reflections/r.md")
      in assertEqual "one candidate" 1 (length candidates)
  , testCase "skips self-references" $
      let content = "I recommend Thinking, Fast and Slow for insights"
          candidates = findLinkCandidates [sampleEntry] content content (testRelativePath "books/thinking-fast.md")
      in assertEqual "no candidates for self" 0 (length candidates)
  , testCase "skips already-linked content" $
      let content = "see [[books/thinking-fast|TFS]] and Thinking, Fast and Slow"
          masked  = maskProtectedRegions content
          candidates = findLinkCandidates [sampleEntry] content masked (testRelativePath "reflections/r.md")
      in assertEqual "no candidates (already linked)" 0 (length candidates)
  , testCase "returns empty for no matches" $
      let content = "This has nothing to do with any book"
          candidates = findLinkCandidates [sampleEntry] content content (testRelativePath "reflections/r.md")
      in assertEqual "no candidates" 0 (length candidates)
  , testCase "matches subtitle when full title not present" $
      let dddEntry = ContentEntry
            (testRelativePath "books/ddd.md")
            (testTitle "Domain-Driven Design: Tackling Complexity")
            (testTitle "Domain-Driven Design: Tackling Complexity")
          content = "I love Domain-Driven Design as a practice"
          candidates = findLinkCandidates [dddEntry] content content (testRelativePath "reflections/r.md")
      in assertEqual "matched via main title" 1 (length candidates)
  , testCase "candidate has correct position" $
      let content = "prefix Thinking, Fast and Slow suffix"
          candidates = findLinkCandidates [sampleEntry] content content (testRelativePath "reflections/r.md")
      in case candidates of
        (c:_) -> assertEqual "position after prefix" 7 (position c)
        [] -> assertBool "should have candidates" False
  , testCase "candidate has matched text" $
      let content = "I read Thinking, Fast and Slow recently"
          candidates = findLinkCandidates [sampleEntry] content content (testRelativePath "reflections/r.md")
      in case candidates of
        (c:_) -> assertEqual "matched text" "Thinking, Fast and Slow" (matchedText c)
        [] -> assertBool "should have candidates" False
  , testCase "avoids duplicate entries for same path" $
      let entry1 = sampleEntry
          entry2 = ContentEntry (testRelativePath "books/thinking-fast.md") (testTitle "TFS Alt") (testTitle "Thinking, Fast and Slow")
          content = "I read Thinking, Fast and Slow twice"
          candidates = findLinkCandidates [entry1, entry2] content content (testRelativePath "reflections/r.md")
      in assertEqual "only one candidate per path" 1 (length candidates)
  , testCase "matches single-word main title" $
      let debugEntry = ContentEntry
            (testRelativePath "books/debugging.md")
            (testTitle "Debugging: The 9 Indispensable Rules")
            (testTitle "Debugging: The 9 Indispensable Rules")
          content = "Debugging by David J. Agans is a classic"
          candidates = findLinkCandidates [debugEntry] content content (testRelativePath "reflections/r.md")
      in do
          assertEqual "one candidate" 1 (length candidates)
          case candidates of
            (c:_) -> assertEqual "matched text" "Debugging" (matchedText c)
            [] -> assertBool "should have candidates" False
  , testCase "matches dash-separated subtitle" $
      let dashEntry = ContentEntry
            (testRelativePath "books/system-design.md")
            (testTitle "System Design Interview - An Insider's Guide")
            (testTitle "System Design Interview - An Insider's Guide")
          content = "I used System Design Interview to prepare"
          candidates = findLinkCandidates [dashEntry] content content (testRelativePath "reflections/r.md")
      in assertEqual "one candidate" 1 (length candidates)
  ]

propertyTests :: TestTree
propertyTests = testGroup "properties"
  [ testProperty "stripEmojis never increases length" $ \s ->
      let txt = T.pack (s :: String)
      in T.length (stripEmojis txt) <= T.length txt
  , testProperty "escapeRegex output is never shorter" $ \s ->
      let txt = T.pack (s :: String)
      in T.length (escapeRegex txt) >= T.length txt
  , testProperty "formatContentEntryWikilink contains entry title" $ \s ->
      let title = T.pack (s :: String)
      in not (T.null (T.strip title)) QC.==>
        let entry = ContentEntry (testRelativePath "books/test.md") (testTitle title) (testTitle title)
        in T.isInfixOf title (formatContentEntryWikilink entry)
  , testProperty "extractContext result length bounded by radius" $ \s ->
      let content = T.pack (s :: String)
      in not (T.null content) QC.==>
        T.length (extractContext content 0 1) <= T.length content + 6
  ]
