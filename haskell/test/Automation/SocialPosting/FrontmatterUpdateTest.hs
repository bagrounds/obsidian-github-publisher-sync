module Automation.SocialPosting.FrontmatterUpdateTest (tests) where

import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Data.Time (UTCTime (..), fromGregorian)
import System.Directory (getModificationTime, setModificationTime)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertEqual, assertBool, testCase)
import Test.Tasty.QuickCheck (testProperty)
import qualified Test.Tasty.QuickCheck as QC

import Automation.SocialPosting.FrontmatterUpdate

tests :: TestTree
tests = testGroup "SocialPosting.FrontmatterUpdate"
  [ upsertFrontmatterFieldTests
  , updateFrontmatterUrlTests
  , updateFrontmatterTimestampTests
  , pureTransformTests
  ]

-- upsertFrontmatterField

upsertFrontmatterFieldTests :: TestTree
upsertFrontmatterFieldTests = testGroup "upsertFrontmatterField"
  [ testCase "inserts new field when not present" $
      assertEqual "" ["title: My Title", "URL: \"https://example.com\""]
        (upsertFrontmatterField ["title: My Title"] "URL" "\"https://example.com\"")

  , testCase "updates existing field" $
      assertEqual "" ["title: My Title", "URL: \"https://new.com\""]
        (upsertFrontmatterField ["title: My Title", "URL: \"https://old.com\""] "URL" "\"https://new.com\"")

  , testCase "preserves other fields when updating" $
      assertEqual "" ["title: My Title", "URL: \"https://new.com\"", "share: true"]
        (upsertFrontmatterField ["title: My Title", "URL: \"https://old.com\"", "share: true"] "URL" "\"https://new.com\"")

  , testCase "handles empty field list" $
      assertEqual "" ["updated: \"2026-01-01\""]
        (upsertFrontmatterField [] "updated" "\"2026-01-01\"")
  ]

-- updateFrontmatterUrl

updateFrontmatterUrlTests :: TestTree
updateFrontmatterUrlTests = testGroup "updateFrontmatterUrl"
  [ testCase "updates existing URL field" $
      withSystemTempDirectory "fm-url-test" $ \directory -> do
        let notePath = directory </> "test-note.md"
        TIO.writeFile notePath
          "---\ntitle: Test Note\nURL: \"https://bagrounds.org/old-path\"\n---\nBody content"
        updateFrontmatterUrl notePath "https://bagrounds.org/new-path"
        content <- TIO.readFile notePath
        assertBool "should contain new URL"
          (T.isInfixOf "https://bagrounds.org/new-path" content)
        assertBool "should not contain old URL"
          (not (T.isInfixOf "https://bagrounds.org/old-path" content))

  , testCase "adds URL field when missing" $
      withSystemTempDirectory "fm-url-test" $ \directory -> do
        let notePath = directory </> "no-url-note.md"
        TIO.writeFile notePath
          "---\ntitle: No URL Note\n---\nBody content"
        updateFrontmatterUrl notePath "https://bagrounds.org/new-url"
        content <- TIO.readFile notePath
        assertBool "should contain added URL"
          (T.isInfixOf "https://bagrounds.org/new-url" content)

  , testCase "does nothing for nonexistent file" $
      updateFrontmatterUrl "/nonexistent/path/note.md" "https://example.com"

  , testCase "leaves file untouched when unquoted URL already matches" $
      withSystemTempDirectory "fm-url-test" $ \directory -> do
        let notePath = directory </> "matching-note.md"
            original = "---\ntitle: Matching Note\nURL: https://bagrounds.org/books/matching-note\n---\nBody content"
        TIO.writeFile notePath original
        setModificationTime notePath untouchedModificationTime
        updateFrontmatterUrl notePath "https://bagrounds.org/books/matching-note"
        content <- TIO.readFile notePath
        modificationTime <- getModificationTime notePath
        assertEqual "content should be unchanged" original content
        assertEqual "file should not be rewritten" untouchedModificationTime modificationTime

  , testCase "leaves file untouched when quoted URL already matches" $
      withSystemTempDirectory "fm-url-test" $ \directory -> do
        let notePath = directory </> "quoted-note.md"
            original = "---\ntitle: Quoted Note\nURL: \"https://bagrounds.org/books/quoted-note\"\n---\nBody content"
        TIO.writeFile notePath original
        setModificationTime notePath untouchedModificationTime
        updateFrontmatterUrl notePath "https://bagrounds.org/books/quoted-note"
        modificationTime <- getModificationTime notePath
        assertEqual "file should not be rewritten" untouchedModificationTime modificationTime
  ]

