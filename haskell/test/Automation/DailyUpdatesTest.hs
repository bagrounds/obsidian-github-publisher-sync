module Automation.DailyUpdatesTest (tests) where

import Data.List (find)
import Data.Text (Text)
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
import Automation.Platform (Platform (..))
import Automation.TestGenerators (testTitle, testRelativePath)

tests :: TestTree
tests = testGroup "DailyUpdates"
  [ addUpdateLinksTests
  , addUpdateLinksToReflectionTests
  ]

addUpdateLinksTests :: TestTree
addUpdateLinksTests = testGroup "addUpdateLinks"
  [ testCase "creates new section with table and stats when no updates section exists" $
      let content = "# My Reflection\n\nSome content here"
          result = addUpdateLinks content
                     [UpdateLink (testRelativePath "ai-blog/2026-03-28-post.md") (testTitle "Post Title") [ImageAdded]]
      in do
        assertBool "should contain updates header"
          (T.isInfixOf "## 🔄 Updates" result)
        assertBool "should contain stats line with legend"
          (T.isInfixOf "📊 1 page · 1 🖼️ images" result)
        assertBool "should contain table header"
          (T.isInfixOf "| Page | 🖼️ |" result)
        assertBool "should contain the page link with escaped pipe"
          (T.isInfixOf "[[ai-blog/2026-03-28-post\\|Post Title]]" result)
        assertBool "should contain image emoji cell"
          (T.isInfixOf "🖼️" result)

  , testCase "adds new page row when updates section exists but page missing" $
      let content = existingTableContent
              [("page1", "Page 1", [ImageAdded])]
          result = addUpdateLinks content
                     [UpdateLink (testRelativePath "ai-blog/cool-post.md") (testTitle "Cool Post") [PostedTo Bluesky]]
      in do
        assertBool "should preserve existing page"
          (T.isInfixOf "[[page1\\|Page 1]]" result)
        assertBool "should contain the new page"
          (T.isInfixOf "[[ai-blog/cool-post\\|Cool Post]]" result)
        assertBool "should show both columns"
          (T.isInfixOf "| 🖼️ | 🦋 |" result)

  , testCase "merges details into existing page entry" $
      let content = existingTableContent
              [("page1", "Page 1", [ImageAdded])]
          result = addUpdateLinks content
                     [UpdateLink (testRelativePath "page1.md") (testTitle "Page 1") [PostedTo Bluesky]]
      in do
        assertBool "should show both columns in header"
          (T.isInfixOf "| 🖼️ | 🦋 |" result)
        let pageLines = filter (T.isInfixOf "[[page1\\|Page 1]]") (T.splitOn "\n" result)
        assertEqual "should have exactly one page entry" 1 (length pageLines)

  , testCase "skips duplicate details" $
      let content = existingTableContent
              [("page1", "Page 1", [ImageAdded])]
          result = addUpdateLinks content
                     [UpdateLink (testRelativePath "page1.md") (testTitle "Page 1") [ImageAdded]]
      in assertEqual "should not change content" content result

  , testCase "returns content unchanged for empty links" $
      let content = "# My Reflection\n\nSome content"
          result = addUpdateLinks content []
      in assertEqual "should not change" content result

  , testCase "multiple pages in same content" $
      let content0 = "# My Reflection\n\nSome content"
          content1 = addUpdateLinks content0
                       [UpdateLink (testRelativePath "img-page.md") (testTitle "Image Page") [ImageAdded]]
          content2 = addUpdateLinks content1
                       [UpdateLink (testRelativePath "social-page.md") (testTitle "Social Page") [PostedTo Bluesky]]
          content3 = addUpdateLinks content2
                       [UpdateLink (testRelativePath "link-page.md") (testTitle "Link Page") [InternalLinksAdded 3]]
      in do
        assertBool "has image page" (T.isInfixOf "[[img-page\\|Image Page]]" content3)
        assertBool "has social page" (T.isInfixOf "[[social-page\\|Social Page]]" content3)
        assertBool "has link page" (T.isInfixOf "[[link-page\\|Link Page]]" content3)
        assertBool "stats show 3 pages" (T.isInfixOf "📊 3 pages" content3)

  , testCase "preserves content after updates section" $
      let content = existingTableContent
              [("p1", "P1", [ImageAdded])]
              <> "\n## 📚 Books\n\nSome books"
          result = addUpdateLinks content
                     [UpdateLink (testRelativePath "sp.md") (testTitle "SP") [PostedTo Bluesky]]
      in do
        assertBool "should preserve books section"
          (T.isInfixOf "## 📚 Books" result)
        assertBool "should preserve books content"
          (T.isInfixOf "Some books" result)
        assertBool "should add social page"
          (T.isInfixOf "[[sp\\|SP]]" result)

  , testCase "adds multiple details at once for a single page" $
      let content = "# Reflection"
          result = addUpdateLinks content
                     [UpdateLink (testRelativePath "a.md") (testTitle "Page A") [PostedTo Bluesky, PostedTo Mastodon]]
      in do
        assertBool "has page" (T.isInfixOf "[[a\\|Page A]]" result)
        assertBool "has both platform columns" (T.isInfixOf "| 🦋 | 🐘 |" result)

  , testCase "adds multiple pages at once" $
      let content = "# Reflection"
          result = addUpdateLinks content
                     [ UpdateLink (testRelativePath "a.md") (testTitle "Page A") [ImageAdded]
                     , UpdateLink (testRelativePath "b.md") (testTitle "Page B") [PostedTo Bluesky]
                     , UpdateLink (testRelativePath "c.md") (testTitle "Page C") [InternalLinksAdded 2]
                     ]
      in do
        assertBool "has A" (T.isInfixOf "[[a\\|Page A]]" result)
        assertBool "has B" (T.isInfixOf "[[b\\|Page B]]" result)
        assertBool "has C" (T.isInfixOf "[[c\\|Page C]]" result)
        assertBool "stats show 3 pages" (T.isInfixOf "📊 3 pages" result)

  , testCase "inserts updates section before social media sections" $
      let content = "# My Reflection\n\nBody text\n\n## 🐦 Tweet\n\nTweet embed"
          result = addUpdateLinks content
                     [UpdateLink (testRelativePath "img.md") (testTitle "Image Page") [ImageAdded]]
      in do
        assertBool "has updates header" (T.isInfixOf "## 🔄 Updates" result)
        assertBool "has page link" (T.isInfixOf "[[img\\|Image Page]]" result)
        assertBool "updates before tweet" $
          let uIdx = T.length $ fst $ T.breakOn "## 🔄 Updates" result
              tIdx = T.length $ fst $ T.breakOn "## 🐦 Tweet" result
          in uIdx < tIdx

  , testCase "inserts updates section before bluesky section" $
      let content = "# My Reflection\n\nBody text\n\n## 🦋 Bluesky\n\nBluesky embed"
          result = addUpdateLinks content
                     [UpdateLink (testRelativePath "img.md") (testTitle "Image Page") [ImageAdded]]
      in assertBool "updates before bluesky" $
          let uIdx = T.length $ fst $ T.breakOn "## 🔄 Updates" result
              bIdx = T.length $ fst $ T.breakOn "## 🦋 Bluesky" result
          in uIdx < bIdx

  , testCase "incremental updates from different operations accumulate under same page" $
      let content0 = "# My Reflection\n\nSome content"
          content1 = addUpdateLinks content0
                       [UpdateLink (testRelativePath "page1.md") (testTitle "Page 1") [ImageAdded]]
          content2 = addUpdateLinks content1
                       [UpdateLink (testRelativePath "page1.md") (testTitle "Page 1") [PostedTo Bluesky]]
          content3 = addUpdateLinks content2
                       [UpdateLink (testRelativePath "page1.md") (testTitle "Page 1") [InternalLinksAdded 2]]
      in do
        assertBool "one page link" (T.isInfixOf "[[page1\\|Page 1]]" content3)
        assertBool "stats show 1 page" (T.isInfixOf "📊 1 page" content3)
        assertBool "has all three columns" (T.isInfixOf "| 🖼️ | 🔗 | 🦋 |" content3)
        let pageOccurrences = length $ T.splitOn "[[page1\\|Page 1]]" content3
        assertEqual "should have exactly one page entry" 2 pageOccurrences

  , testCase "table row contains emoji cell values for platforms" $
      let content = "# Reflection"
          result = addUpdateLinks content
                     [UpdateLink (testRelativePath "page.md") (testTitle "My Page") [ImageAdded, PostedTo Bluesky]]
          resultLines = T.splitOn "\n" result
          pageLines = filter (T.isInfixOf "[[page\\|My Page]]") resultLines
      in case pageLines of
        (pageLine : _) -> do
          assertBool "page row contains image emoji" (T.isInfixOf "🖼️" pageLine)
          assertBool "page row contains bluesky emoji" (T.isInfixOf "🦋" pageLine)
          assertBool "page row contains page link" (T.isInfixOf "[[page\\|My Page]]" pageLine)
        [] -> assertBool "page link should be present" False

  , testCase "same detail under different pages is not deduplicated across pages" $
      let content = "# Reflection"
          result = addUpdateLinks content
                     [ UpdateLink (testRelativePath "page-a.md") (testTitle "Page A") [ImageAdded]
                     , UpdateLink (testRelativePath "page-b.md") (testTitle "Page B") [ImageAdded]
                     ]
      in do
        assertBool "has page A" (T.isInfixOf "[[page-a\\|Page A]]" result)
        assertBool "has page B" (T.isInfixOf "[[page-b\\|Page B]]" result)
        assertBool "stats show 2 images" (T.isInfixOf "2 🖼️ images" result)

  , testCase "same detail under different pages works incrementally" $
      let content0 = "# Reflection"
          content1 = addUpdateLinks content0
                       [UpdateLink (testRelativePath "page-a.md") (testTitle "Page A") [ImageAdded]]
          content2 = addUpdateLinks content1
                       [UpdateLink (testRelativePath "page-b.md") (testTitle "Page B") [ImageAdded]]
      in do
        assertBool "has page A" (T.isInfixOf "[[page-a\\|Page A]]" content2)
        assertBool "has page B" (T.isInfixOf "[[page-b\\|Page B]]" content2)
        assertBool "stats show 2 images" (T.isInfixOf "2 🖼️ images" content2)

  , testCase "internal links stats sum across pages" $
      let content = "# Reflection"
          result = addUpdateLinks content
                     [ UpdateLink (testRelativePath "a.md") (testTitle "Page A") [InternalLinksAdded 3]
                     , UpdateLink (testRelativePath "b.md") (testTitle "Page B") [InternalLinksAdded 5]
                     ]
      in assertBool "stats show total 8 links" (T.isInfixOf "8 🔗 links" result)

  , testCase "internal links accumulate additively for same page" $
      let content0 = "# Reflection"
          content1 = addUpdateLinks content0
                       [UpdateLink (testRelativePath "page.md") (testTitle "Page") [InternalLinksAdded 2]]
          content2 = addUpdateLinks content1
                       [UpdateLink (testRelativePath "page.md") (testTitle "Page") [InternalLinksAdded 3]]
      in assertBool "stats show total 5 links" (T.isInfixOf "5 🔗 links" content2)

  , testCase "only active columns are shown in table header" $
      let content = "# Reflection"
          result = addUpdateLinks content
                     [UpdateLink (testRelativePath "a.md") (testTitle "Page A") [ImageAdded, PostedTo Mastodon]]
      in do
        assertBool "shows image column" (T.isInfixOf "🖼️" result)
        assertBool "shows mastodon column" (T.isInfixOf "🐘" result)
        assertBool "no links column in header"
          (not $ T.isInfixOf "| 🔗 |" result)

  , testCase "migrates legacy bullet format to table on next update" $
      let content = "# Reflection\n\n## 🔄 Updates\n- [[page1|Page 1]]\n  - 🖼️ added image\n  - 🦋 posted to BlueSky\n"
          result = addUpdateLinks content
                     [UpdateLink (testRelativePath "page1.md") (testTitle "Page 1") [PostedTo Mastodon]]
      in do
        assertBool "has table header" (T.isInfixOf "| Page |" result)
        assertBool "has stats line" (T.isInfixOf "📊 1 page" result)
        assertBool "has image column" (T.isInfixOf "🖼️" result)
        assertBool "has bluesky in table" (T.isInfixOf "🦋" result)
        assertBool "has mastodon in table" (T.isInfixOf "🐘" result)
        assertBool "no bullet format" (not $ T.isInfixOf "  - " result)

  , testCase "stats line serves as legend with descriptive words" $
      let content = "# Reflection"
          result = addUpdateLinks content
                     [ UpdateLink (testRelativePath "a.md") (testTitle "A") [ImageAdded, PostedTo Bluesky, InternalLinksAdded 3]
                     , UpdateLink (testRelativePath "b.md") (testTitle "B") [PostedTo Mastodon]
                     ]
      in do
        assertBool "has images label" (T.isInfixOf "🖼️ images" result)
        assertBool "has links label" (T.isInfixOf "🔗 links" result)
        assertBool "has Bluesky label" (T.isInfixOf "🦋 Bluesky" result)
        assertBool "has Mastodon label" (T.isInfixOf "🐘 Mastodon" result)

  , testCase "title containing pipe is escaped in table and round-trips correctly" $
      let content = "# Reflection"
          result = addUpdateLinks content
                     [UpdateLink (testRelativePath "reflections/2026-03-28.md") (testTitle "2026-03-28 | My Reflection") [ImageAdded]]
      in do
        assertBool "escaped pipe in wiki link"
          (T.isInfixOf "[[reflections/2026-03-28\\|2026-03-28 \\| My Reflection]]" result)
        let result2 = addUpdateLinks result
                        [UpdateLink (testRelativePath "reflections/2026-03-28.md") (testTitle "2026-03-28 | My Reflection") [PostedTo Bluesky]]
        assertBool "round-trips: page still has single entry"
          (let pageOccurrences = length $ T.splitOn "reflections/2026-03-28" result2
           in pageOccurrences == 2)
        assertBool "round-trips: both columns present"
          (T.isInfixOf "| 🖼️ | 🦋 |" result2)

  , testCase "title with multiple pipes is fully escaped" $
      let content = "# Reflection"
          result = addUpdateLinks content
                     [UpdateLink (testRelativePath "notes/test.md") (testTitle "A | B | C") [PostedTo Mastodon]]
      in do
        assertBool "all pipes escaped"
          (T.isInfixOf "[[notes/test\\|A \\| B \\| C]]" result)
        let result2 = addUpdateLinks result
                        [UpdateLink (testRelativePath "notes/test.md") (testTitle "A | B | C") [ImageAdded]]
        assertBool "round-trips with multi-pipe title"
          (T.isInfixOf "| 🖼️ |" result2 && T.isInfixOf "| 🐘 |" result2)

  , testCase "migrates legacy checkmark format to emoji cells" $
      let content = "# Reflection\n\n## 🔄 Updates\n📊 1 page · 1 🖼️\n\n| Page | 🖼️ | 🦋 |\n|---|---|---|\n| [[page1|Page 1]] | ✓ | ✓ |\n"
          result = addUpdateLinks content
                     [UpdateLink (testRelativePath "page1.md") (testTitle "Page 1") [PostedTo Mastodon]]
      in do
        assertBool "image cell uses emoji" (T.isInfixOf "🖼️ |" result)
        assertBool "bluesky cell uses emoji" (T.isInfixOf "🦋 |" result)
        assertBool "mastodon cell uses emoji" (T.isInfixOf "🐘 |" result)
        assertBool "no checkmarks in output" (not $ T.isInfixOf "✓" result)

  , testProperty "addUpdateLinks never removes existing lines outside updates section" $
      \(QC.ASCIIString bodyStr) ->
        let body = T.pack bodyStr
            content = "# Reflection\n\n" <> body <> "\n\nSome footer"
            result = addUpdateLinks content
                       [UpdateLink (testRelativePath "test.md") (testTitle "Test") [ImageAdded]]
        in T.isInfixOf "Some footer" result

  , testCase "preserves existing entries when table contains standard markdown links" $
      let content = T.unlines
            [ "# Reflection"
            , ""
            , "## 🔄 Updates"
            , "📊 3 pages · 3 🖼️ images"
            , ""
            , "| Page | 🖼️ |"
            , "|---|---|"
            , "| [Page One](./page-one.md) | 🖼️ |"
            , "| [Page Two](../ai-blog/page-two.md) | 🖼️ |"
            , "| [Page Three](../books/page-three.md) | 🖼️ |"
            ]
          result = addUpdateLinks content
                     [UpdateLink (testRelativePath "new-page.md") (testTitle "New Page") [ImageAdded]]
      in do
        assertBool "stats show 4 pages" (T.isInfixOf "📊 4 pages" result)
        assertBool "has new page" (T.isInfixOf "New Page" result)
        assertBool "preserves page one" (T.isInfixOf "Page One" result)
        assertBool "preserves page two" (T.isInfixOf "Page Two" result)
        assertBool "preserves page three" (T.isInfixOf "Page Three" result)

  , testCase "parses markdown links with escaped pipes in title" $
      let content = T.unlines
            [ "# Reflection"
            , ""
            , "## 🔄 Updates"
            , "📊 1 page · 1 🖼️ images"
            , ""
            , "| Page | 🖼️ |"
            , "|---|---|"
            , "| [2026-04-13 \\| My Reflection](./2026-04-13.md) | 🖼️ |"
            ]
          result = addUpdateLinks content
                     [UpdateLink (testRelativePath "new.md") (testTitle "New") [PostedTo Bluesky]]
      in do
        assertBool "stats show 2 pages" (T.isInfixOf "📊 2 pages" result)
        assertBool "has reflection entry" (T.isInfixOf "2026-04-13" result)
        assertBool "has new entry" (T.isInfixOf "New" result)

  , testCase "prevents data loss when table cannot be parsed" $
      let content = T.unlines
            [ "# Reflection"
            , ""
            , "## 🔄 Updates"
            , "📊 5 pages · 5 🖼️ images"
            , ""
            , "| Page | 🖼️ |"
            , "|---|---|"
            , "| UNPARSEABLE ROW 1 | 🖼️ |"
            , "| UNPARSEABLE ROW 2 | 🖼️ |"
            , "| UNPARSEABLE ROW 3 | 🖼️ |"
            , "| UNPARSEABLE ROW 4 | 🖼️ |"
            , "| UNPARSEABLE ROW 5 | 🖼️ |"
            ]
          result = addUpdateLinks content
                     [UpdateLink (testRelativePath "new.md") (testTitle "New") [ImageAdded]]
      in assertEqual "should preserve content unchanged when parsing fails but stats show entries"
           content result

  , testCase "parseStatsPageCount extracts count from stats line" $
      do
        assertEqual "parses 31 pages" 31 (parseStatsPageCount "📊 31 pages · 24 🖼️ images")
        assertEqual "parses 1 page" 1 (parseStatsPageCount "📊 1 page · 1 🖼️ images")
        assertEqual "parses 0 for empty" 0 (parseStatsPageCount "")
        assertEqual "parses 0 for missing stats" 0 (parseStatsPageCount "no stats here")

  , testCase "resolveRelativePath converts paths correctly" $
      do
        assertEqual "dot-slash" "reflections/file" (resolveRelativePath "./file")
        assertEqual "dot-dot-slash" "ai-blog/post" (resolveRelativePath "../ai-blog/post")
        assertEqual "bare name" "reflections/file" (resolveRelativePath "file")

  , testCase "mixed wiki and markdown links in same table" $
      let content = T.unlines
            [ "# Reflection"
            , ""
            , "## 🔄 Updates"
            , "📊 2 pages · 2 🖼️ images"
            , ""
            , "| Page | 🖼️ |"
            , "|---|---|"
            , "| [[page1\\|Page One]] | 🖼️ |"
            , "| [Page Two](../ai-blog/page-two.md) | 🖼️ |"
            ]
          result = addUpdateLinks content
                     [UpdateLink (testRelativePath "page3.md") (testTitle "Page Three") [ImageAdded]]
      in do
        assertBool "stats show 3 pages" (T.isInfixOf "📊 3 pages" result)
        assertBool "preserves wiki link page" (T.isInfixOf "Page One" result)
        assertBool "preserves markdown link page" (T.isInfixOf "Page Two" result)
        assertBool "has new page" (T.isInfixOf "Page Three" result)
  ]

