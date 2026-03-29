module Automation.AiBlogLinksTest (tests) where

import qualified Data.Text as T
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import Test.Tasty.QuickCheck (testProperty)
import qualified Test.Tasty.QuickCheck as QC

import Automation.AiBlogLinks

tests :: TestTree
tests = testGroup "AiBlogLinks"
  [ constantTests
  , buildAiBlogBackLinkTests
  , buildAiBlogForwardLinkTests
  , buildNavLineTests
  , updateNavLinksTests
  , navLinksMatchTests
  , extractPostDateTests
  , propertyTests
  ]

--------------------------------------------------------------------------------
-- constants
--------------------------------------------------------------------------------

constantTests :: TestTree
constantTests = testGroup "constants"
  [ testCase "aiBlogNavPrefix starts with Home link" $
      assertBool "starts with [[index|" (T.isPrefixOf "[[index|" aiBlogNavPrefix)
  , testCase "aiBlogNavPrefix contains AI Blog link" $
      assertBool "contains AI Blog" (T.isInfixOf "AI Blog" aiBlogNavPrefix)
  ]

--------------------------------------------------------------------------------
-- buildAiBlogBackLink
--------------------------------------------------------------------------------

buildAiBlogBackLinkTests :: TestTree
buildAiBlogBackLinkTests = testGroup "buildAiBlogBackLink"
  [ testCase "builds back link with .md extension stripped" $
      buildAiBlogBackLink "2026-03-28-1-my-post.md" @?= "[[ai-blog/2026-03-28-1-my-post|⏮️]]"
  , testCase "handles filename without .md" $
      buildAiBlogBackLink "2026-03-28-1-my-post" @?= "[[ai-blog/2026-03-28-1-my-post|⏮️]]"
  , testCase "handles empty filename" $
      buildAiBlogBackLink "" @?= "[[ai-blog/|⏮️]]"
  ]

--------------------------------------------------------------------------------
-- buildAiBlogForwardLink
--------------------------------------------------------------------------------

buildAiBlogForwardLinkTests :: TestTree
buildAiBlogForwardLinkTests = testGroup "buildAiBlogForwardLink"
  [ testCase "builds forward link with .md stripped" $
      buildAiBlogForwardLink "2026-04-01-1-next-post.md" @?= "[[ai-blog/2026-04-01-1-next-post|⏭️]]"
  , testCase "handles filename without .md" $
      buildAiBlogForwardLink "2026-04-01-1-next-post" @?= "[[ai-blog/2026-04-01-1-next-post|⏭️]]"
  ]

--------------------------------------------------------------------------------
-- buildNavLine
--------------------------------------------------------------------------------

buildNavLineTests :: TestTree
buildNavLineTests = testGroup "buildNavLine"
  [ testCase "no previous, no next" $
      buildNavLine Nothing Nothing @?= aiBlogNavPrefix
  , testCase "previous only" $
      let result = buildNavLine (Just "prev.md") Nothing
      in do
        assertBool "starts with prefix" (T.isPrefixOf aiBlogNavPrefix result)
        assertBool "contains back link" (T.isInfixOf "⏮️" result)
        assertBool "no forward link" (not (T.isInfixOf "⏭️" result))
  , testCase "next only" $
      let result = buildNavLine Nothing (Just "next.md")
      in do
        assertBool "starts with prefix" (T.isPrefixOf aiBlogNavPrefix result)
        assertBool "contains forward link" (T.isInfixOf "⏭️" result)
        assertBool "no back link" (not (T.isInfixOf "⏮️" result))
  , testCase "both previous and next" $
      let result = buildNavLine (Just "prev.md") (Just "next.md")
      in do
        assertBool "starts with prefix" (T.isPrefixOf aiBlogNavPrefix result)
        assertBool "contains back link" (T.isInfixOf "⏮️" result)
        assertBool "contains forward link" (T.isInfixOf "⏭️" result)
        assertBool "has separator" (T.isInfixOf " | " result)
  , testCase "both links have correct structure" $
      let result = buildNavLine (Just "2026-01-01-1-a.md") (Just "2026-01-03-1-c.md")
      in do
        assertBool "back link path" (T.isInfixOf "[[ai-blog/2026-01-01-1-a|⏮️]]" result)
        assertBool "forward link path" (T.isInfixOf "[[ai-blog/2026-01-03-1-c|⏭️]]" result)
  ]

--------------------------------------------------------------------------------
-- updateNavLinks
--------------------------------------------------------------------------------

