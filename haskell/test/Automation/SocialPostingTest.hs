module Automation.SocialPostingTest (tests) where

import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertEqual, assertBool, testCase)
import Test.Tasty.QuickCheck (testProperty)
import qualified Test.Tasty.QuickCheck as QC
import qualified Data.Text.IO as TIO

import Automation.SocialPosting

tests :: TestTree
tests = testGroup "SocialPosting"
  [ detectPlatformTests
  , linkExtractionTests
  , contentFilterTests
  , pathReconstructionTests
  , reflectionEligibilityTests
  , bfsTests
  ]

--------------------------------------------------------------------------------
-- Platform detection
--------------------------------------------------------------------------------

detectPlatformTests :: TestTree
detectPlatformTests = testGroup "detectPostedPlatforms"
  [ testCase "detects no platforms in empty content" $
      assertEqual "" Set.empty (detectPostedPlatforms "")

  , testCase "detects tweet section" $
      assertEqual "" (Set.singleton Twitter)
        (detectPostedPlatforms "some text\n## 🐦 Tweet\ntweet content")

  , testCase "detects bluesky section" $
      assertEqual "" (Set.singleton Bluesky)
        (detectPostedPlatforms "some text\n## 🦋 Bluesky\nbluesky content")

  , testCase "detects mastodon section" $
      assertEqual "" (Set.singleton Mastodon)
        (detectPostedPlatforms "some text\n## 🐘 Mastodon\nmastodon content")

  , testCase "detects all three platforms" $
      assertEqual "" (Set.fromList [Twitter, Bluesky, Mastodon])
        (detectPostedPlatforms
          "text\n## 🐦 Tweet\nt\n## 🦋 Bluesky\nb\n## 🐘 Mastodon\nm")

  , testProperty "empty content has no platforms" $
      \() -> Set.null (detectPostedPlatforms "")
  ]

--------------------------------------------------------------------------------
-- Link extraction
--------------------------------------------------------------------------------

linkExtractionTests :: TestTree
linkExtractionTests = testGroup "extractMarkdownLinks"
  [ testCase "extracts markdown links" $ do
      withSystemTempDirectory "social-test" $ \dir -> do
        let body = "See [this](../books/foo.md) and [that](../topics/bar.md)"
            links = extractMarkdownLinks body "reflections/2025-01-01.md" dir
        assertBool "should find links" (length links >= 1)

  , testCase "extracts wiki links with absolute paths" $ do
      withSystemTempDirectory "social-test" $ \dir -> do
        let body = "See [[books/my-book]] and [[topics/my-topic]]"
            links = extractMarkdownLinks body "index.md" dir
        assertBool "should find links" (length links >= 2)

  , testCase "skips external URLs" $ do
      withSystemTempDirectory "social-test" $ \dir -> do
        let body = "See [this](https://example.com/foo.md)"
            links = extractMarkdownLinks body "reflections/2025-01-01.md" dir
        assertEqual "no links" [] links

  , testCase "deduplicates links" $ do
      withSystemTempDirectory "social-test" $ \dir -> do
        let body = "See [a](books/foo.md) and [b](books/foo.md)"
            links = extractMarkdownLinks body "reflections/2025-01-01.md" dir
        assertEqual "one unique link" 1 (length links)
  ]

--------------------------------------------------------------------------------
-- Content filtering
--------------------------------------------------------------------------------

contentFilterTests :: TestTree
contentFilterTests = testGroup "content filtering"
  [ testCase "isPostableContent rejects index pages" $
      assertBool "index page should not be postable" $
        not (isPostableContent (mkNote "books/index.md" "Index" (T.replicate 60 "x")))

  , testCase "isPostableContent rejects short content" $
      assertBool "short content not postable" $
        not (isPostableContent (mkNote "books/foo.md" "Foo" "short"))

  , testCase "isPostableContent accepts normal content" $
      assertBool "normal content should be postable" $
        isPostableContent (mkNote "books/foo.md" "Great Book Title" (T.replicate 60 "x"))

  , testCase "isPostableContent rejects no_social flagged" $
      assertBool "no_social should not be postable" $
        not (isPostableContent (mkNote "books/foo.md" "Foo" (T.replicate 60 "x"))
          { cnNoSocial = True })

  , testCase "isUntitledReflection identifies date-only titles" $
      assertBool "date-only title in reflections is untitled" $
        isUntitledReflection (mkNote "reflections/2025-01-15.md" "2025-01-15" "body")

  , testCase "isUntitledReflection allows creative titles" $
      assertBool "creative title is not untitled" $
        not (isUntitledReflection (mkNote "reflections/2025-01-15.md" "My Reflection" "body"))

  , testCase "isUntitledReflection ignores non-reflections" $
      assertBool "non-reflection with date title is fine" $
        not (isUntitledReflection (mkNote "books/2025-01-15.md" "2025-01-15" "body"))
  ]