existingTableContent :: [(Text, Text, [UpdateDetail])] -> Text
existingTableContent entries =
  let allDetails = concatMap (\(_, _, details) -> details) entries
      columns = filter (\column -> any (matchesColumn column) allDetails) canonicalOrder
      header = "| Page | " <> T.intercalate " | " (fmap columnEmojiHelper columns) <> " |"
      separator = "|---|" <> T.concat (replicate (length columns) "---|")
      rows = fmap (buildRowHelper columns) entries
      statsLine = "📊 " <> T.pack (show (length entries)) <> " "
        <> (if length entries == 1 then "page" else "pages")
        <> T.concat (fmap (\column ->
            let count = computeStatHelper entries column
            in if count > 0 then " · " <> T.pack (show count) <> " " <> columnEmojiHelper column <> " " <> columnLabelHelper column else ""
          ) canonicalOrder)
      table = T.intercalate "\n" (header : separator : rows)
  in "# Reflection\n\n## 🔄 Updates\n" <> statsLine <> "\n\n" <> table <> "\n"
  where
    canonicalOrder :: [UpdateDetail]
    canonicalOrder = [ImageAdded, InternalLinksAdded 0, PostedTo Bluesky, PostedTo Mastodon, PostedTo Twitter]
    matchesColumn :: UpdateDetail -> UpdateDetail -> Bool
    matchesColumn ImageAdded ImageAdded = True
    matchesColumn (InternalLinksAdded _) (InternalLinksAdded _) = True
    matchesColumn (PostedTo a) (PostedTo b) = a == b
    matchesColumn _ _ = False
    columnEmojiHelper :: UpdateDetail -> Text
    columnEmojiHelper ImageAdded = "🖼️"
    columnEmojiHelper (InternalLinksAdded _) = "🔗"
    columnEmojiHelper (PostedTo Bluesky) = "🦋"
    columnEmojiHelper (PostedTo Mastodon) = "🐘"
    columnEmojiHelper (PostedTo Twitter) = "🐦"
    columnLabelHelper :: UpdateDetail -> Text
    columnLabelHelper ImageAdded = "images"
    columnLabelHelper (InternalLinksAdded _) = "links"
    columnLabelHelper (PostedTo Bluesky) = "Bluesky"
    columnLabelHelper (PostedTo Mastodon) = "Mastodon"
    columnLabelHelper (PostedTo Twitter) = "Twitter"
    cellHelper :: UpdateDetail -> Text
    cellHelper (InternalLinksAdded n) = T.pack (show n)
    cellHelper detail = columnEmojiHelper detail
    buildRowHelper :: [UpdateDetail] -> (Text, Text, [UpdateDetail]) -> Text
    buildRowHelper columns (path, title, details) =
      let escapedPath = T.replace "|" "\\|" path
          escapedTitle = T.replace "|" "\\|" title
          pageLink = "[[" <> escapedPath <> "\\|" <> escapedTitle <> "]]"
          cells = fmap (\column -> maybe "" cellHelper (find (matchesColumn column) details)) columns
      in "| " <> pageLink <> " | " <> T.intercalate " | " cells <> " |"
    computeStatHelper :: [(Text, Text, [UpdateDetail])] -> UpdateDetail -> Int
    computeStatHelper es (InternalLinksAdded _) = sum [n | (_, _, ds) <- es, InternalLinksAdded n <- ds]
    computeStatHelper es column = length (filter (\(_, _, ds) -> any (matchesColumn column) ds) es)

