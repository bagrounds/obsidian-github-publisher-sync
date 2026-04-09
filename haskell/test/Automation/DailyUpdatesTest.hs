module Automation.DailyUpdatesTest (tests) where

import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertEqual, assertBool, testCase)
import Test.Tasty.QuickCheck (testProperty)
import qualified Test.Tasty.QuickCheck as QC

import Automation.DailyUpdates
import Automation.Types (RelativePath (..), Title (..))

tests :: TestTree
tests = testGroup "DailyUpdates"
  [ addUpdateLinksTests
  , addUpdateLinksToReflectionTests
  ]

--------------------------------------------------------------------------------
-- addUpdateLinks (pure function)
--------------------------------------------------------------------------------

addUpdateLinksTests :: TestTree
addUpdateLinksTests = testGroup "addUpdateLinks"
  [ testCase "creates new section with page and details when no updates section exists" $
      let content = "# My Reflection\n\nSome content here"
          result = addUpdateLinks content
                     [UpdateLink (RelativePath "ai-blog/2026-03-28-post.md") (Title "Post Title") ["🖼️ added image"]]
      in do
        assertBool "should contain updates header"
          (T.isInfixOf "## 🔄 Updates" result)
        assertBool "should contain the page link"
          (T.isInfixOf "[[ai-blog/2026-03-28-post|Post Title]]" result)
        assertBool "should contain the detail"
          (T.isInfixOf "  - 🖼️ added image" result)

  , testCase "adds new page when updates section exists but page missing" $
      let content = "# My Reflection\n\n## 🔄 Updates\n- [[page1|Page 1]]\n  - 🖼️ added image\n"
          result = addUpdateLinks content
                     [UpdateLink (RelativePath "ai-blog/cool-post.md") (Title "Cool Post") ["🦋 posted to BlueSky"]]
      in do
        assertBool "should preserve existing page"
          (T.isInfixOf "[[page1|Page 1]]" result)
        assertBool "should contain the new page"
          (T.isInfixOf "[[ai-blog/cool-post|Cool Post]]" result)
        assertBool "should contain the new detail"
          (T.isInfixOf "  - 🦋 posted to BlueSky" result)

  , testCase "inserts details into existing page entry" $
      let content = "# My Reflection\n\n## 🔄 Updates\n- [[page1|Page 1]]\n  - 🖼️ added image\n"
          result = addUpdateLinks content
                     [UpdateLink (RelativePath "page1.md") (Title "Page 1") ["🦋 posted to BlueSky"]]
      in do
        assertBool "should contain both details"
          (T.isInfixOf "  - 🖼️ added image" result && T.isInfixOf "  - 🦋 posted to BlueSky" result)

  , testCase "skips duplicate details" $
      let content = "# My Reflection\n\n## 🔄 Updates\n- [[page1|Page 1]]\n  - 🖼️ added image\n"
          result = addUpdateLinks content
                     [UpdateLink (RelativePath "page1.md") (Title "Page 1") ["🖼️ added image"]]
      in assertEqual "should not change content" content result

  , testCase "returns content unchanged for empty links" $
      let content = "# My Reflection\n\nSome content"
          result = addUpdateLinks content []
      in assertEqual "should not change" content result

  , testCase "multiple pages in same content" $
      let content0 = "# My Reflection\n\nSome content"
          content1 = addUpdateLinks content0
                       [UpdateLink (RelativePath "img-page.md") (Title "Image Page") ["🖼️ added image"]]
          content2 = addUpdateLinks content1
                       [UpdateLink (RelativePath "social-page.md") (Title "Social Page") ["🦋 posted to BlueSky"]]
          content3 = addUpdateLinks content2
                       [UpdateLink (RelativePath "link-page.md") (Title "Link Page") ["🔗 added 3 internal links"]]
      in do
        assertBool "has image page" (T.isInfixOf "[[img-page|Image Page]]" content3)
        assertBool "has social page" (T.isInfixOf "[[social-page|Social Page]]" content3)
        assertBool "has link page" (T.isInfixOf "[[link-page|Link Page]]" content3)
        assertBool "has image detail" (T.isInfixOf "  - 🖼️ added image" content3)
        assertBool "has social detail" (T.isInfixOf "  - 🦋 posted to BlueSky" content3)
        assertBool "has link detail" (T.isInfixOf "  - 🔗 added 3 internal links" content3)

  , testCase "preserves content after updates section" $
      let content = "# My Reflection\n\n## 🔄 Updates\n- [[p1|P1]]\n  - 🖼️ added image\n\n## 📚 Books\n\nSome books"
          result = addUpdateLinks content
                     [UpdateLink (RelativePath "sp.md") (Title "SP") ["🦋 posted to BlueSky"]]
      in do
        assertBool "should preserve books section"
          (T.isInfixOf "## 📚 Books" result)
        assertBool "should preserve books content"
          (T.isInfixOf "Some books" result)
        assertBool "should add social page"
          (T.isInfixOf "[[sp|SP]]" result)

  , testCase "adds multiple details at once for a single page" $
      let content = "# Reflection"
          result = addUpdateLinks content
                     [UpdateLink (RelativePath "a.md") (Title "Page A") ["🦋 posted to BlueSky", "🐘 posted to Mastodon"]]
      in do
        assertBool "has page" (T.isInfixOf "[[a|Page A]]" result)
        assertBool "has bluesky detail" (T.isInfixOf "  - 🦋 posted to BlueSky" result)
        assertBool "has mastodon detail" (T.isInfixOf "  - 🐘 posted to Mastodon" result)

  , testCase "adds multiple pages at once" $
      let content = "# Reflection"
          result = addUpdateLinks content
                     [ UpdateLink (RelativePath "a.md") (Title "Page A") ["🖼️ added image"]
                     , UpdateLink (RelativePath "b.md") (Title "Page B") ["🦋 posted to BlueSky"]
                     , UpdateLink (RelativePath "c.md") (Title "Page C") ["🔗 added 2 internal links"]
                     ]
      in do
        assertBool "has A" (T.isInfixOf "[[a|Page A]]" result)
        assertBool "has B" (T.isInfixOf "[[b|Page B]]" result)
        assertBool "has C" (T.isInfixOf "[[c|Page C]]" result)

  , testCase "inserts updates section before social media sections" $
      let content = "# My Reflection\n\nBody text\n\n## 🐦 Tweet\n\nTweet embed"
          result = addUpdateLinks content
                     [UpdateLink (RelativePath "img.md") (Title "Image Page") ["🖼️ added image"]]
      in do
        assertBool "has updates header" (T.isInfixOf "## 🔄 Updates" result)
        assertBool "has page link" (T.isInfixOf "[[img|Image Page]]" result)
        assertBool "updates before tweet" $
          let uIdx = T.length $ fst $ T.breakOn "## 🔄 Updates" result
              tIdx = T.length $ fst $ T.breakOn "## 🐦 Tweet" result
          in uIdx < tIdx

  , testCase "inserts updates section before bluesky section" $
      let content = "# My Reflection\n\nBody text\n\n## 🦋 Bluesky\n\nBluesky embed"
          result = addUpdateLinks content
                     [UpdateLink (RelativePath "img.md") (Title "Image Page") ["🖼️ added image"]]
      in assertBool "updates before bluesky" $
          let uIdx = T.length $ fst $ T.breakOn "## 🔄 Updates" result
              bIdx = T.length $ fst $ T.breakOn "## 🦋 Bluesky" result
          in uIdx < bIdx

  , testCase "incremental updates from different operations accumulate under same page" $
      let content0 = "# My Reflection\n\nSome content"
          content1 = addUpdateLinks content0
                       [UpdateLink (RelativePath "page1.md") (Title "Page 1") ["🖼️ added image"]]
          content2 = addUpdateLinks content1
                       [UpdateLink (RelativePath "page1.md") (Title "Page 1") ["🦋 posted to BlueSky"]]
          content3 = addUpdateLinks content2
                       [UpdateLink (RelativePath "page1.md") (Title "Page 1") ["🔗 added 2 internal links"]]
      in do
        assertBool "one page link" (T.isInfixOf "[[page1|Page 1]]" content3)
        assertBool "has image detail" (T.isInfixOf "  - 🖼️ added image" content3)
        assertBool "has bluesky detail" (T.isInfixOf "  - 🦋 posted to BlueSky" content3)
        assertBool "has link detail" (T.isInfixOf "  - 🔗 added 2 internal links" content3)
        -- Only one page link entry (the second occurrence would be duplicate text)
        let pageOccurrences = length $ T.splitOn "- [[page1|Page 1]]" content3
        assertEqual "should have exactly one page entry" 2 pageOccurrences

  , testCase "details appear as indented sub-bullets under page link" $
      let content = "# Reflection"
          result = addUpdateLinks content
                     [UpdateLink (RelativePath "page.md") (Title "My Page") ["🖼️ added image", "🦋 posted to BlueSky"]]
          resultLines = T.splitOn "\n" result
          matchingLines = filter (T.isInfixOf "[[page|My Page]]") resultLines
      in case matchingLines of
        (pageLine : _) -> do
          let pageIdx = length $ takeWhile (/= pageLine) resultLines
              detailLine1 = safeAt resultLines (pageIdx + 1)
              detailLine2 = safeAt resultLines (pageIdx + 2)
          assertBool "page line starts with dash" (T.isPrefixOf "- [[" pageLine)
          assertEqual "first detail" (Just "  - 🖼️ added image") detailLine1
          assertEqual "second detail" (Just "  - 🦋 posted to BlueSky") detailLine2
        [] -> assertBool "page link should be present" False

  , testCase "same detail under different pages is not deduplicated across pages" $
      let content = "# Reflection"
          result = addUpdateLinks content
                     [ UpdateLink (RelativePath "page-a.md") (Title "Page A") ["🖼️ added image"]
                     , UpdateLink (RelativePath "page-b.md") (Title "Page B") ["🖼️ added image"]
                     ]
      in do
        assertBool "has page A" (T.isInfixOf "[[page-a|Page A]]" result)
        assertBool "has page B" (T.isInfixOf "[[page-b|Page B]]" result)
        let linesWithDetail = filter (== "  - 🖼️ added image") (T.splitOn "\n" result)
        assertEqual "should have two image details (one per page)" 2 (length linesWithDetail)

  , testCase "same detail under different pages works incrementally" $
      let content0 = "# Reflection"
          content1 = addUpdateLinks content0
                       [UpdateLink (RelativePath "page-a.md") (Title "Page A") ["🖼️ added image"]]
          content2 = addUpdateLinks content1
                       [UpdateLink (RelativePath "page-b.md") (Title "Page B") ["🖼️ added image"]]
      in do
        assertBool "has page A" (T.isInfixOf "[[page-a|Page A]]" content2)
        assertBool "has page B" (T.isInfixOf "[[page-b|Page B]]" content2)
        let linesWithDetail = filter (== "  - 🖼️ added image") (T.splitOn "\n" content2)
        assertEqual "should have two image details (one per page)" 2 (length linesWithDetail)

  , testProperty "addUpdateLinks never removes existing lines" $
      \(QC.ASCIIString bodyStr) ->
        let body = T.pack bodyStr
            content = "# Reflection\n\n" <> body <> "\n\nSome footer"
            result = addUpdateLinks content
                       [UpdateLink (RelativePath "test.md") (Title "Test") ["🖼️ added image"]]
        in T.isInfixOf "Some footer" result
  ]

