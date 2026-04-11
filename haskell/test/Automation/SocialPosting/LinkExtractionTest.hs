module Automation.SocialPosting.LinkExtractionTest (tests) where

import qualified Data.Map.Strict as Map
import Data.Text (Text)
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertEqual, assertBool, testCase)
import Test.Tasty.QuickCheck (testProperty)
import qualified Test.Tasty.QuickCheck as QC

import Automation.SocialPosting.LinkExtraction

tests :: TestTree
tests = testGroup "SocialPosting.LinkExtraction"
  [ parseWikiLinksTests
  , normalizeFilePathTests
  , reconstructPathTests
  , extractMarkdownLinksTests
  ]

-- parseWikiLinks

parseWikiLinksTests :: TestTree
parseWikiLinksTests = testGroup "parseWikiLinks"
  [ testCase "parses simple wiki link" $
      assertEqual "" ["books/my-book"] (parseWikiLinks "See [[books/my-book]] here")

  , testCase "parses multiple wiki links" $
      assertEqual "" ["books/a", "topics/b"]
        (parseWikiLinks "Read [[books/a]] about [[topics/b]]")

  , testCase "handles section anchors" $
      assertEqual "" ["books/my-book"]
        (parseWikiLinks "See [[books/my-book#section]] here")

  , testCase "handles display text" $
      assertEqual "" ["books/my-book"]
        (parseWikiLinks "See [[books/my-book|My Book Title]] here")

  , testCase "handles section and display text" $
      assertEqual "" ["books/my-book"]
        (parseWikiLinks "See [[books/my-book#section|Display Text]] here")

  , testCase "returns empty for no wiki links" $
      assertEqual "" [] (parseWikiLinks "No links here at all")

  , testCase "returns empty for incomplete opening brackets" $
      assertEqual "" [] (parseWikiLinks "See [not-a-link] here")

  , testCase "returns empty for empty wiki link" $
      assertEqual "" [] (parseWikiLinks "See [[]] here")

  , testCase "handles link without path separator" $
      assertEqual "" ["my-note"] (parseWikiLinks "See [[my-note]] here")

  , testCase "handles adjacent wiki links" $
      assertEqual "" ["a", "b"]
        (parseWikiLinks "[[a]][[b]]")

  , testProperty "never crashes on arbitrary input" $
      \(QC.ASCIIString s) -> seq (parseWikiLinks s) True
  ]

-- normalizeFilePath

normalizeFilePathTests :: TestTree
normalizeFilePathTests = testGroup "normalizeFilePath"
  [ testCase "resolves parent directory references" $
      assertEqual "" "books/foo.md"
        (normalizeFilePath "reflections/../books/foo.md")

  , testCase "resolves current directory references" $
      assertEqual "" "books/foo.md"
        (normalizeFilePath "books/./foo.md")

  , testCase "preserves simple paths" $
      assertEqual "" "books/foo.md"
        (normalizeFilePath "books/foo.md")

  , testCase "handles multiple parent refs" $
      assertEqual "" "foo.md"
        (normalizeFilePath "a/b/../../foo.md")

  , testCase "handles complex nested path" $
      assertEqual "" "reflections/topics/bar.md"
        (normalizeFilePath "reflections/2025/../topics/./bar.md")

  , testProperty "normalizing a normalized path is idempotent" $
      \(QC.ASCIIString s) ->
        let cleaned = filter (\c -> c /= '.' && c /= ' ' && c /= '\0') s
            normalized = normalizeFilePath cleaned
        in normalizeFilePath normalized == normalized
  ]

-- reconstructPath

reconstructPathTests :: TestTree
reconstructPathTests = testGroup "reconstructPath"
  [ testCase "single node path" $
      assertEqual "" ["a"] (reconstructPath Map.empty "a" "a")

  , testCase "two node path" $
      assertEqual "" ["a", "b"]
        (reconstructPath (Map.singleton "b" "a") "a" "b")

  , testCase "three node path" $
      assertEqual "" ["a", "b", "c"]
        (reconstructPath (Map.fromList [("b", "a"), ("c", "b")]) "a" "c")

  , testCase "four node path" $
      assertEqual "" ["a", "b", "c", "d"]
        (reconstructPath (Map.fromList [("b", "a"), ("c", "b"), ("d", "c")]) "a" "d")

  , testCase "handles unknown target gracefully" $
      assertEqual "" ["z"]
        (reconstructPath Map.empty "a" "z")
  ]

-- extractMarkdownLinks

extractMarkdownLinksTests :: TestTree
extractMarkdownLinksTests = testGroup "extractMarkdownLinks"
  [ testCase "extracts markdown links" $
      withSystemTempDirectory "link-test" $ \dir -> do
        let body = "See [this](../books/foo.md) and [that](../topics/bar.md)" :: Text
            links = extractMarkdownLinks body "reflections/2025-01-01.md" dir
        assertBool "should find links" (not (null links))

  , testCase "extracts wiki links with absolute paths" $
      withSystemTempDirectory "link-test" $ \dir -> do
        let body = "See [[books/my-book]] and [[topics/my-topic]]" :: Text
            links = extractMarkdownLinks body "index.md" dir
        assertBool "should find links" (length links >= 2)

  , testCase "skips external URLs" $
      withSystemTempDirectory "link-test" $ \dir -> do
        let body = "See [this](https://example.com/foo.md)" :: Text
            links = extractMarkdownLinks body "reflections/2025-01-01.md" dir
        assertEqual "no links" [] links

  , testCase "deduplicates links" $
      withSystemTempDirectory "link-test" $ \dir -> do
        let body = "See [a](books/foo.md) and [b](books/foo.md)" :: Text
            links = extractMarkdownLinks body "reflections/2025-01-01.md" dir
        assertEqual "one unique link" 1 (length links)
  ]