addUpdateLinksToReflectionTests :: TestTree
addUpdateLinksToReflectionTests = testGroup "addUpdateLinksToReflection"
  [ testCase "creates reflection and adds page with details" $
      withSystemTempDirectory "daily-updates-test" $ \tmpDir -> do
        let reflDir = tmpDir </> "reflections"
        createDirectoryIfMissing True reflDir

        TIO.writeFile (reflDir </> "2026-03-28.md") "---\ntitle: 2026-03-28\n---\n\n# Reflection\n"

        modified <- addUpdateLinksToReflection reflDir "2026-03-28"
                      [UpdateLink (testRelativePath "ai-blog/post.md") (testTitle "A Post") [ImageAdded]]
        assertBool "should report modification" modified

        content <- TIO.readFile (reflDir </> "2026-03-28.md")
        assertBool "has updates header" (T.isInfixOf "## 🔄 Updates" content)
        assertBool "has page link" (T.isInfixOf "[[ai-blog/post\\|A Post]]" content)
        assertBool "has table format" (T.isInfixOf "| Page |" content)
        assertBool "has stats with legend" (T.isInfixOf "📊 1 page · 1 🖼️ images" content)

  , testCase "returns false when details already present in table format" $
      withSystemTempDirectory "daily-updates-test" $ \tmpDir -> do
        let reflDir = tmpDir </> "reflections"
        createDirectoryIfMissing True reflDir

        TIO.writeFile (reflDir </> "2026-03-28.md") "---\ntitle: 2026-03-28\n---\n\n# Reflection\n"

        _ <- addUpdateLinksToReflection reflDir "2026-03-28"
               [UpdateLink (testRelativePath "ai-blog/post.md") (testTitle "A Post") [ImageAdded]]

        modified <- addUpdateLinksToReflection reflDir "2026-03-28"
                      [UpdateLink (testRelativePath "ai-blog/post.md") (testTitle "A Post") [ImageAdded]]
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
               [UpdateLink (testRelativePath "page.md") (testTitle "My Page") [ImageAdded]]
        _ <- addUpdateLinksToReflection reflDir "2026-03-28"
               [UpdateLink (testRelativePath "page.md") (testTitle "My Page") [PostedTo Bluesky]]

        content <- TIO.readFile (reflDir </> "2026-03-28.md")
        assertBool "has page link" (T.isInfixOf "[[page\\|My Page]]" content)
        assertBool "has image column" (T.isInfixOf "🖼️" content)
        assertBool "has bluesky column" (T.isInfixOf "🦋" content)
        assertBool "stats show both" (T.isInfixOf "1 🖼️ images" content && T.isInfixOf "1 🦋 Bluesky" content)

  , testCase "different pages create separate table rows" $
      withSystemTempDirectory "daily-updates-test" $ \tmpDir -> do
        let reflDir = tmpDir </> "reflections"
        createDirectoryIfMissing True reflDir

        TIO.writeFile (reflDir </> "2026-03-28.md") "---\ntitle: 2026-03-28\n---\n\n# Reflection\n"

        _ <- addUpdateLinksToReflection reflDir "2026-03-28"
               [UpdateLink (testRelativePath "img.md") (testTitle "Image Page") [ImageAdded]]
        _ <- addUpdateLinksToReflection reflDir "2026-03-28"
               [UpdateLink (testRelativePath "social.md") (testTitle "Social Page") [PostedTo Bluesky]]

        content <- TIO.readFile (reflDir </> "2026-03-28.md")
        assertBool "has image page" (T.isInfixOf "[[img\\|Image Page]]" content)
        assertBool "has social page" (T.isInfixOf "[[social\\|Social Page]]" content)
        assertBool "stats show 2 pages" (T.isInfixOf "📊 2 pages" content)
  ]