safeAt :: [a] -> Int -> Maybe a
safeAt xs i
  | i >= 0 && i < length xs = Just (xs !! i)
  | otherwise = Nothing

--------------------------------------------------------------------------------
-- addUpdateLinksToReflection (IO function)
--------------------------------------------------------------------------------

addUpdateLinksToReflectionTests :: TestTree
addUpdateLinksToReflectionTests = testGroup "addUpdateLinksToReflection"
  [ testCase "creates reflection and adds page with details" $
      withSystemTempDirectory "daily-updates-test" $ \tmpDir -> do
        let reflDir = tmpDir </> "reflections"
        createDirectoryIfMissing True reflDir

        TIO.writeFile (reflDir </> "2026-03-28.md") "---\ntitle: 2026-03-28\n---\n\n# Reflection\n"

        modified <- addUpdateLinksToReflection reflDir "2026-03-28"
                      [UpdateLink (RelativePath "ai-blog/post.md") (Title "A Post") ["🖼️ added image"]]
        assertBool "should report modification" modified

        content <- TIO.readFile (reflDir </> "2026-03-28.md")
        assertBool "has updates header" (T.isInfixOf "## 🔄 Updates" content)
        assertBool "has page link" (T.isInfixOf "[[ai-blog/post|A Post]]" content)
        assertBool "has detail" (T.isInfixOf "  - 🖼️ added image" content)

  , testCase "returns false when details already present" $
      withSystemTempDirectory "daily-updates-test" $ \tmpDir -> do
        let reflDir = tmpDir </> "reflections"
        createDirectoryIfMissing True reflDir

        TIO.writeFile (reflDir </> "2026-03-28.md") $
          "---\ntitle: 2026-03-28\n---\n\n## 🔄 Updates\n- [[ai-blog/post|A Post]]\n  - 🖼️ added image\n"

        modified <- addUpdateLinksToReflection reflDir "2026-03-28"
                      [UpdateLink (RelativePath "ai-blog/post.md") (Title "A Post") ["🖼️ added image"]]
        assertBool "should report no modification" (not modified)

  , testCase "returns false for empty links" $
      withSystemTempDirectory "daily-updates-test" $ \tmpDir -> do
        let reflDir = tmpDir </> "reflections"
        createDirectoryIfMissing True reflDir

        modified <- addUpdateLinksToReflection reflDir "2026-03-28" []
        assertBool "should report no modification" (not modified)

  , testCase "different operations accumulate details under same page" $
      withSystemTempDirectory "daily-updates-test" $ \tmpDir -> do
        let reflDir = tmpDir </> "reflections"
        createDirectoryIfMissing True reflDir

        TIO.writeFile (reflDir </> "2026-03-28.md") "---\ntitle: 2026-03-28\n---\n\n# Reflection\n"

        _ <- addUpdateLinksToReflection reflDir "2026-03-28"
               [UpdateLink (RelativePath "page.md") (Title "My Page") ["🖼️ added image"]]
        _ <- addUpdateLinksToReflection reflDir "2026-03-28"
               [UpdateLink (RelativePath "page.md") (Title "My Page") ["🦋 posted to BlueSky"]]

        content <- TIO.readFile (reflDir </> "2026-03-28.md")
        assertBool "has page link" (T.isInfixOf "[[page|My Page]]" content)
        assertBool "has image detail" (T.isInfixOf "  - 🖼️ added image" content)
        assertBool "has bluesky detail" (T.isInfixOf "  - 🦋 posted to BlueSky" content)

  , testCase "different pages create separate entries" $
      withSystemTempDirectory "daily-updates-test" $ \tmpDir -> do
        let reflDir = tmpDir </> "reflections"
        createDirectoryIfMissing True reflDir

        TIO.writeFile (reflDir </> "2026-03-28.md") "---\ntitle: 2026-03-28\n---\n\n# Reflection\n"

        _ <- addUpdateLinksToReflection reflDir "2026-03-28"
               [UpdateLink (RelativePath "img.md") (Title "Image Page") ["🖼️ added image"]]
        _ <- addUpdateLinksToReflection reflDir "2026-03-28"
               [UpdateLink (RelativePath "social.md") (Title "Social Page") ["🦋 posted to BlueSky"]]

        content <- TIO.readFile (reflDir </> "2026-03-28.md")
        assertBool "has image page" (T.isInfixOf "[[img|Image Page]]" content)
        assertBool "has social page" (T.isInfixOf "[[social|Social Page]]" content)
        assertBool "has image detail" (T.isInfixOf "  - 🖼️ added image" content)
        assertBool "has social detail" (T.isInfixOf "  - 🦋 posted to BlueSky" content)
  ]
