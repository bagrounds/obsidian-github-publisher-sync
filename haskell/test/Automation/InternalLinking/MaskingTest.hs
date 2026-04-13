{-# LANGUAGE OverloadedStrings #-}

module Automation.InternalLinking.MaskingTest (tests) where

import Automation.InternalLinking.Masking (maskProtectedRegions)
import qualified Data.Text as T
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertEqual, testCase)
import Test.Tasty.QuickCheck (testProperty)

tests :: TestTree
tests = testGroup "InternalLinking.Masking"
  [ maskFrontmatterTests
  , maskFencedCodeTests
  , maskInlineCodeTests
  , maskMarkdownLinksTests
  , maskWikilinksTests
  , maskHeadingsTests
  , maskUrlsTests
  , maskBoldTests
  , compositionTests
  , propertyTests
  ]

maskFrontmatterTests :: TestTree
maskFrontmatterTests = testGroup "maskFrontmatter"
  [ testCase "masks frontmatter content" $
      let content = "---\ntitle: Secret\nauthor: Me\n---\nBody text"
          masked = maskProtectedRegions content
      in do
        assertBool "frontmatter masked" (not (T.isInfixOf "Secret" masked))
        assertBool "body preserved" (T.isInfixOf "Body text" masked)
  , testCase "preserves text without frontmatter" $
      let content = "Just some plain text"
          masked = maskProtectedRegions content
      in assertEqual "unchanged" content masked
  , testCase "handles unclosed frontmatter" $
      let content = "---\ntitle: Oops\nNo closing"
          masked = maskProtectedRegions content
      in assertEqual "preserves length" (T.length content) (T.length masked)
  ]

maskFencedCodeTests :: TestTree
maskFencedCodeTests = testGroup "maskFencedCode"
  [ testCase "masks backtick code blocks" $
      let content = "before\n```\ncode block\n```\nafter"
          masked = maskProtectedRegions content
      in do
        assertBool "code masked" (not (T.isInfixOf "code block" masked))
        assertBool "before preserved" (T.isInfixOf "before" masked)
        assertBool "after preserved" (T.isInfixOf "after" masked)
  , testCase "masks code blocks with language specifier" $
      let content = "before\n```haskell\nmap id xs\n```\nafter"
          masked = maskProtectedRegions content
      in assertBool "code masked" (not (T.isInfixOf "map id xs" masked))
  , testCase "masks tilde code blocks" $
      let content = "before\n~~~\ntilde code\n~~~\nafter"
          masked = maskProtectedRegions content
      in assertBool "code masked" (not (T.isInfixOf "tilde code" masked))
  , testCase "handles unclosed code blocks" $
      let content = "before\n```\nunclosed code"
          masked = maskProtectedRegions content
      in assertEqual "preserves length" (T.length content) (T.length masked)
  ]

maskInlineCodeTests :: TestTree
maskInlineCodeTests = testGroup "maskInlineCode"
  [ testCase "masks inline code" $
      let content = "use `someFunction` here"
          masked = maskProtectedRegions content
      in assertBool "code masked" (not (T.isInfixOf "someFunction" masked))
  , testCase "preserves surrounding text" $
      let content = "before `code` after"
          masked = maskProtectedRegions content
      in do
        assertBool "before preserved" (T.isPrefixOf "before" masked)
        assertBool "after preserved" (T.isSuffixOf "after" masked)
  , testCase "handles multiple inline code spans" $
      let content = "use `foo` and `bar` together"
          masked = maskProtectedRegions content
      in do
        assertBool "foo masked" (not (T.isInfixOf "`foo`" masked))
        assertBool "bar masked" (not (T.isInfixOf "`bar`" masked))
  ]

maskMarkdownLinksTests :: TestTree
maskMarkdownLinksTests = testGroup "maskMarkdownLinks"
  [ testCase "masks markdown link entirely" $
      let content = "see [My Title](path/to/file.md) here"
          masked = maskProtectedRegions content
      in assertBool "link masked" (not (T.isInfixOf "[My Title]" masked))
  , testCase "preserves length through markdown link masking" $
      let content = "text [link](url) more"
          masked = maskProtectedRegions content
      in assertEqual "preserves length" (T.length content) (T.length masked)
  , testCase "masks multiple markdown links" $
      let content = "[one](a.md) and [two](b.md)"
          masked = maskProtectedRegions content
      in do
        assertBool "first masked" (not (T.isInfixOf "[one]" masked))
        assertBool "second masked" (not (T.isInfixOf "[two]" masked))
  ]

