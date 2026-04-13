module Automation.SocialPosting.ContentDiscoveryTest (tests) where

import qualified Data.Set as Set
import qualified Data.Text as T
import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Data.Time.LocalTime (TimeOfDay (..))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertEqual, assertBool, testCase, (@?=))
import Test.Tasty.QuickCheck (testProperty)
import qualified Test.Tasty.QuickCheck as QC

import Automation.BlogImage.ContentDirectory (ContentDirectory (..))
import Automation.BlogSeriesConfig (imageBackfillContentDirsFrom)
import Automation.Platform (Platform (..))
import Automation.SocialPosting.ContentDiscovery

defaultContentDirs :: [ContentDirectory]
defaultContentDirs = imageBackfillContentDirsFrom []

now :: UTCTime
now = mkUTC 2026 4 10 12

tests :: TestTree
tests = testGroup "SocialPosting.ContentDiscovery"
  [ platformDetectionTests
  , contentFilterTests
  , reflectionEligibilityTests
  , bfsEligibilityTests
  , urlFromFilePathTests
  , imageBackfillTests
  , imageDateTests
  ]


platformDetectionTests :: TestTree
platformDetectionTests = testGroup "detectPostedPlatforms"
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


contentFilterTests :: TestTree
contentFilterTests = testGroup "content filtering"
  [ testCase "isIndexPath detects index.md" $
      assertBool "index.md is an index path" $
        isIndexPath "books/index.md"

  , testCase "isIndexPath detects root index.md" $
      assertBool "index.md is an index path" $
        isIndexPath "index.md"

  , testCase "isIndexPath rejects non-index files" $
      assertBool "book file is not an index path" $
        not (isIndexPath "books/great-book.md")

  , testCase "isAwaitingImageBackfill detects note without image in backfill directory" $
      assertBool "should be awaiting image" $
        isAwaitingImageBackfill defaultContentDirs now "books/great-book.md" "Some text about a great book" Nothing

  , testCase "isAwaitingImageBackfill rejects note with old image" $
      assertBool "has image from long ago, should not be awaiting" $
        not (isAwaitingImageBackfill defaultContentDirs now "books/great-book.md"
          "![[attachments/books-great-book.jpg]]\nSome text about a great book"
          (Just (mkUTC 2026 4 1 12)))
  ]


reflectionEligibilityTests :: TestTree
reflectionEligibilityTests = testGroup "isReflectionEligibleForPosting"
  [ testCase "very old reflection is eligible" $
      let testNow = mkUTC 2026 3 15 12
      in assertBool "old reflection should be eligible"
           (isReflectionEligibleForPosting testNow (TimeOfDay 17 0 0) (fromGregorian 2020 1 1))

  , testCase "yesterday's reflection is eligible after posting cutoff" $
      let testNow = mkUTC 2026 3 15 18
      in assertBool "yesterday at hour 18 with posting cutoff 17:00"
           (isReflectionEligibleForPosting testNow (TimeOfDay 17 0 0) (fromGregorian 2026 3 14))

  , testCase "yesterday's reflection is ineligible before posting cutoff" $
      let testNow = mkUTC 2026 3 15 10
      in assertBool "yesterday at hour 10 with posting cutoff 17:00"
           (not (isReflectionEligibleForPosting testNow (TimeOfDay 17 0 0) (fromGregorian 2026 3 14)))

  , testCase "today's reflection is never eligible" $
      let testNow = mkUTC 2026 3 15 23
      in assertBool "today's reflection should not be eligible"
           (not (isReflectionEligibleForPosting testNow (TimeOfDay 17 0 0) (fromGregorian 2026 3 15)))

  , testProperty "reflections older than 2 days are always eligible" $
      QC.forAll (QC.choose (2, 365)) $ \daysAgo ->
        let testNow = mkUTC 2026 6 15 12
            reflDate = fromGregorian 2026 6 (15 - daysAgo)
        in isReflectionEligibleForPosting testNow (TimeOfDay 17 0 0) reflDate
  ]

mkUTC :: Integer -> Int -> Int -> Int -> UTCTime
mkUTC year month day hour =
  UTCTime (fromGregorian year month day)
          (secondsToDiffTime (fromIntegral hour * 3600))


