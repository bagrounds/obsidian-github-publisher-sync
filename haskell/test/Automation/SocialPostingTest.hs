module Automation.SocialPostingTest (tests) where

import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Data.Time.LocalTime (TimeOfDay (..))
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertEqual, assertBool, testCase, (@?=))
import Test.Tasty.QuickCheck (testProperty)
import qualified Test.Tasty.QuickCheck as QC
import qualified Data.Text.IO as TIO

import Automation.SocialPosting
import Automation.Reflection (selectMostRecentReflection)
import Automation.TestGenerators (testUrl, testTitle, testRelativePath)
import Automation.Types (RelativePath, mkRelativePath, Title, mkTitle, Url, mkUrl)

tests :: TestTree
tests = testGroup "SocialPosting"
  [ detectPlatformTests
  , detectPlatformExtendedTests
  , linkExtractionTests
  , wikiLinkParserTests
  , normalizeFilePathTests
  , contentFilterTests
  , contentFilterExtendedTests
  , imageBackfillFilterTests
  , indexPathTests
  , pathReconstructionTests
  , reflectionEligibilityTests
  , bfsEligibilityTests
  , bfsTraversalTests
  , bfsTests
  , urlValidationTests
  , selectMostRecentReflectionTests
  , socialPostTests
  , readContentNoteTests
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
-- Extended platform detection
--------------------------------------------------------------------------------

detectPlatformExtendedTests :: TestTree
detectPlatformExtendedTests = testGroup "detectPostedPlatforms (extended)"
  [ testCase "does not detect partial header match" $
      assertEqual "" Set.empty
        (detectPostedPlatforms "## Tweet without emoji")

  , testCase "detects twitter and mastodon only" $
      assertEqual "" (Set.fromList [Twitter, Mastodon])
        (detectPostedPlatforms "## 🐦 Tweet\ntweet\n## 🐘 Mastodon\ntoot")

  , testCase "plain text without headers has no platforms" $
      assertEqual "" Set.empty
        (detectPostedPlatforms "just some text about birds and butterflies")
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
        assertBool "should find links" (not (null links))

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
-- Wiki link parser (replacing regex with recursive descent)
--------------------------------------------------------------------------------

wikiLinkParserTests :: TestTree
wikiLinkParserTests = testGroup "parseWikiLinks"
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

--------------------------------------------------------------------------------
-- Path normalization
--------------------------------------------------------------------------------

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
-- Extended content filtering
--------------------------------------------------------------------------------

contentFilterExtendedTests :: TestTree
contentFilterExtendedTests = testGroup "content filtering (extended)"
  [ testCase "isPostableContent rejects content at exactly min length minus one" $
      assertBool "49 chars not postable" $
        not (isPostableContent (mkNote "books/foo.md" "Foo" (T.replicate 49 "x")))

  , testCase "isPostableContent accepts content at exactly min length" $
      assertBool "50 chars postable" $
        isPostableContent (mkNote "books/foo.md" "Good Title" (T.replicate 50 "x"))

  , testCase "isUntitledReflection rejects date with extra text" $
      assertBool "date-plus-text is titled" $
        not (isUntitledReflection (mkNote "reflections/2025-01-15.md" "2025-01-15 My Day" "body"))

  , testCase "isPostableContent rejects whitespace-only body" $
      assertBool "whitespace body not postable" $
        not (isPostableContent (mkNote "books/foo.md" "Foo" "   \n  \n  "))
  ]

--------------------------------------------------------------------------------
-- Image backfill filter
--------------------------------------------------------------------------------

imageBackfillFilterTests :: TestTree
imageBackfillFilterTests = testGroup "isAwaitingImageBackfill"
  [ testCase "note without image in backfill directory is awaiting" $
      assertBool "should be awaiting image" $
        isAwaitingImageBackfill "books/great-book.md" "Some text about a great book"

  , testCase "note with embedded image is not awaiting" $
      assertBool "has image, should not be awaiting" $
        not (isAwaitingImageBackfill "books/great-book.md"
          "![[attachments/books-great-book.jpg]]\nSome text about a great book")

  , testCase "note with markdown image is not awaiting" $
      assertBool "has markdown image, should not be awaiting" $
        not (isAwaitingImageBackfill "books/great-book.md"
          "![cover](attachments/books-great-book.png)\nSome text")

  , testCase "reflection without image is awaiting" $
      assertBool "reflection without image should be awaiting" $
        isAwaitingImageBackfill "reflections/2026-04-07.md" "Today was a good day"

  , testCase "reflection with image is not awaiting" $
      assertBool "reflection with image should not be awaiting" $
        not (isAwaitingImageBackfill "reflections/2026-04-07.md"
          "![[attachments/reflections-2026-04-07.jpg]]\nToday was a good day")

  , testCase "ai-blog post without image is awaiting" $
      assertBool "ai-blog without image should be awaiting" $
        isAwaitingImageBackfill "ai-blog/2026-04-05-cool-post.md" "A cool blog post"

  , testCase "excluded file is not awaiting" $
      assertBool "index.md should not be awaiting" $
        not (isAwaitingImageBackfill "books/index.md" "Browse all books")

  , testCase "non-md file is not awaiting" $
      assertBool "non-md file should not be awaiting" $
        not (isAwaitingImageBackfill "books/great-book.txt" "Some text")

  , testCase "file not in any content directory is not awaiting" $
      assertBool "unknown directory should not be awaiting" $
        not (isAwaitingImageBackfill "people/john-doe.md" "A person page")

  , testCase "topics directory note without image is awaiting" $
      assertBool "topics note without image should be awaiting" $
        isAwaitingImageBackfill "topics/machine-learning.md" "A topic about ML"

  , testCase "software directory note with image is not awaiting" $
      assertBool "software note with image should not be awaiting" $
        not (isAwaitingImageBackfill "software/cool-tool.md"
          "![[attachments/software-cool-tool.png]]\nA great tool")

  , testCase "BFS skips notes awaiting image but follows their links" $ do
      withSystemTempDirectory "social-image-test" $ \dir -> do
        let reflDir = dir </> "reflections"
            booksDir = dir </> "books"
        createDirectoryIfMissing True reflDir
        createDirectoryIfMissing True booksDir
        TIO.writeFile (reflDir </> "2020-01-01.md")
          ("---\ntitle: \"2020-01-01\"\n---\n" <>
           "See [[books/no-image-book]]\n" <>
           T.replicate 60 "x")
        TIO.writeFile (booksDir </> "no-image-book.md")
          ("---\ntitle: Book Without Image\nURL: https://example.com/books/no-image-book\n---\n" <>
           "Read [[books/has-image-book]]\n" <>
           T.replicate 60 "x")
        TIO.writeFile (booksDir </> "has-image-book.md")
          ("---\ntitle: Book With Image\nURL: https://example.com/books/has-image-book\n---\n" <>
           "![[attachments/books-has-image-book.jpg]]\n" <>
           T.replicate 60 "x")
        let config = FindContentConfig dir [Twitter] (TimeOfDay 0 0 0) Nothing
        result <- bfsContentDiscovery config
        let resultPaths = fmap (cnRelativePath . ctpNote) result
        assertBool "should skip book without image"
          (all (\p -> p /= testRelativePath "books/no-image-book.md") resultPaths)
        assertBool "should find book with image through no-image book"
          (any (\p -> p == testRelativePath "books/has-image-book.md") resultPaths)
  ]

--------------------------------------------------------------------------------
-- Index page eligibility
--------------------------------------------------------------------------------

indexPathTests :: TestTree
indexPathTests = testGroup "isIndexPath and index eligibility"
  [ testCase "isIndexPath detects index.md" $
      assertBool "index.md is an index path" $
        isIndexPath "books/index.md"

  , testCase "isIndexPath detects root index.md" $
      assertBool "index.md is an index path" $
        isIndexPath "index.md"

  , testCase "isIndexPath rejects non-index files" $
      assertBool "book file is not an index path" $
        not (isIndexPath "books/great-book.md")

  , testCase "checkBfsEligibility rejects index pages" $ do
      result <- checkBfsEligibility "books/index.md" (TimeOfDay 17 0 0)
      assertBool "index should not be eligible" (not result)

  , testCase "checkBfsEligibility rejects root index page" $ do
      result <- checkBfsEligibility "index.md" (TimeOfDay 17 0 0)
      assertBool "root index should not be eligible" (not result)
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
  [ testCase "very old reflection is eligible" $
      let now = mkUTC 2026 3 15 12
      in assertBool "old reflection should be eligible"
           (isReflectionEligibleForPosting now (TimeOfDay 17 0 0) (fromGregorian 2020 1 1))

  , testCase "yesterday's reflection is eligible after posting cutoff" $
      let now = mkUTC 2026 3 15 18
      in assertBool "yesterday at hour 18 with posting cutoff 17:00"
           (isReflectionEligibleForPosting now (TimeOfDay 17 0 0) (fromGregorian 2026 3 14))

  , testCase "yesterday's reflection is ineligible before posting cutoff" $
      let now = mkUTC 2026 3 15 10
      in assertBool "yesterday at hour 10 with posting cutoff 17:00"
           (not (isReflectionEligibleForPosting now (TimeOfDay 17 0 0) (fromGregorian 2026 3 14)))

  , testCase "today's reflection is never eligible" $
      let now = mkUTC 2026 3 15 23
      in assertBool "today's reflection should not be eligible"
           (not (isReflectionEligibleForPosting now (TimeOfDay 17 0 0) (fromGregorian 2026 3 15)))

  , testCase "two days ago is always eligible regardless of hour" $
      let now = mkUTC 2026 3 15 0
      in assertBool "two days ago should be eligible even at hour 0"
           (isReflectionEligibleForPosting now (TimeOfDay 17 0 0) (fromGregorian 2026 3 13))

  , testCase "yesterday at exactly the posting cutoff is eligible" $
      let now = mkUTC 2026 3 15 17
      in assertBool "yesterday at exactly posting cutoff"
           (isReflectionEligibleForPosting now (TimeOfDay 17 0 0) (fromGregorian 2026 3 14))
  ]

-- | Build a deterministic UTCTime for testing.
mkUTC :: Integer -> Int -> Int -> Int -> UTCTime
mkUTC year month day hour =
  UTCTime (fromGregorian year month day)
          (secondsToDiffTime (fromIntegral hour * 3600))

--------------------------------------------------------------------------------
-- BFS eligibility (reflection timing in BFS traversal)
--------------------------------------------------------------------------------

bfsEligibilityTests :: TestTree
bfsEligibilityTests = testGroup "checkBfsEligibility"
  [ testCase "non-reflection paths are always eligible" $ do
      result <- checkBfsEligibility "books/great-book.md" (TimeOfDay 17 0 0)
      assertBool "book should be eligible" result

  , testCase "non-reflection in topics dir is eligible" $ do
      result <- checkBfsEligibility "topics/machine-learning.md" (TimeOfDay 17 0 0)
      assertBool "topic should be eligible" result

  , testCase "old reflection is eligible" $ do
      result <- checkBfsEligibility "reflections/2020-01-01.md" (TimeOfDay 17 0 0)
      assertBool "old reflection should be eligible" result

  , testCase "bfsContentDiscovery skips ineligible reflections and finds linked content" $ do
      withSystemTempDirectory "social-test" $ \dir -> do
        let reflDir = dir </> "reflections"
            booksDir = dir </> "books"
        createDirectoryIfMissing True reflDir
        createDirectoryIfMissing True booksDir
        TIO.writeFile (reflDir </> "2099-12-31.md")
          ("---\ntitle: Future Reflection\n---\n" <>
           "Today I read [[books/linked-book]]\n" <>
           T.replicate 60 "x")
        TIO.writeFile (booksDir </> "linked-book.md")
          ("---\ntitle: A Linked Book\nURL: https://example.com/books/linked-book\n---\n" <>
           "![[attachments/books-linked-book.jpg]]\n" <>
           T.replicate 60 "x")
        let config = FindContentConfig dir [Twitter, Bluesky] (TimeOfDay 17 0 0) Nothing
        result <- bfsContentDiscovery config
        let resultPaths = fmap (cnRelativePath . ctpNote) result
        assertBool "should find linked book, not the ineligible reflection"
          (all (\p -> p /= testRelativePath "reflections/2099-12-31.md") resultPaths)
        assertBool "should find the linked book" (not (null result))
  ]

--------------------------------------------------------------------------------
-- BFS traversal through non-postable content
--------------------------------------------------------------------------------

bfsTraversalTests :: TestTree
bfsTraversalTests = testGroup "BFS traversal"
  [ testCase "BFS traverses through index pages to reach postable content" $ do
      withSystemTempDirectory "social-test" $ \dir -> do
        let reflDir = dir </> "reflections"
            booksDir = dir </> "books"
        createDirectoryIfMissing True reflDir
        createDirectoryIfMissing True booksDir
        -- Untitled reflection (date-only title) so BFS must traverse through it
        TIO.writeFile (reflDir </> "2020-01-01.md")
          ("---\ntitle: \"2020-01-01\"\n---\n" <>
           "See [[books/index]]\n" <>
           T.replicate 60 "x")
        TIO.writeFile (booksDir </> "index.md")
          ("---\ntitle: Book Index\n---\n" <>
           "Browse [[books/hidden-gem]]\n" <>
           T.replicate 60 "x")
        TIO.writeFile (booksDir </> "hidden-gem.md")
          ("---\ntitle: A Hidden Gem\nURL: https://example.com/books/hidden-gem\n---\n" <>
           "![[attachments/books-hidden-gem.jpg]]\n" <>
           T.replicate 60 "x")
        let config = FindContentConfig dir [Twitter] (TimeOfDay 0 0 0) Nothing
        result <- bfsContentDiscovery config
        let resultPaths = fmap (cnRelativePath . ctpNote) result
        assertBool "should not post index page"
          (all (\p -> p /= testRelativePath "books/index.md") resultPaths)
        assertBool "should find hidden gem through index page"
          (any (\p -> p == testRelativePath "books/hidden-gem.md") resultPaths)

  , testCase "BFS traverses through no_social content to reach postable content" $ do
      withSystemTempDirectory "social-test" $ \dir -> do
        let reflDir = dir </> "reflections"
            topicsDir = dir </> "topics"
            booksDir = dir </> "books"
        createDirectoryIfMissing True reflDir
        createDirectoryIfMissing True topicsDir
        createDirectoryIfMissing True booksDir
        -- Untitled reflection (date-only title) so BFS must traverse through it
        TIO.writeFile (reflDir </> "2020-01-01.md")
          ("---\ntitle: \"2020-01-01\"\n---\n" <>
           "About [[topics/private-topic]]\n" <>
           T.replicate 60 "x")
        TIO.writeFile (topicsDir </> "private-topic.md")
          ("---\ntitle: Private Topic\nno_social: true\n---\n" <>
           "See also [[books/public-book]]\n" <>
           T.replicate 60 "x")
        TIO.writeFile (booksDir </> "public-book.md")
          ("---\ntitle: Public Book\nURL: https://example.com/books/public-book\n---\n" <>
           "![[attachments/books-public-book.jpg]]\n" <>
           T.replicate 60 "x")
        let config = FindContentConfig dir [Twitter] (TimeOfDay 0 0 0) Nothing
        result <- bfsContentDiscovery config
        let resultPaths = fmap (cnRelativePath . ctpNote) result
        assertBool "should not post private topic"
          (all (\p -> p /= testRelativePath "topics/private-topic.md") resultPaths)
        assertBool "should find public book through private topic"
          (any (\p -> p == testRelativePath "books/public-book.md") resultPaths)

  , testCase "BFS traverses through short-body content to reach postable content" $ do
      withSystemTempDirectory "social-test" $ \dir -> do
        let reflDir = dir </> "reflections"
            booksDir = dir </> "books"
        createDirectoryIfMissing True reflDir
        createDirectoryIfMissing True booksDir
        -- Untitled reflection (date-only title) so BFS must traverse through it
        TIO.writeFile (reflDir </> "2020-01-01.md")
          ("---\ntitle: \"2020-01-01\"\n---\n" <>
           "See [[books/stub]]\n" <>
           T.replicate 60 "x")
        TIO.writeFile (booksDir </> "stub.md")
          ("---\ntitle: Stub Note\n---\n" <>
           "Short.\nSee [[books/real-book]]\n")
        TIO.writeFile (booksDir </> "real-book.md")
          ("---\ntitle: Real Book\nURL: https://example.com/books/real-book\n---\n" <>
           "![[attachments/books-real-book.jpg]]\n" <>
           T.replicate 60 "x")
        let config = FindContentConfig dir [Twitter] (TimeOfDay 0 0 0) Nothing
        result <- bfsContentDiscovery config
        let resultPaths = fmap (cnRelativePath . ctpNote) result
        assertBool "should not post stub"
          (all (\p -> p /= testRelativePath "books/stub.md") resultPaths)
        assertBool "should find real book through stub"
          (any (\p -> p == testRelativePath "books/real-book.md") resultPaths)
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
            assertEqual "title" (testTitle "My Book") (cnTitle note)
            assertEqual "url" (testUrl "https://example.com/books/my-book") (cnUrl note)

  , testCase "bfsContentDiscovery with empty dir returns empty" $ do
      withSystemTempDirectory "social-test" $ \dir -> do
        let config = FindContentConfig dir [Twitter, Bluesky] (TimeOfDay 17 0 0) Nothing
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
           "![[attachments/books-great-book.jpg]]\n" <>
           T.replicate 60 "x")
        let config = FindContentConfig dir [Twitter, Bluesky, Mastodon] (TimeOfDay 0 0 0) Nothing
        result <- bfsContentDiscovery config
        assertBool "should find content to post" (not (null result))
  ]

--------------------------------------------------------------------------------
-- URL validation
--------------------------------------------------------------------------------

urlValidationTests :: TestTree
urlValidationTests = testGroup "URL validation"
  [ testCase "urlFromFilePath derives correct URL from relative path" $
      assertEqual "" "https://bagrounds.org/books/my-book"
        (urlFromFilePath "books/my-book.md")

  , testCase "urlFromFilePath handles nested paths" $
      assertEqual "" "https://bagrounds.org/reflections/2025-01-15"
        (urlFromFilePath "reflections/2025-01-15.md")

  , testCase "urlFromFilePath handles path without .md extension" $
      assertEqual "" "https://bagrounds.org/books/my-book"
        (urlFromFilePath "books/my-book")

  , testCase "validateNoteUrl passes through when URL is live" $ do
      let alwaysLive _ = pure True
          note = mkNote "books/my-book.md" "My Book" (T.replicate 60 "x")
      result <- validateNoteUrl alwaysLive note
      case result of
        Nothing -> assertBool "should pass when URL is live" False
        Just n  -> assertEqual "url unchanged" (cnUrl note) (cnUrl n)

  , testCase "validateNoteUrl returns Nothing when URL is dead and matches file path" $ do
      let alwaysDead _ = pure False
          note = (mkNote "books/my-book.md" "My Book" (T.replicate 60 "x"))
            { cnUrl = testUrl "https://bagrounds.org/books/my-book" }
      result <- validateNoteUrl alwaysDead note
      assertEqual "should return Nothing for dead URL" Nothing result

  , testCase "validateNoteUrl fixes stale frontmatter URL when file-path URL is live" $ do
      withSystemTempDirectory "url-test" $ \dir -> do
        let booksDir = dir </> "books"
        createDirectoryIfMissing True booksDir
        TIO.writeFile (booksDir </> "renamed-book.md")
          "---\ntitle: My Book\nURL: \"https://bagrounds.org/books/old-name\"\n---\nContent here."
        let checker url = pure (url == "https://bagrounds.org/books/renamed-book")
            note = ContentNote
              { cnFilePath = booksDir </> "renamed-book.md"
              , cnRelativePath = testRelativePath "books/renamed-book.md"
              , cnTitle = testTitle "My Book"
              , cnUrl = testUrl "https://bagrounds.org/books/old-name"
              , cnBody = T.replicate 60 "x"
              , cnPostedPlatforms = Set.empty
              , cnLinkedNotePaths = []
              , cnNoSocial = False
              }
        result <- validateNoteUrl checker note
        case result of
          Nothing -> assertBool "should return fixed note" False
          Just n  -> assertEqual "url should be updated"
            (testUrl "https://bagrounds.org/books/renamed-book") (cnUrl n)
        -- Verify the file was updated
        updatedContent <- TIO.readFile (booksDir </> "renamed-book.md")
        assertBool "file should contain new URL"
          (T.isInfixOf "https://bagrounds.org/books/renamed-book" updatedContent)

  , testCase "validateNoteUrl returns Nothing when both URLs are dead" $ do
      let alwaysDead _ = pure False
          note = (mkNote "books/my-book.md" "My Book" (T.replicate 60 "x"))
            { cnUrl = testUrl "https://bagrounds.org/books/old-name"
            , cnFilePath = "/nonexistent/books/my-book.md"
            }
      result <- validateNoteUrl alwaysDead note
      assertEqual "should return Nothing for both dead URLs" Nothing result

  , testCase "BFS skips notes with dead URLs but still follows links" $ do
      withSystemTempDirectory "url-test" $ \dir -> do
        let reflDir = dir </> "reflections"
            booksDir = dir </> "books"
        createDirectoryIfMissing True reflDir
        createDirectoryIfMissing True booksDir
        TIO.writeFile (reflDir </> "2020-01-01.md")
          ("---\ntitle: \"2020-01-01\"\n---\n" <>
           "See [[books/dead-link]]\n" <>
           T.replicate 60 "x")
        TIO.writeFile (booksDir </> "dead-link.md")
          ("---\ntitle: Dead Link Book\nURL: \"https://bagrounds.org/books/dead-link\"\n---\n" <>
           "![[attachments/books-dead-link.jpg]]\n" <>
           "Read [[books/live-book]]\n" <>
           T.replicate 60 "x")
        TIO.writeFile (booksDir </> "live-book.md")
          ("---\ntitle: Live Book\nURL: \"https://bagrounds.org/books/live-book\"\n---\n" <>
           "![[attachments/books-live-book.jpg]]\n" <>
           T.replicate 60 "x")
        let checker url = pure (url == "https://bagrounds.org/books/live-book")
            config = FindContentConfig dir [Twitter] (TimeOfDay 0 0 0) (Just checker)
        result <- bfsContentDiscovery config
        let resultPaths = fmap (cnRelativePath . ctpNote) result
        assertBool "should not include dead-link book"
          (all (\p -> p /= testRelativePath "books/dead-link.md") resultPaths)
        assertBool "should find live book through dead-link book"
          (any (\p -> p == testRelativePath "books/live-book.md") resultPaths)

  , testCase "updateFrontmatterUrl updates existing URL field" $ do
      withSystemTempDirectory "url-test" $ \dir -> do
        let notePath = dir </> "test-note.md"
        TIO.writeFile notePath
          "---\ntitle: Test Note\nURL: \"https://bagrounds.org/old-path\"\n---\nBody content"
        updateFrontmatterUrl notePath "https://bagrounds.org/new-path"
        content <- TIO.readFile notePath
        assertBool "should contain new URL"
          (T.isInfixOf "https://bagrounds.org/new-path" content)
        assertBool "should not contain old URL"
          (not (T.isInfixOf "https://bagrounds.org/old-path" content))

  , testCase "updateFrontmatterUrl adds URL field when missing" $ do
      withSystemTempDirectory "url-test" $ \dir -> do
        let notePath = dir </> "no-url-note.md"
        TIO.writeFile notePath
          "---\ntitle: No URL Note\n---\nBody content"
        updateFrontmatterUrl notePath "https://bagrounds.org/new-url"
        content <- TIO.readFile notePath
        assertBool "should contain added URL"
          (T.isInfixOf "https://bagrounds.org/new-url" content)
  ]

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

mkNote :: Text -> Text -> Text -> ContentNote
mkNote relPath title body = ContentNote
  { cnFilePath = T.unpack relPath
  , cnRelativePath = testRelativePath relPath
  , cnTitle = testTitle title
  , cnUrl = testUrl ("https://example.com/" <> relPath)
  , cnBody = body
  , cnPostedPlatforms = Set.empty
  , cnLinkedNotePaths = []
  , cnNoSocial = False
  }

--------------------------------------------------------------------------------
-- selectMostRecentReflection
--------------------------------------------------------------------------------

selectMostRecentReflectionTests :: TestTree
selectMostRecentReflectionTests = testGroup "selectMostRecentReflection"
  [ testCase "returns Nothing for empty list" $
      assertEqual "" Nothing (selectMostRecentReflection [])

  , testCase "returns Nothing when no date files" $
      assertEqual "" Nothing
        (selectMostRecentReflection ["readme.md", "index.md", "notes.txt"])

  , testCase "selects the most recent date file" $
      assertEqual "" (Just "reflections/2025-01-15.md")
        (selectMostRecentReflection ["2025-01-01.md", "2025-01-15.md", "2025-01-10.md"])

  , testCase "ignores non-date filenames" $
      assertEqual "" (Just "reflections/2025-03-20.md")
        (selectMostRecentReflection ["index.md", "2025-03-20.md", "notes.txt"])

  , testCase "handles single date file" $
      assertEqual "" (Just "reflections/2026-04-08.md")
        (selectMostRecentReflection ["2026-04-08.md"])

  , testCase "ignores date files without .md extension" $
      assertEqual "" (Just "reflections/2025-06-15.md")
        (selectMostRecentReflection ["2025-01-01.txt", "2025-06-15.md"])
  ]

--------------------------------------------------------------------------------
-- SocialPost smart constructor tests
--------------------------------------------------------------------------------

socialPostTests :: TestTree
socialPostTests = testGroup "SocialPost"
  [ testCase "mkTweet accepts text under 280 chars" $
      case mkTweet "Hello, world!" of
        Right (Tweet content) -> assertEqual "" "Hello, world!" content
        Left err -> assertBool ("unexpected rejection: " <> T.unpack err) False

  , testCase "mkTweet rejects text over 280 chars" $
      let longText = T.replicate 281 "a"
      in case mkTweet longText of
        Left _ -> pure ()
        Right _ -> assertBool "expected rejection for 281 chars" False

  , testCase "mkBlueskyPost accepts text under 300 chars" $
      case mkBlueskyPost "Hello from Bluesky!" of
        Right (BlueskyPost content) -> assertEqual "" "Hello from Bluesky!" content
        Left err -> assertBool ("unexpected rejection: " <> T.unpack err) False

  , testCase "mkBlueskyPost rejects text over 300 chars" $
      let longText = T.replicate 301 "b"
      in case mkBlueskyPost longText of
        Left _ -> pure ()
        Right _ -> assertBool "expected rejection for 301 chars" False

  , testCase "mkMastodonPost accepts text under 500 chars" $
      case mkMastodonPost "Hello from Mastodon!" of
        Right (MastodonPost content) -> assertEqual "" "Hello from Mastodon!" content
        Left err -> assertBool ("unexpected rejection: " <> T.unpack err) False

  , testCase "mkMastodonPost rejects text over 500 chars" $
      let longText = T.replicate 501 "c"
      in case mkMastodonPost longText of
        Left _ -> pure ()
        Right _ -> assertBool "expected rejection for 501 chars" False

  , testCase "socialPostContent extracts text from Tweet" $
      assertEqual "" "hello" (socialPostContent (Tweet "hello"))

  , testCase "socialPostContent extracts text from BlueskyPost" $
      assertEqual "" "sky" (socialPostContent (BlueskyPost "sky"))

  , testCase "socialPostContent extracts text from MastodonPost" $
      assertEqual "" "toot" (socialPostContent (MastodonPost "toot"))

  , testCase "socialPostPlatform returns correct platform" $ do
      assertEqual "Tweet" Twitter (socialPostPlatform (Tweet "x"))
      assertEqual "BlueskyPost" Bluesky (socialPostPlatform (BlueskyPost "x"))
      assertEqual "MastodonPost" Mastodon (socialPostPlatform (MastodonPost "x"))

  , testCase "mkSocialPost dispatches to correct constructor" $ do
      assertEqual "Twitter" (Right (Tweet "hi")) (mkSocialPost Twitter "hi")
      assertEqual "Bluesky" (Right (BlueskyPost "hi")) (mkSocialPost Bluesky "hi")
      assertEqual "Mastodon" (Right (MastodonPost "hi")) (mkSocialPost Mastodon "hi")

  , testProperty "mkSocialPost always succeeds for text under minimum platform limit" $
      QC.forAll (QC.elements [Twitter, Bluesky, Mastodon]) $ \platform ->
        QC.forAll (QC.choose (0, 279)) $ \len ->
          let text = T.replicate len "x"
          in case mkSocialPost platform text of
            Right _ -> True
            Left _ -> False

  , testProperty "socialPostContent returns original text for valid inputs" $
      QC.forAll (QC.elements [Twitter, Bluesky, Mastodon]) $ \platform ->
        QC.forAll (QC.choose (0, 50)) $ \len ->
          let text = T.replicate len "a"
          in case mkSocialPost platform text of
            Right post -> socialPostContent post == text
            Left _ -> False
  ]

-- --------------------------------------------------------------------------
-- readContentNote
-- --------------------------------------------------------------------------

readContentNoteTests :: TestTree
readContentNoteTests = testGroup "readContentNote"
  [ testCase "returns Nothing for empty relative path" $
      withSystemTempDirectory "social-posting-test" $ \tmpDir -> do
        result <- readContentNote "" tmpDir
        result @?= Nothing

  , testCase "returns Nothing for nonexistent file" $
      withSystemTempDirectory "social-posting-test" $ \tmpDir -> do
        result <- readContentNote "nonexistent/file.md" tmpDir
        result @?= Nothing

  , testCase "returns Nothing for whitespace-only title" $
      withSystemTempDirectory "social-posting-test" $ \tmpDir -> do
        let relativePath = "books/test-book.md"
            filePath = tmpDir </> "books" </> "test-book.md"
            content = T.unlines
              [ "---"
              , "title: \"  \""
              , "URL: https://bagrounds.org/books/test-book"
              , "---"
              , "This is a sufficiently long body of text for content note testing purposes."
              ]
        createDirectoryIfMissing True (tmpDir </> "books")
        TIO.writeFile filePath content
        result <- readContentNote relativePath tmpDir
        result @?= Nothing

  , testCase "succeeds with valid content note" $
      withSystemTempDirectory "social-posting-test" $ \tmpDir -> do
        let relativePath = "books/valid-book.md"
            filePath = tmpDir </> "books" </> "valid-book.md"
            content = T.unlines
              [ "---"
              , "title: \"A Valid Book Title\""
              , "URL: https://bagrounds.org/books/valid-book"
              , "---"
              , "This book has enough content to be a valid note for social posting."
              ]
        createDirectoryIfMissing True (tmpDir </> "books")
        TIO.writeFile filePath content
        result <- readContentNote relativePath tmpDir
        assertBool "should return Just for valid content note" $ result /= Nothing
  ]

