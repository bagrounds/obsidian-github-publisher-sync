module Automation.DailyUpdatesTest (tests) where

import Data.List (find)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Data.Time (fromGregorian)
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertEqual, assertBool, testCase, (@?=))
import Test.Tasty.QuickCheck (testProperty)
import qualified Test.Tasty.QuickCheck as QC

import Automation.DailyUpdates
import Automation.Platform (Platform (..))
import Automation.TestGenerators (testTitle, testRelativePath)

tests :: TestTree
tests = testGroup "DailyUpdates"
  [ addUpdateLinksTests
  , buildChangesPageContentTests
  , addChangesForwardLinkTests
  , addUpdateLinksToReflectionTests
  ]

buildChangesPageContentTests :: TestTree
buildChangesPageContentTests = testGroup "buildChangesPageContent"
  [ testCase "uses correct back marker emoji when previous date provided" $
      let content = buildChangesPageContent (fromGregorian 2026 4 2) (Just "2026-04-01")
      in do
        assertBool "contains ⏮️" (T.isInfixOf "⏮️" content)
        assertBool "links to previous changes date" (T.isInfixOf "[[changes/2026-04-01|⏮️]]" content)
  , testCase "no back link when no previous date" $
      let content = buildChangesPageContent (fromGregorian 2026 4 1) Nothing
      in assertBool "no back marker" (not (T.isInfixOf "⏮️" content))
  ]

