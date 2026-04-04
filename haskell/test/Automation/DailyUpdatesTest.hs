module Automation.DailyUpdatesTest (tests) where

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

tests :: TestTree
tests = testGroup "DailyUpdates"
  [ addUpdateLinksTests
  , categorySubHeaderTests
  , addUpdateLinksToReflectionTests
  ]

--------------------------------------------------------------------------------
-- categorySubHeader
--------------------------------------------------------------------------------

categorySubHeaderTests :: TestTree
categorySubHeaderTests = testGroup "categorySubHeader"
  [ testCase "ImageUpdate has emoji prefix" $
      assertEqual "" "### 🖼️ Images" (categorySubHeader ImageUpdate)

  , testCase "InternalLinkUpdate has emoji prefix" $
      assertEqual "" "### 🔗 Internal Links" (categorySubHeader InternalLinkUpdate)

  , testCase "SocialPostUpdate has emoji prefix" $
      assertEqual "" "### 📢 Social Posts" (categorySubHeader SocialPostUpdate)
  ]

--------------------------------------------------------------------------------
-- addUpdateLinks (pure function)
--------------------------------------------------------------------------------

addUpdateLinksTests :: TestTree
addUpdateLinksTests = testGroup "addUpdateLinks"
  [ testCase "creates new section with sub-header when no updates section exists" $
      let content = "# My Reflection\n\nSome content here"
          result = addUpdateLinks content ImageUpdate
                     [UpdateLink "ai-blog/2026-03-28-post.md" "Post Title"]
      in do
        assertBool "should contain updates header"
          (T.isInfixOf "## 🔄 Updates" result)
        assertBool "should contain image sub-header"
          (T.isInfixOf "### 🖼️ Images" result)
        assertBool "should contain the link"
          (T.isInfixOf "[[ai-blog/2026-03-28-post|Post Title]]" result)

  , testCase "appends sub-section when updates section exists but category missing" $
      let content = "# My Reflection\n\n## 🔄 Updates\n\n### 🖼️ Images\n\n- [[page1|Page 1]]\n"
          result = addUpdateLinks content SocialPostUpdate
                     [UpdateLink "ai-blog/cool-post.md" "Cool Post"]
      in do
        assertBool "should still contain image sub-header"
          (T.isInfixOf "### 🖼️ Images" result)
        assertBool "should contain social posts sub-header"
          (T.isInfixOf "### 📢 Social Posts" result)
        assertBool "should contain the new link"
          (T.isInfixOf "[[ai-blog/cool-post|Cool Post]]" result)
        assertBool "should preserve existing link"
          (T.isInfixOf "[[page1|Page 1]]" result)

  , testCase "inserts into existing sub-section" $
      let content = "# My Reflection\n\n## 🔄 Updates\n\n### 🖼️ Images\n\n- [[page1|Page 1]]\n"
          result = addUpdateLinks content ImageUpdate
                     [UpdateLink "ai-blog/page2.md" "Page 2"]
      in do
        assertBool "should contain both links"
          (T.isInfixOf "[[page1|Page 1]]" result && T.isInfixOf "[[ai-blog/page2|Page 2]]" result)

  , testCase "skips duplicate links" $
      let content = "# My Reflection\n\n## 🔄 Updates\n\n### 🖼️ Images\n\n- [[page1|Page 1]]\n"
          result = addUpdateLinks content ImageUpdate
                     [UpdateLink "page1.md" "Page 1"]
      in assertEqual "should not change content" content result

  , testCase "returns content unchanged for empty links" $
      let content = "# My Reflection\n\nSome content"
          result = addUpdateLinks content ImageUpdate []
      in assertEqual "should not change" content result

  , testCase "multiple categories in same content" $
      let content0 = "# My Reflection\n\nSome content"
          content1 = addUpdateLinks content0 ImageUpdate
                       [UpdateLink "img-page.md" "Image Page"]
          content2 = addUpdateLinks content1 SocialPostUpdate
                       [UpdateLink "social-page.md" "Social Page"]
          content3 = addUpdateLinks content2 InternalLinkUpdate
                       [UpdateLink "link-page.md" "Link Page"]
      in do
        assertBool "has image sub-header" (T.isInfixOf "### 🖼️ Images" content3)
        assertBool "has social sub-header" (T.isInfixOf "### 📢 Social Posts" content3)
        assertBool "has internal links sub-header" (T.isInfixOf "### 🔗 Internal Links" content3)
        assertBool "has image link" (T.isInfixOf "[[img-page|Image Page]]" content3)
        assertBool "has social link" (T.isInfixOf "[[social-page|Social Page]]" content3)
        assertBool "has internal link" (T.isInfixOf "[[link-page|Link Page]]" content3)

  , testCase "preserves content after updates section" $
      let content = "# My Reflection\n\n## 🔄 Updates\n\n### 🖼️ Images\n\n- [[p1|P1]]\n\n## 📚 Books\n\nSome books"
          result = addUpdateLinks content SocialPostUpdate
                     [UpdateLink "sp.md" "SP"]
      in do
        assertBool "should preserve books section"
          (T.isInfixOf "## 📚 Books" result)
        assertBool "should preserve books content"
          (T.isInfixOf "Some books" result)
        assertBool "should add social link"
          (T.isInfixOf "[[sp|SP]]" result)

  , testCase "adds multiple links at once" $
      let content = "# Reflection"
          result = addUpdateLinks content ImageUpdate
                     [ UpdateLink "a.md" "Page A"
                     , UpdateLink "b.md" "Page B"
                     , UpdateLink "c.md" "Page C"
                     ]
      in do
        assertBool "has A" (T.isInfixOf "[[a|Page A]]" result)
        assertBool "has B" (T.isInfixOf "[[b|Page B]]" result)
        assertBool "has C" (T.isInfixOf "[[c|Page C]]" result)

  , testCase "inserts updates section before social media sections" $
      let content = "# My Reflection\n\nBody text\n\n## 🐦 Tweet\n\nTweet embed"
          result = addUpdateLinks content ImageUpdate
                     [UpdateLink "img.md" "Image Page"]
      in do
        assertBool "has updates header" (T.isInfixOf "## 🔄 Updates" result)
        assertBool "has image link" (T.isInfixOf "[[img|Image Page]]" result)
        assertBool "updates before tweet" $
          let uIdx = T.length $ fst $ T.breakOn "## 🔄 Updates" result
              tIdx = T.length $ fst $ T.breakOn "## 🐦 Tweet" result
          in uIdx < tIdx

  , testCase "inserts updates section before bluesky section" $
      let content = "# My Reflection\n\nBody text\n\n## 🦋 Bluesky\n\nBluesky embed"
          result = addUpdateLinks content ImageUpdate
                     [UpdateLink "img.md" "Image Page"]
      in assertBool "updates before bluesky" $
          let uIdx = T.length $ fst $ T.breakOn "## 🔄 Updates" result
              bIdx = T.length $ fst $ T.breakOn "## 🦋 Bluesky" result
          in uIdx < bIdx

  , testProperty "addUpdateLinks never removes existing lines" $
      \(QC.ASCIIString bodyStr) ->
        let body = T.pack bodyStr
            content = "# Reflection\n\n" <> body <> "\n\nSome footer"
            result = addUpdateLinks content ImageUpdate
                       [UpdateLink "test.md" "Test"]
        in T.isInfixOf "Some footer" result
  ]

