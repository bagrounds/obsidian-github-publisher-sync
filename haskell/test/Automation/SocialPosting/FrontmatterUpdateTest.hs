module Automation.SocialPosting.FrontmatterUpdateTest (tests) where

import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertEqual, assertBool, testCase)

import Automation.SocialPosting.FrontmatterUpdate

tests :: TestTree
tests = testGroup "SocialPosting.FrontmatterUpdate"
  [ upsertFrontmatterFieldTests
  , updateFrontmatterUrlTests
  , updateFrontmatterTimestampTests
  , updatePathTimestampsTests
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
  ]

-- updateFrontmatterTimestamp

updateFrontmatterTimestampTests :: TestTree
updateFrontmatterTimestampTests = testGroup "updateFrontmatterTimestamp"
  [ testCase "adds updated timestamp to frontmatter" $
      withSystemTempDirectory "fm-ts-test" $ \directory -> do
        let notePath = directory </> "test-note.md"
        TIO.writeFile notePath
          "---\ntitle: Test Note\n---\nBody content"
        updateFrontmatterTimestamp notePath
        content <- TIO.readFile notePath
        assertBool "should contain updated field"
          (T.isInfixOf "updated:" content)

  , testCase "updates existing timestamp" $
      withSystemTempDirectory "fm-ts-test" $ \directory -> do
        let notePath = directory </> "test-note.md"
        TIO.writeFile notePath
          "---\ntitle: Test Note\nupdated: \"2020-01-01T00:00:00\"\n---\nBody content"
        updateFrontmatterTimestamp notePath
        content <- TIO.readFile notePath
        assertBool "should not contain old timestamp"
          (not (T.isInfixOf "2020-01-01T00:00:00" content))
        assertBool "should contain updated field"
          (T.isInfixOf "updated:" content)

  , testCase "does nothing for nonexistent file" $
      updateFrontmatterTimestamp "/nonexistent/path/note.md"
  ]

-- updatePathTimestamps

updatePathTimestampsTests :: TestTree
updatePathTimestampsTests = testGroup "updatePathTimestamps"
  [ testCase "updates timestamps for multiple paths" $
      withSystemTempDirectory "fm-paths-test" $ \directory -> do
        let booksDirectory = directory </> "books"
        createDirectoryIfMissing True booksDirectory
        TIO.writeFile (booksDirectory </> "book-a.md")
          "---\ntitle: Book A\n---\nContent A"
        TIO.writeFile (booksDirectory </> "book-b.md")
          "---\ntitle: Book B\n---\nContent B"
        updatePathTimestamps directory ["books/book-a.md", "books/book-b.md"]
        contentA <- TIO.readFile (booksDirectory </> "book-a.md")
        contentB <- TIO.readFile (booksDirectory </> "book-b.md")
        assertBool "book A should have updated field"
          (T.isInfixOf "updated:" contentA)
        assertBool "book B should have updated field"
          (T.isInfixOf "updated:" contentB)
  ]