bfsEligibilityTests :: TestTree
bfsEligibilityTests = testGroup "checkBfsEligibility"
  [ testCase "non-reflection paths are always eligible" $ do
      result <- checkBfsEligibility "books/great-book.md" (TimeOfDay 17 0 0)
      assertBool "book should be eligible" result

  , testCase "non-reflection in topics dir is eligible" $ do
      result <- checkBfsEligibility "topics/machine-learning.md" (TimeOfDay 17 0 0)
      assertBool "topic should be eligible" result

  , testCase "index paths are never eligible" $ do
      result <- checkBfsEligibility "books/index.md" (TimeOfDay 17 0 0)
      assertBool "index should not be eligible" (not result)

  , testCase "old reflection is eligible" $ do
      result <- checkBfsEligibility "reflections/2020-01-01.md" (TimeOfDay 17 0 0)
      assertBool "old reflection should be eligible" result
  ]


urlFromFilePathTests :: TestTree
urlFromFilePathTests = testGroup "urlFromFilePath"
  [ testCase "derives correct URL from relative path" $
      assertEqual "" "https://bagrounds.org/books/my-book"
        (urlFromFilePath "books/my-book.md")

  , testCase "handles nested paths" $
      assertEqual "" "https://bagrounds.org/reflections/2025-01-15"
        (urlFromFilePath "reflections/2025-01-15.md")

  , testCase "handles path without .md extension" $
      assertEqual "" "https://bagrounds.org/books/my-book"
        (urlFromFilePath "books/my-book")

  , testProperty "always starts with https://bagrounds.org/" $
      \(QC.ASCIIString s) ->
        T.isPrefixOf "https://bagrounds.org/" (urlFromFilePath (T.pack s))
  ]


imageBackfillTests :: TestTree
imageBackfillTests = testGroup "isAwaitingImageBackfill"
  [ testCase "note without image in backfill directory is awaiting" $
      assertBool "should be awaiting image" $
        isAwaitingImageBackfill defaultContentDirs now "books/great-book.md" "Some text about a great book" Nothing

  , testCase "note with embedded image and old date is not awaiting" $
      assertBool "has image, should not be awaiting" $
        not (isAwaitingImageBackfill defaultContentDirs now "books/great-book.md"
          "![[attachments/books-great-book.jpg]]\nSome text about a great book"
          (Just (mkUTC 2026 4 1 12)))

  , testCase "excluded file is not awaiting" $
      assertBool "index.md should not be awaiting" $
        not (isAwaitingImageBackfill defaultContentDirs now "books/index.md" "Browse all books" Nothing)

  , testCase "file not in any content directory is not awaiting" $
      assertBool "unknown directory should not be awaiting" $
        not (isAwaitingImageBackfill defaultContentDirs now "people/john-doe.md" "A person page" Nothing)
  ]


imageDateTests :: TestTree
imageDateTests = testGroup "image date propagation delay"
  [ testCase "parseImageDate parses ISO 8601 timestamp" $
      parseImageDate "2026-04-10T12:00:00Z" @?= Just (mkUTC 2026 4 10 12)

  , testCase "parseImageDate parses timestamp with timezone offset" $
      parseImageDate "2026-04-10T12:00:00+0000" @?= Just (mkUTC 2026 4 10 12)

  , testCase "parseImageDate returns Nothing for invalid input" $
      parseImageDate "not-a-date" @?= Nothing

  , testCase "isRecentlyBackfilled returns True for same-day image" $
      assertBool "image generated 1 hour ago is recent" $
        isRecentlyBackfilled now (Just (mkUTC 2026 4 10 11))

  , testCase "isRecentlyBackfilled returns False for old image" $
      assertBool "image from a week ago is not recent" $
        not (isRecentlyBackfilled now (Just (mkUTC 2026 4 3 12)))

  , testCase "isRecentlyBackfilled returns False for no image date" $
      assertBool "no image date means not recently backfilled" $
        not (isRecentlyBackfilled now Nothing)

  , testCase "note with image generated 1 hour ago is still awaiting" $
      assertBool "recently generated image should defer posting" $
        isAwaitingImageBackfill defaultContentDirs now "books/great-book.md"
          "![[attachments/books-great-book.jpg]]\nSome text about a great book"
          (Just (mkUTC 2026 4 10 11))

  , testCase "note with image generated 2 days ago is not awaiting" $
      assertBool "image from 2 days ago should be propagated" $
        not (isAwaitingImageBackfill defaultContentDirs now "books/great-book.md"
          "![[attachments/books-great-book.jpg]]\nSome text about a great book"
          (Just (mkUTC 2026 4 8 12)))
  ]