untouchedModificationTime :: UTCTime
untouchedModificationTime = UTCTime (fromGregorian 2020 1 1) 0

-- updateFrontmatterTimestamp

stampTime :: UTCTime
stampTime = UTCTime (fromGregorian 2026 11 1) 45296

updateFrontmatterTimestampTests :: TestTree
updateFrontmatterTimestampTests = testGroup "updateFrontmatterTimestamp"
  [ testCase "adds updated timestamp to frontmatter" $
      withSystemTempDirectory "fm-ts-test" $ \directory -> do
        let notePath = directory </> "test-note.md"
        TIO.writeFile notePath
          "---\ntitle: Test Note\n---\nBody content"
        updateFrontmatterTimestamp stampTime notePath
        content <- TIO.readFile notePath
        assertEqual "should contain injected timestamp"
          "---\ntitle: Test Note\nupdated: \"2026-11-01T12:34:56\"\n---\nBody content" content

  , testCase "updates existing timestamp" $
      withSystemTempDirectory "fm-ts-test" $ \directory -> do
        let notePath = directory </> "test-note.md"
        TIO.writeFile notePath
          "---\ntitle: Test Note\nupdated: \"2020-01-01T00:00:00\"\n---\nBody content"
        updateFrontmatterTimestamp stampTime notePath
        content <- TIO.readFile notePath
        assertBool "should not contain old timestamp"
          (not (T.isInfixOf "2020-01-01T00:00:00" content))
        assertBool "should contain injected timestamp"
          (T.isInfixOf "updated: \"2026-11-01T12:34:56\"" content)

  , testCase "does not rewrite a note whose timestamp already matches" $
      withSystemTempDirectory "fm-ts-test" $ \directory -> do
        let notePath = directory </> "test-note.md"
        TIO.writeFile notePath
          "---\ntitle: Test Note\nupdated: \"2026-11-01T12:34:56\"\n---\nBody content"
        setModificationTime notePath untouchedModificationTime
        updateFrontmatterTimestamp stampTime notePath
        modificationTime <- getModificationTime notePath
        assertEqual "file should not be rewritten" untouchedModificationTime modificationTime

  , testCase "does nothing for nonexistent file" $
      updateFrontmatterTimestamp stampTime "/nonexistent/path/note.md"
  ]

-- pure frontmatter transforms

pureTransformTests :: TestTree
pureTransformTests = testGroup "pure frontmatter transforms"
  [ testCase "setUpdatedTimestamp leaves content without frontmatter unchanged" $
      assertEqual "" "Just a body" (setUpdatedTimestamp stampTime "Just a body")

  , testCase "setCanonicalUrl keeps an equal unquoted URL byte-for-byte" $
      let content = "---\nURL: https://bagrounds.org/books/a\n---\nBody"
      in assertEqual "" content (setCanonicalUrl "https://bagrounds.org/books/a" content)

  , testCase "setCanonicalUrl replaces a stale URL" $
      assertEqual ""
        "---\nURL: \"https://bagrounds.org/books/new\"\n---\nBody"
        (setCanonicalUrl "https://bagrounds.org/books/new" "---\nURL: https://bagrounds.org/books/old\n---\nBody")

  , testProperty "setCanonicalUrl is idempotent" $
      \(slug :: String) ->
        let url = "https://bagrounds.org/" <> T.pack (filter (`notElem` ("\"\\\n\r" :: String)) slug)
            content = "---\ntitle: Note\n---\nBody"
            once = setCanonicalUrl url content
        in setCanonicalUrl url once QC.=== once

  , testProperty "setFrontmatterField is idempotent" $
      \(value :: String) ->
        let rendered = T.pack (filter (`notElem` ("\n\r" :: String)) value)
            content = "---\ntitle: Note\n---\nBody"
            once = setFrontmatterField "field" rendered content
        in setFrontmatterField "field" rendered once QC.=== once
  ]