--------------------------------------------------------------------------------
-- Path reconstruction
--------------------------------------------------------------------------------

pathReconstructionTests :: TestTree
pathReconstructionTests = testGroup "reconstructPath"
  [ testCase "single node path" $
      assertEqual "" ["a"] (reconstructPath Map.empty "a" "a")

  , testCase "two node path" $
      assertEqual "" ["a", "b"]
        (reconstructPath (Map.singleton "b" "a") "a" "b")

  , testCase "three node path" $
      assertEqual "" ["a", "b", "c"]
        (reconstructPath (Map.fromList [("b", "a"), ("c", "b")]) "a" "c")
  ]

--------------------------------------------------------------------------------
-- Reflection eligibility
--------------------------------------------------------------------------------

reflectionEligibilityTests :: TestTree
reflectionEligibilityTests = testGroup "isReflectionEligibleForPosting"
  [ testCase "very old reflection is eligible" $ do
      result <- isReflectionEligibleForPosting "2020-01-01" 17
      assertBool "old reflection should be eligible" result
  ]

--------------------------------------------------------------------------------
-- BFS discovery
--------------------------------------------------------------------------------

bfsTests :: TestTree
bfsTests = testGroup "BFS discovery"
  [ testCase "findMostRecentReflection with no reflections dir" $ do
      withSystemTempDirectory "social-test" $ \dir -> do
        result <- findMostRecentReflection dir
        assertEqual "" Nothing result

  , testCase "findMostRecentReflection finds latest" $ do
      withSystemTempDirectory "social-test" $ \dir -> do
        let reflDir = dir </> "reflections"
        createDirectoryIfMissing True reflDir
        TIO.writeFile (reflDir </> "2025-01-01.md") "---\ntitle: Day 1\n---\nbody"
        TIO.writeFile (reflDir </> "2025-01-15.md") "---\ntitle: Day 15\n---\nbody"
        TIO.writeFile (reflDir </> "2025-01-10.md") "---\ntitle: Day 10\n---\nbody"
        result <- findMostRecentReflection dir
        assertEqual "" (Just "reflections/2025-01-15.md") result

  , testCase "readContentNote reads a note" $ do
      withSystemTempDirectory "social-test" $ \dir -> do
        let noteDir = dir </> "books"
        createDirectoryIfMissing True noteDir
        TIO.writeFile (noteDir </> "my-book.md")
          "---\ntitle: My Book\nURL: https://example.com/books/my-book\n---\nThis is a great book about many things."
        result <- readContentNote "books/my-book.md" dir
        case result of
          Nothing -> assertBool "should have read note" False
          Just note -> do
            assertEqual "title" "My Book" (cnTitle note)
            assertEqual "url" "https://example.com/books/my-book" (cnUrl note)

  , testCase "bfsContentDiscovery with empty dir returns empty" $ do
      withSystemTempDirectory "social-test" $ \dir -> do
        let config = FindContentConfig dir [Twitter, Bluesky] 17
        result <- bfsContentDiscovery config
        assertEqual "" [] result

  , testCase "bfsContentDiscovery finds postable linked content" $ do
      withSystemTempDirectory "social-test" $ \dir -> do
        let reflDir = dir </> "reflections"
            booksDir = dir </> "books"
        createDirectoryIfMissing True reflDir
        createDirectoryIfMissing True booksDir
        TIO.writeFile (reflDir </> "2025-01-15.md")
          ("---\ntitle: My Creative Day\n---\n" <>
           "Today I read [[books/great-book]]\n" <>
           T.replicate 60 "x")
        TIO.writeFile (booksDir </> "great-book.md")
          ("---\ntitle: A Great Book\nURL: https://example.com/books/great-book\n---\n" <>
           T.replicate 60 "x")
        let config = FindContentConfig dir [Twitter, Bluesky, Mastodon] 0
        result <- bfsContentDiscovery config
        assertBool "should find content to post" (not (null result))
  ]

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

mkNote :: Text -> Text -> Text -> ContentNote
mkNote relPath title body = ContentNote
  { cnFilePath = T.unpack relPath
  , cnRelativePath = relPath
  , cnTitle = title
  , cnUrl = "https://example.com/" <> relPath
  , cnBody = body
  , cnPostedPlatforms = Set.empty
  , cnLinkedNotePaths = []
  , cnNoSocial = False
  }