updateNavLinksTests :: TestTree
updateNavLinksTests = testGroup "updateNavLinks"
  [ testCase "updates existing nav line" $
      let content = aiBlogNavPrefix <> "\n# My Post\n\nBody"
          result = updateNavLinks content (Just "prev.md") Nothing
      in do
        assertBool "contains updated nav" (T.isInfixOf "⏮️" result)
        assertBool "contains body" (T.isInfixOf "Body" result)
  , testCase "returns content unchanged when no nav prefix found" $
      let content = "# No Nav Here\n\nBody"
          result = updateNavLinks content (Just "prev.md") Nothing
      in result @?= content
  , testCase "returns content unchanged when nav already matches" $
      let navLine = buildNavLine (Just "prev.md") (Just "next.md")
          content = navLine <> "\n# Post\n\nBody"
          result = updateNavLinks content (Just "prev.md") (Just "next.md")
      in result @?= content
  , testCase "replaces old nav line with new one" $
      let oldNav = buildNavLine (Just "old-prev.md") Nothing
          content = oldNav <> "\n# Post\n\nBody"
          result = updateNavLinks content (Just "new-prev.md") (Just "new-next.md")
      in do
        assertBool "has new back link" (T.isInfixOf "new-prev" result)
        assertBool "has new forward link" (T.isInfixOf "new-next" result)
        assertBool "old link removed" (not (T.isInfixOf "old-prev" result))
  , testCase "preserves content before and after nav line" $
      let content = "---\ntitle: Test\n---\n" <> aiBlogNavPrefix <> "\n# My Post\n\nBody text here"
          result = updateNavLinks content (Just "p.md") Nothing
      in do
        assertBool "preserves frontmatter" (T.isInfixOf "title: Test" result)
        assertBool "preserves body" (T.isInfixOf "Body text here" result)
  ]

--------------------------------------------------------------------------------
-- navLinksMatch
--------------------------------------------------------------------------------

navLinksMatchTests :: TestTree
navLinksMatchTests = testGroup "navLinksMatch"
  [ testCase "matches when nav line is correct" $
      let navLine = buildNavLine (Just "prev.md") (Just "next.md")
          content = "before\n" <> navLine <> "\nafter"
      in navLinksMatch content (Just "prev.md") (Just "next.md") @?= True
  , testCase "does not match when nav line differs" $
      let navLine = buildNavLine (Just "old.md") Nothing
          content = "before\n" <> navLine <> "\nafter"
      in navLinksMatch content (Just "new.md") Nothing @?= False
  , testCase "matches with no links" $
      let content = "before\n" <> aiBlogNavPrefix <> "\nafter"
      in navLinksMatch content Nothing Nothing @?= True
  , testCase "does not match when no nav line present" $
      navLinksMatch "no nav here" Nothing Nothing @?= False
  ]

--------------------------------------------------------------------------------
-- extractPostDate
--------------------------------------------------------------------------------

extractPostDateTests :: TestTree
extractPostDateTests = testGroup "extractPostDate"
  [ testCase "extracts date from standard filename" $
      extractPostDate "2026-03-28-1-my-post.md" @?= Just "2026-03-28"
  , testCase "extracts date from date-only filename" $
      extractPostDate "2026-03-28.md" @?= Just "2026-03-28"
  , testCase "returns Nothing for short filename" $
      extractPostDate "short.md" @?= Nothing
  , testCase "returns Nothing for invalid format" $
      extractPostDate "abcdefghij.md" @?= Nothing
  , testCase "returns Nothing for empty filename" $
      extractPostDate "" @?= Nothing
  , testCase "returns Nothing when dashes in wrong place" $
      extractPostDate "20260328ab.md" @?= Nothing
  ]

--------------------------------------------------------------------------------
-- property tests
--------------------------------------------------------------------------------

propertyTests :: TestTree
propertyTests = testGroup "properties"
  [ testProperty "buildNavLine always starts with aiBlogNavPrefix" $
      \(QC.ASCIIString prev) (QC.ASCIIString next) ->
        let prevM = case null prev of
              True  -> Nothing
              False -> Just (T.pack prev <> ".md")
            nextM = case null next of
              True  -> Nothing
              False -> Just (T.pack next <> ".md")
        in T.isPrefixOf aiBlogNavPrefix (buildNavLine prevM nextM)
  , testProperty "navLinksMatch agrees with buildNavLine" $
      \(QC.ASCIIString prev) (QC.ASCIIString next) ->
        let prevM = case null prev of
              True  -> Nothing
              False -> Just (T.pack prev <> ".md")
            nextM = case null next of
              True  -> Nothing
              False -> Just (T.pack next <> ".md")
            navLine = buildNavLine prevM nextM
            content = "header\n" <> navLine <> "\nbody"
        in navLinksMatch content prevM nextM
  , testProperty "updateNavLinks is idempotent" $
      \(QC.ASCIIString prev) ->
        let prevM = case null prev of
              True  -> Nothing
              False -> Just (T.pack prev <> ".md")
            content = aiBlogNavPrefix <> "\n# Post\n\nBody"
            once = updateNavLinks content prevM Nothing
            twice = updateNavLinks once prevM Nothing
        in once == twice
  ]
