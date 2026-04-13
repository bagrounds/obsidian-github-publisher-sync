{-# LANGUAGE OverloadedStrings #-}

module Automation.InternalLinking.LinkExtractionTest (tests) where

import Automation.InternalLinking.LinkExtraction
  ( extractLinkedPaths
  , normalizeFilePath
  , makeRelativeTo
  , splitSlash
  , joinSlash
  , hasSuffix
  )
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertEqual, assertBool, testCase)
import Test.Tasty.QuickCheck (testProperty)
import qualified Test.QuickCheck as QC

tests :: TestTree
tests = testGroup "InternalLinking.LinkExtraction"
  [ normalizeFilePathTests
  , makeRelativeToTests
  , splitSlashTests
  , joinSlashTests
  , hasSuffixTests
  , extractLinkedPathsTests
  , propertyTests
  ]

normalizeFilePathTests :: TestTree
normalizeFilePathTests = testGroup "normalizeFilePath"
  [ testCase "resolves parent directory references" $
      assertEqual "" "books/foo.md" (normalizeFilePath "reflections/../books/foo.md")
  , testCase "resolves current directory references" $
      assertEqual "" "books/foo.md" (normalizeFilePath "books/./foo.md")
  , testCase "preserves simple paths" $
      assertEqual "" "books/foo.md" (normalizeFilePath "books/foo.md")
  , testCase "handles multiple parent refs" $
      assertEqual "" "foo.md" (normalizeFilePath "a/b/../../foo.md")
  , testCase "handles complex nested path" $
      assertEqual "" "reflections/topics/bar.md" (normalizeFilePath "reflections/2025/../topics/./bar.md")
  , testCase "handles single file" $
      assertEqual "" "file.md" (normalizeFilePath "file.md")
  , testCase "handles empty path" $
      assertEqual "" "" (normalizeFilePath "")
  ]

makeRelativeToTests :: TestTree
makeRelativeToTests = testGroup "makeRelativeTo"
  [ testCase "removes common prefix" $
      assertEqual "" "books/foo.md" (makeRelativeTo "/content" "/content/books/foo.md")
  , testCase "handles identical paths" $
      assertEqual "" "" (makeRelativeTo "a/b" "a/b")
  , testCase "handles nested paths" $
      assertEqual "" "foo.md" (makeRelativeTo "a/b/c" "a/b/c/foo.md")
  , testCase "handles no common prefix" $
      assertEqual "" "x/y/z.md" (makeRelativeTo "a/b" "x/y/z.md")
  ]

splitSlashTests :: TestTree
splitSlashTests = testGroup "splitSlash"
  [ testCase "splits simple path" $
      assertEqual "" ["a", "b", "c"] (splitSlash "a/b/c")
  , testCase "handles single segment" $
      assertEqual "" ["file.md"] (splitSlash "file.md")
  , testCase "handles empty string" $
      assertEqual "" [] (splitSlash "")
  , testCase "handles leading slash" $
      assertEqual "" ["content", "books"] (splitSlash "/content/books")
  , testCase "handles trailing slash" $
      assertEqual "" ["content", "books"] (splitSlash "content/books/")
  ]

joinSlashTests :: TestTree
joinSlashTests = testGroup "joinSlash"
  [ testCase "joins segments" $
      assertEqual "" "a/b/c" (joinSlash ["a", "b", "c"])
  , testCase "handles single segment" $
      assertEqual "" "file.md" (joinSlash ["file.md"])
  , testCase "handles empty list" $
      assertEqual "" "" (joinSlash [])
  ]

hasSuffixTests :: TestTree
hasSuffixTests = testGroup "hasSuffix"
  [ testCase "matches .md suffix" $
      assertBool "has .md" (hasSuffix ".md" "file.md")
  , testCase "rejects non-matching suffix" $
      assertBool "no .txt" (not (hasSuffix ".txt" "file.md"))
  , testCase "matches empty suffix" $
      assertBool "empty suffix" (hasSuffix "" "anything")
  , testCase "handles equal strings" $
      assertBool "equal" (hasSuffix ".md" ".md")
  ]

extractLinkedPathsTests :: TestTree
extractLinkedPathsTests = testGroup "extractLinkedPaths"
  [ testCase "skips external URLs" $
      let body = "See [title](https://example.com/foo.md) here"
          paths = extractLinkedPaths body "reflections/2025-01-01.md" "/content"
      in assertEqual "no paths" 0 (length paths)
  , testCase "returns empty for plain text" $
      let paths = extractLinkedPaths "No links here" "reflections/r.md" "/content"
      in assertEqual "no paths" 0 (length paths)
  , testCase "extracts wiki links" $
      let body = "Read [[books/a]] and [[topics/b]] today"
          paths = extractLinkedPaths body "reflections/2025-01-01.md" "/content"
      in assertEqual "two links" 2 (length paths)
  , testCase "resolves plain wikilinks relative to note directory" $
      let body = "I enjoyed [[some-book]] today"
          paths = extractLinkedPaths body "reflections/2025-01-01.md" "/content"
      in assertEqual "relative to reflections" ["reflections/some-book.md"] paths
  , testCase "resolves relative markdown links" $
      let body = "See [book](../books/foo.md) for details"
          paths = extractLinkedPaths body "reflections/2025-01-01.md" "/content"
      in assertEqual "resolved" ["books/foo.md"] paths
  , testCase "deduplicates links" $
      let body = "See [[books/a]] and [[books/a]] again"
          paths = extractLinkedPaths body "reflections/r.md" "/content"
      in assertEqual "deduplicated" 1 (length paths)
  , testCase "skips parent directory links" $
      let body = "See [[../../secret]] here"
          paths = extractLinkedPaths body "reflections/r.md" "/content"
      in assertEqual "skipped" 0 (length paths)
  ]

propertyTests :: TestTree
propertyTests = testGroup "properties"
  [ testProperty "splitSlash and joinSlash round-trip for non-empty segments" $ \segments ->
      let nonEmpty = filter (not . null) (segments :: [String])
          noSlashes = filter (notElem '/') nonEmpty
      in not (null noSlashes) QC.==>
        splitSlash (joinSlash noSlashes) == noSlashes
  , testProperty "normalizeFilePath is idempotent" $ \s ->
      let path = filter (\c -> c /= '\0' && c /= '\n') (s :: String)
          normalized = normalizeFilePath path
      in normalizeFilePath normalized == normalized
  , testProperty "hasSuffix with full string is always true" $ \s ->
      hasSuffix (s :: String) s
  ]