maskWikilinksTests :: TestTree
maskWikilinksTests = testGroup "maskWikilinks"
  [ testCase "masks simple wikilink" $
      let content = "see [[some/page]] here"
          masked = maskProtectedRegions content
      in assertBool "wikilink masked" (not (T.isInfixOf "[[some/page]]" masked))
  , testCase "masks wikilink with alias" $
      let content = "see [[page|display text]] here"
          masked = maskProtectedRegions content
      in assertBool "wikilink masked" (not (T.isInfixOf "[[page|display text]]" masked))
  , testCase "masks wikilink with heading anchor" $
      let content = "see [[page#section]] here"
          masked = maskProtectedRegions content
      in assertBool "wikilink masked" (not (T.isInfixOf "[[page#section]]" masked))
  ]

maskHeadingsTests :: TestTree
maskHeadingsTests = testGroup "maskHeadings"
  [ testCase "masks H1 heading" $
      let content = "# My Heading\nBody"
          masked = maskProtectedRegions content
      in assertBool "heading masked" (not (T.isInfixOf "My Heading" masked))
  , testCase "masks H3 heading" $
      let content = "### Third Level\nBody"
          masked = maskProtectedRegions content
      in assertBool "heading masked" (not (T.isInfixOf "Third Level" masked))
  , testCase "does not mask hash without space" $
      let content = "#hashtag is not a heading"
          masked = maskProtectedRegions content
      in assertBool "not a heading" (T.isInfixOf "#hashtag" masked)
  , testCase "preserves non-heading lines" $
      let content = "# Heading\nNormal text\n## Second Heading\nMore text"
          masked = maskProtectedRegions content
      in do
        assertBool "normal preserved" (T.isInfixOf "Normal text" masked)
        assertBool "more preserved" (T.isInfixOf "More text" masked)
  ]

maskUrlsTests :: TestTree
maskUrlsTests = testGroup "maskUrls"
  [ testCase "masks https URL" $
      let content = "visit https://example.com/page today"
          masked = maskProtectedRegions content
      in assertBool "URL masked" (not (T.isInfixOf "https://example.com" masked))
  , testCase "masks http URL" $
      let content = "visit http://example.com today"
          masked = maskProtectedRegions content
      in assertBool "URL masked" (not (T.isInfixOf "http://example.com" masked))
  , testCase "preserves surrounding text" $
      let content = "before https://x.com after"
          masked = maskProtectedRegions content
      in do
        assertBool "before preserved" (T.isPrefixOf "before" masked)
        assertBool "after preserved" (T.isSuffixOf "after" masked)
  ]

maskBoldTests :: TestTree
maskBoldTests = testGroup "maskBold"
  [ testCase "removes bold markers" $
      let content = "some **bold** text"
          masked = maskProtectedRegions content
      in assertBool "no bold markers" (not (T.isInfixOf "**" masked))
  , testCase "preserves bold text content" $
      let content = "some **bold** text"
          masked = maskProtectedRegions content
      in assertBool "text preserved" (T.isInfixOf "bold" masked)
  ]

compositionTests :: TestTree
compositionTests = testGroup "composition"
  [ testCase "masks all protected region types simultaneously" $
      let content = "---\ntitle: Fm\n---\nSome text\n# Heading\n`code` and [[link]] and [md](url.md) and **bold** and https://url.com"
          masked = maskProtectedRegions content
      in do
        assertBool "frontmatter masked" (not (T.isInfixOf "title: Fm" masked))
        assertBool "heading masked" (not (T.isInfixOf "# Heading" masked))
        assertBool "code masked" (not (T.isInfixOf "`code`" masked))
        assertBool "wikilink masked" (not (T.isInfixOf "[[link]]" masked))
  , testCase "preserves unprotected body text" $
      let content = "---\ntitle: X\n---\n# H\nImportant body content here"
          masked = maskProtectedRegions content
      in assertBool "body preserved" (T.isInfixOf "Important body content here" masked)
  ]

propertyTests :: TestTree
propertyTests = testGroup "properties"
  [ testProperty "masking preserves text length" $ \s ->
      let txt = T.pack (s :: String)
          masked = maskProtectedRegions txt
      in T.length masked == T.length txt
  , testProperty "masking plain alphanumeric text is identity" $ \s ->
      let txt = T.pack (filter (\c -> c /= '`' && c /= '[' && c /= ']' && c /= '#' && c /= '*' && c /= '-' && c /= '~' && c /= '(' && c /= ')' && c /= ':' && c /= '/' && c /= '\n') (s :: String))
      in maskProtectedRegions txt == txt
  ]