addChangesForwardLinkTests :: TestTree
addChangesForwardLinkTests = testGroup "addChangesForwardLink"
  [ testCase "adds forward link after existing back link" $
      let content = "[[index|Home]] > [[changes/index|Changes]] | [[reflections/2026-04-01|\129694 2026-04-01]] | [[changes/2026-03-31|⏮️]]\n# 2026-04-01"
          result = addChangesForwardLink content "2026-04-02"
      in do
        assertBool "contains ⏭️" (T.isInfixOf "⏭️" result)
        assertBool "links to target date" (T.isInfixOf "[[changes/2026-04-02|⏭️]]" result)
  , testCase "does not add duplicate forward link" $
      let content = "[[changes/2026-03-31|⏮️]] [[changes/2026-04-02|⏭️]]\n# Post"
          result = addChangesForwardLink content "2026-04-03"
      in result @?= content
  , testCase "adds forward link when no back link present" $
      let content = "[[index|Home]] > [[changes/index|Changes]]\n# Post"
          result = addChangesForwardLink content "2026-04-02"
      in do
        assertBool "contains ⏭️" (T.isInfixOf "⏭️" result)
        assertBool "links to target date" (T.isInfixOf "[[changes/2026-04-02|⏭️]]" result)
  , testProperty "addChangesForwardLink is idempotent" $
      \(QC.ASCIIString dateStr) ->
        let date = T.pack dateStr
            content = "nav | [[changes/prev|⏮️]]\n# Post"
            once = addChangesForwardLink content date
            twice = addChangesForwardLink once date
        in once == twice
  , testProperty "addChangesForwardLink is idempotent without back link" $
      \(QC.ASCIIString dateStr) ->
        let date = T.pack dateStr
            content = "[[index|Home]] > [[changes/index|Changes]]\n# Post"
            once = addChangesForwardLink content date
            twice = addChangesForwardLink once date
        in once == twice
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

  , testCase "extractStatsLine finds stats line in content" $
      do
        assertEqual "extracts from section" (Just "📊 3 pages · 2 🖼️ images")
          (extractStatsLine "## 🔄 Updates\n📊 3 pages · 2 🖼️ images\n\n| Page |")
        assertEqual "returns Nothing when absent" Nothing
          (extractStatsLine "# Heading\n\nNo stats here")
        assertEqual "extracts from multiline content" (Just "📊 1 page · 1 🦋 Bluesky")
          (extractStatsLine "---\ntitle: test\n---\n# Heading\n\n## 🔄 Updates\n📊 1 page · 1 🦋 Bluesky\n")

  , testCase "resolveRelativePath converts paths correctly" $
      do
        assertEqual "dot-slash" "reflections/file" (resolveRelativePath "./file")
        assertEqual "dot-dot-slash" "ai-blog/post" (resolveRelativePath "../ai-blog/post")
        assertEqual "bare name" "reflections/file" (resolveRelativePath "file")

  , testCase "parses Obsidian-formatted table with column padding" $
      let content = T.unlines
            [ "# Reflection"
            , ""
            , "## 🔄 Updates"
            , "📊 3 pages · 3 🖼️ images"
            , ""
            , "| Page                                                                   | 🖼️ |"
            , "| ---------------------------------------------------------------------- | --- |"
            , "| [[books/the-creative-act\\|✨🎭🧘\x200d♂️🌌 The Creative Act: A Way of Being]] | 🖼️ |"
            , "| [[books/thinking-fast-and-slow\\|🤔🐇🐢 Thinking, Fast and Slow]]          | 🖼️ |"
            , "| [[books/sapiens\\|📜🌍⏳ Sapiens: A Brief History of Humankind]]            | 🖼️ |"
            ]
          result = addUpdateLinks content
                     [UpdateLink (testRelativePath "new-book.md") (testTitle "New Book") [ImageAdded]]
      in do
        assertBool "stats show 4 pages" (T.isInfixOf "📊 4 pages" result)
        assertBool "preserves creative act" (T.isInfixOf "The Creative Act" result)
        assertBool "preserves thinking fast" (T.isInfixOf "Thinking, Fast and Slow" result)
        assertBool "preserves sapiens" (T.isInfixOf "Sapiens" result)
        assertBool "has new book" (T.isInfixOf "New Book" result)

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
  [ testCase "writes updates to changes page and links reflection" $
      withSystemTempDirectory "daily-updates-test" $ \tmpDir -> do
        let reflDir = tmpDir </> "reflections"
            testDate = fromGregorian 2026 3 28
        createDirectoryIfMissing True reflDir

        TIO.writeFile (reflDir </> "2026-03-28.md") "---\ntitle: 2026-03-28\n---\n\n# Reflection\n"

        modified <- addUpdateLinksToReflection tmpDir testDate
                      [UpdateLink (testRelativePath "ai-blog/post.md") (testTitle "A Post") [ImageAdded]]
        assertBool "should report modification" modified

        changesContent <- TIO.readFile (tmpDir </> "changes" </> "2026-03-28.md")
        assertBool "changes has updates header" (T.isInfixOf "## \128260 Updates" changesContent)
        assertBool "changes has page link" (T.isInfixOf "[[ai-blog/post\\|A Post]]" changesContent)
        assertBool "changes has table format" (T.isInfixOf "| Page |" changesContent)
        assertBool "changes has stats with legend" (T.isInfixOf "\128202 1 page \183 1 \128444\65039 images" changesContent)

        reflContent <- TIO.readFile (reflDir </> "2026-03-28.md")
        assertBool "reflection has changes heading pointing to index" (T.isInfixOf "## [[changes/index|\128260 Changes]]" reflContent)
        assertBool "reflection has stats preview with date link" (T.isInfixOf "[[changes/2026-03-28|2026-03-28]]" reflContent)
        assertBool "reflection has stats in preview" (T.isInfixOf "\128202 1 page \183 1 \128444\65039 images" reflContent)
        assertBool "reflection does not have updates table" (not (T.isInfixOf "| Page |" reflContent))

  , testCase "creates changes index page with dataview" $
      withSystemTempDirectory "daily-updates-test" $ \tmpDir -> do
        let reflDir = tmpDir </> "reflections"
            testDate = fromGregorian 2026 3 28
        createDirectoryIfMissing True reflDir
        TIO.writeFile (reflDir </> "2026-03-28.md") "---\ntitle: 2026-03-28\n---\n\n# Reflection\n"

        _ <- addUpdateLinksToReflection tmpDir testDate
               [UpdateLink (testRelativePath "page.md") (testTitle "A Page") [ImageAdded]]

        indexContent <- TIO.readFile (tmpDir </> "changes" </> "index.md")
        assertBool "index has title" (T.isInfixOf "\128260 Changes" indexContent)
        assertBool "index has home link" (T.isInfixOf "[[index|Home]]" indexContent)
        assertBool "index has dataview block" (T.isInfixOf "```dataview" indexContent)
        assertBool "index has FROM clause" (T.isInfixOf "FROM \"changes\"" indexContent)
        assertBool "index has LIST query" (T.isInfixOf "LIST WITHOUT ID" indexContent)

  , testCase "returns false when details already present in table format" $
      withSystemTempDirectory "daily-updates-test" $ \tmpDir -> do
        let reflDir = tmpDir </> "reflections"
            testDate = fromGregorian 2026 3 28
        createDirectoryIfMissing True reflDir

        TIO.writeFile (reflDir </> "2026-03-28.md") "---\ntitle: 2026-03-28\n---\n\n# Reflection\n"

        _ <- addUpdateLinksToReflection tmpDir testDate
               [UpdateLink (testRelativePath "ai-blog/post.md") (testTitle "A Post") [ImageAdded]]

        modified <- addUpdateLinksToReflection tmpDir testDate
                      [UpdateLink (testRelativePath "ai-blog/post.md") (testTitle "A Post") [ImageAdded]]
        assertBool "should report no modification" (not modified)

  , testCase "returns false for empty links" $
      withSystemTempDirectory "daily-updates-test" $ \tmpDir -> do
        let testDate = fromGregorian 2026 3 28
        modified <- addUpdateLinksToReflection tmpDir testDate []
        assertBool "should report no modification" (not modified)

  , testCase "different operations accumulate details under same page" $
      withSystemTempDirectory "daily-updates-test" $ \tmpDir -> do
        let reflDir = tmpDir </> "reflections"
            testDate = fromGregorian 2026 3 28
        createDirectoryIfMissing True reflDir

        TIO.writeFile (reflDir </> "2026-03-28.md") "---\ntitle: 2026-03-28\n---\n\n# Reflection\n"

        _ <- addUpdateLinksToReflection tmpDir testDate
               [UpdateLink (testRelativePath "page.md") (testTitle "My Page") [ImageAdded]]
        _ <- addUpdateLinksToReflection tmpDir testDate
               [UpdateLink (testRelativePath "page.md") (testTitle "My Page") [PostedTo Bluesky]]

        content <- TIO.readFile (tmpDir </> "changes" </> "2026-03-28.md")
        assertBool "has page link" (T.isInfixOf "[[page\\|My Page]]" content)
        assertBool "has image column" (T.isInfixOf "\128444\65039" content)
        assertBool "has bluesky column" (T.isInfixOf "\129419" content)
        assertBool "stats show both" (T.isInfixOf "1 \128444\65039 images" content && T.isInfixOf "1 \129419 Bluesky" content)

  , testCase "different pages create separate table rows" $
      withSystemTempDirectory "daily-updates-test" $ \tmpDir -> do
        let reflDir = tmpDir </> "reflections"
            testDate = fromGregorian 2026 3 28
        createDirectoryIfMissing True reflDir

        TIO.writeFile (reflDir </> "2026-03-28.md") "---\ntitle: 2026-03-28\n---\n\n# Reflection\n"

        _ <- addUpdateLinksToReflection tmpDir testDate
               [UpdateLink (testRelativePath "img.md") (testTitle "Image Page") [ImageAdded]]
        _ <- addUpdateLinksToReflection tmpDir testDate
               [UpdateLink (testRelativePath "social.md") (testTitle "Social Page") [PostedTo Bluesky]]

        content <- TIO.readFile (tmpDir </> "changes" </> "2026-03-28.md")
        assertBool "has image page" (T.isInfixOf "[[img\\|Image Page]]" content)
        assertBool "has social page" (T.isInfixOf "[[social\\|Social Page]]" content)
        assertBool "stats show 2 pages" (T.isInfixOf "\128202 2 pages" content)

  , testCase "changes page has proper frontmatter and nav" $
      withSystemTempDirectory "daily-updates-test" $ \tmpDir -> do
        let reflDir = tmpDir </> "reflections"
            testDate = fromGregorian 2026 3 28
        createDirectoryIfMissing True reflDir
        TIO.writeFile (reflDir </> "2026-03-28.md") "---\ntitle: 2026-03-28\n---\n\n# Reflection\n"

        _ <- addUpdateLinksToReflection tmpDir testDate
               [UpdateLink (testRelativePath "page.md") (testTitle "A Page") [ImageAdded]]

        content <- TIO.readFile (tmpDir </> "changes" </> "2026-03-28.md")
        assertBool "has frontmatter" (T.isPrefixOf "---" content)
        assertBool "has share true" (T.isInfixOf "share: true" content)
        assertBool "has URL" (T.isInfixOf "https://bagrounds.org/changes/2026-03-28" content)
        assertBool "has reflection backlink with date" (T.isInfixOf "[[reflections/2026-03-28|\129694 2026-03-28]]" content)
        assertBool "has changes index link" (T.isInfixOf "[[changes/index|Changes]]" content)

  , testCase "adds forward link to previous changes page" $
      withSystemTempDirectory "daily-updates-test" $ \tmpDir -> do
        let reflDir = tmpDir </> "reflections"
            day1 = fromGregorian 2026 3 27
            day2 = fromGregorian 2026 3 28
        createDirectoryIfMissing True reflDir
        TIO.writeFile (reflDir </> "2026-03-27.md") "---\ntitle: 2026-03-27\n---\n\n# Reflection\n"
        TIO.writeFile (reflDir </> "2026-03-28.md") "---\ntitle: 2026-03-28\n---\n\n# Reflection\n"

        _ <- addUpdateLinksToReflection tmpDir day1
               [UpdateLink (testRelativePath "page1.md") (testTitle "Page 1") [ImageAdded]]
        _ <- addUpdateLinksToReflection tmpDir day2
               [UpdateLink (testRelativePath "page2.md") (testTitle "Page 2") [ImageAdded]]

        prevContent <- TIO.readFile (tmpDir </> "changes" </> "2026-03-27.md")
        assertBool "previous page has forward link" (T.isInfixOf "⏭️" prevContent)

        nextContent <- TIO.readFile (tmpDir </> "changes" </> "2026-03-28.md")
        assertBool "next page has backward link" (T.isInfixOf "⏮️" nextContent)

  , testCase "stats preview in reflection stays in sync with changes page" $
      withSystemTempDirectory "daily-updates-test" $ \tmpDir -> do
        let reflDir = tmpDir </> "reflections"
            testDate = fromGregorian 2026 3 28
        createDirectoryIfMissing True reflDir
        TIO.writeFile (reflDir </> "2026-03-28.md") "---\ntitle: 2026-03-28\n---\n\n# Reflection\n"

        _ <- addUpdateLinksToReflection tmpDir testDate
               [UpdateLink (testRelativePath "page1.md") (testTitle "Page 1") [ImageAdded]]

        reflContent1 <- TIO.readFile (reflDir </> "2026-03-28.md")
        assertBool "reflection has stats preview after first update"
          (T.isInfixOf "[[changes/2026-03-28|2026-03-28]] | \128202 1 page" reflContent1)

        _ <- addUpdateLinksToReflection tmpDir testDate
               [UpdateLink (testRelativePath "page2.md") (testTitle "Page 2") [PostedTo Bluesky]]

        reflContent2 <- TIO.readFile (reflDir </> "2026-03-28.md")
        assertBool "reflection stats preview updated after second update"
          (T.isInfixOf "[[changes/2026-03-28|2026-03-28]] | \128202 2 pages" reflContent2)
        assertBool "old stats preview removed"
          (not (T.isInfixOf "\128202 1 page" reflContent2))
  ]