--------------------------------------------------------------------------------
-- addUpdateLinksToReflection (IO function)
--------------------------------------------------------------------------------

addUpdateLinksToReflectionTests :: TestTree
addUpdateLinksToReflectionTests = testGroup "addUpdateLinksToReflection"
  [ testCase "creates reflection and adds categorized links" $
      withSystemTempDirectory "daily-updates-test" $ \tmpDir -> do
        let reflDir = tmpDir </> "reflections"
        createDirectoryIfMissing True reflDir

        TIO.writeFile (reflDir </> "2026-03-28.md") "---\ntitle: 2026-03-28\n---\n\n# Reflection\n"

        modified <- addUpdateLinksToReflection reflDir "2026-03-28" ImageUpdate
                      [UpdateLink "ai-blog/post.md" "A Post"]
        assertBool "should report modification" modified

        content <- TIO.readFile (reflDir </> "2026-03-28.md")
        assertBool "has updates header" (T.isInfixOf "## 🔄 Updates" content)
        assertBool "has image sub-header" (T.isInfixOf "### 🖼️ Images" content)
        assertBool "has link" (T.isInfixOf "[[ai-blog/post|A Post]]" content)

  , testCase "returns false when links already present" $
      withSystemTempDirectory "daily-updates-test" $ \tmpDir -> do
        let reflDir = tmpDir </> "reflections"
        createDirectoryIfMissing True reflDir

        TIO.writeFile (reflDir </> "2026-03-28.md") $
          "---\ntitle: 2026-03-28\n---\n\n## 🔄 Updates\n\n### 🖼️ Images\n\n- [[ai-blog/post|A Post]]\n"

        modified <- addUpdateLinksToReflection reflDir "2026-03-28" ImageUpdate
                      [UpdateLink "ai-blog/post.md" "A Post"]
        assertBool "should report no modification" (not modified)

  , testCase "returns false for empty links" $
      withSystemTempDirectory "daily-updates-test" $ \tmpDir -> do
        let reflDir = tmpDir </> "reflections"
        createDirectoryIfMissing True reflDir

        modified <- addUpdateLinksToReflection reflDir "2026-03-28" ImageUpdate []
        assertBool "should report no modification" (not modified)

  , testCase "different categories create separate sub-sections" $
      withSystemTempDirectory "daily-updates-test" $ \tmpDir -> do
        let reflDir = tmpDir </> "reflections"
        createDirectoryIfMissing True reflDir

        TIO.writeFile (reflDir </> "2026-03-28.md") "---\ntitle: 2026-03-28\n---\n\n# Reflection\n"

        _ <- addUpdateLinksToReflection reflDir "2026-03-28" ImageUpdate
               [UpdateLink "img.md" "Image Page"]
        _ <- addUpdateLinksToReflection reflDir "2026-03-28" SocialPostUpdate
               [UpdateLink "social.md" "Social Page"]

        content <- TIO.readFile (reflDir </> "2026-03-28.md")
        assertBool "has image sub-header" (T.isInfixOf "### 🖼️ Images" content)
        assertBool "has social sub-header" (T.isInfixOf "### 📢 Social Posts" content)
        assertBool "has image link" (T.isInfixOf "[[img|Image Page]]" content)
        assertBool "has social link" (T.isInfixOf "[[social|Social Page]]" content)

  , testCase "link in body does NOT prevent adding update link" $
      let content = T.unlines
            [ "# 2026-04-03"
            , ""
            , "## 📺 Videos"
            , "- [[videos/backyard-fruit-trees|🏡🌳🍎 Backyard Fruit Trees]]"
            , ""
            , "## 🔄 Updates"
            , ""
            , "### 🖼️ Images"
            , ""
            , "- [[ai-blog/some-post|Some Post]]"
            ]
          result = addUpdateLinks content SocialPostUpdate
                     [UpdateLink "videos/backyard-fruit-trees.md" "🏡🌳🍎 Backyard Fruit Trees"]
      in do
        assertBool "should contain social posts sub-header"
          (T.isInfixOf "### 📢 Social Posts" result)
        assertBool "should contain social post link in updates section"
          (T.isInfixOf "- [[videos/backyard-fruit-trees|🏡🌳🍎 Backyard Fruit Trees]]" result)

  , testCase "duplicate within updates section is still skipped" $
      let content = T.unlines
            [ "# 2026-04-03"
            , ""
            , "## 🔄 Updates"
            , ""
            , "### 📢 Social Posts"
            , ""
            , "- [[videos/backyard-fruit-trees|🏡🌳🍎 Backyard Fruit Trees]]"
            ]
          result = addUpdateLinks content SocialPostUpdate
                     [UpdateLink "videos/backyard-fruit-trees.md" "🏡🌳🍎 Backyard Fruit Trees"]
      in assertEqual "should not change content" content result
  ]
