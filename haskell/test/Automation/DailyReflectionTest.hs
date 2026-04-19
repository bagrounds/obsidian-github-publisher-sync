module Automation.DailyReflectionTest (tests) where

import qualified Data.Text as T
import Data.Time (fromGregorian)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import Test.Tasty.QuickCheck (testProperty)
import qualified Test.Tasty.QuickCheck as QC
import Data.Time.LocalTime (TimeOfDay (..))

import Automation.AiBlogLinks (aiBlogConfig)
import Automation.BlogSeriesConfig (BlogSeriesConfig (..))
import Automation.DailyReflection
import Automation.PacificTime (formatDay)
import Automation.TestGenerators (testTitle)

tests :: TestTree
tests = testGroup "DailyReflection"
  [ buildReflectionContentTests
  , buildSeriesSectionHeadingTests
  , buildPostLinkTests
  , addForwardLinkTests
  , insertPostLinkTests
  , aiBlogSectionTests
  , propertyTests
  ]

sampleSeries :: BlogSeriesConfig
sampleSeries = BlogSeriesConfig
  { bscId           = "auto-blog-zero"
  , bscName         = "Auto Blog Zero"
  , bscIcon         = "🤖"
  , bscAuthor       = "[[auto-blog-zero]]"
  , bscBaseUrl      = "https://bagrounds.org/auto-blog-zero"
  , bscPriorityUser = Just "bagrounds"
  , bscNavLink      = "[[index|Home]] > [[auto-blog-zero/index|🤖 Auto Blog Zero]]"
  , bscScheduleTime = TimeOfDay 8 0 0
  , bscContextQueries = []
  }

--------------------------------------------------------------------------------
-- buildReflectionContent
--------------------------------------------------------------------------------

buildReflectionContentTests :: TestTree
buildReflectionContentTests = testGroup "buildReflectionContent"
  [ testCase "generates frontmatter with date" $
      let result = buildReflectionContent (fromGregorian 2026 4 1) Nothing
      in do
        assertBool "starts with frontmatter" (T.isPrefixOf "---" result)
        assertBool "contains share: true" (T.isInfixOf "share: true" result)
        assertBool "contains date in title" (T.isInfixOf "2026-04-01" result)
        assertBool "contains URL" (T.isInfixOf "https://bagrounds.org/reflections/2026-04-01" result)
  , testCase "generates heading with date" $
      let result = buildReflectionContent (fromGregorian 2026 4 1) Nothing
      in assertBool "contains h1 with date" (T.isInfixOf "# 2026-04-01" result)
  , testCase "includes nav breadcrumb" $
      let result = buildReflectionContent (fromGregorian 2026 4 1) Nothing
      in assertBool "contains Home nav" (T.isInfixOf "[[index|Home]]" result)
  , testCase "no backlink when no previous date" $
      let result = buildReflectionContent (fromGregorian 2026 4 1) Nothing
      in assertBool "no back arrow" (not (T.isInfixOf "⏮️" result))
  , testCase "includes backlink when previous date provided" $
      let result = buildReflectionContent (fromGregorian 2026 4 1) (Just "2026-03-31")
      in do
        assertBool "has back arrow" (T.isInfixOf "⏮️" result)
        assertBool "links to previous date" (T.isInfixOf "reflections/2026-03-31" result)
  , testCase "includes Author field" $
      let result = buildReflectionContent (fromGregorian 2026 4 1) Nothing
      in assertBool "contains Author" (T.isInfixOf "Author:" result)
  , testCase "includes changes link at the bottom" $
      let result = buildReflectionContent (fromGregorian 2026 4 1) Nothing
      in assertBool "contains changes link" (T.isInfixOf "## [[changes/2026-04-01|\128260 Changes]]" result)
  , testCase "changes link is after heading" $
      let result = buildReflectionContent (fromGregorian 2026 4 1) Nothing
          headingIdx = T.length $ fst $ T.breakOn "# 2026-04-01" result
          changesIdx = T.length $ fst $ T.breakOn "## [[changes/2026-04-01|\128260 Changes]]" result
      in assertBool "changes link after heading" (changesIdx > headingIdx)
  ]

--------------------------------------------------------------------------------
-- buildSeriesSectionHeading
--------------------------------------------------------------------------------

buildSeriesSectionHeadingTests :: TestTree
buildSeriesSectionHeadingTests = testGroup "buildSeriesSectionHeading"
  [ testCase "formats heading with icon and name" $
      let result = buildSeriesSectionHeading sampleSeries
      in do
        assertBool "starts with ##" (T.isPrefixOf "## " result)
        assertBool "contains series name" (T.isInfixOf "Auto Blog Zero" result)
        assertBool "contains wikilink to index" (T.isInfixOf "auto-blog-zero/index" result)
  ]

--------------------------------------------------------------------------------
-- buildPostLink
--------------------------------------------------------------------------------

buildPostLinkTests :: TestTree
buildPostLinkTests = testGroup "buildPostLink"
  [ testCase "formats list item with wikilink" $
      buildPostLink "auto-blog-zero" "my-post" (testTitle "My Post Title")
        @?= "- [[auto-blog-zero/my-post|My Post Title]]"
  , testCase "handles special characters in title" $
      let result = buildPostLink "chickie-loo" "fancy-post" (testTitle "A Post: With Colon")
      in assertBool "contains title" (T.isInfixOf "A Post: With Colon" result)
  , testCase "preserves emojis in display title for blog series" $
      buildPostLink "the-noise" "2026-04-14-my-post" (testTitle "2026-04-14 | 📰 My Post 📰")
        @?= "- [[the-noise/2026-04-14-my-post|2026-04-14 | 📰 My Post 📰]]"
  , testCase "preserves emojis in display title for auto-blog-zero" $
      buildPostLink "auto-blog-zero" "2026-04-14-my-post" (testTitle "2026-04-14 | 🤖 My Post 🤖")
        @?= "- [[auto-blog-zero/2026-04-14-my-post|2026-04-14 | 🤖 My Post 🤖]]"
  ]

--------------------------------------------------------------------------------
-- addForwardLink
--------------------------------------------------------------------------------

addForwardLinkTests :: TestTree
addForwardLinkTests = testGroup "addForwardLink"
  [ testCase "adds forward link after existing back link" $
      let content = "[[index|Home]] > [[reflections/index|Reflections]] | [[reflections/2026-03-31|⏮️]]\n# 2026-04-01"
          result = addForwardLink content "2026-04-02"
      in do
        assertBool "contains forward arrow" (T.isInfixOf "⏭️" result)
        assertBool "links to target date" (T.isInfixOf "reflections/2026-04-02" result)
  , testCase "does not add duplicate forward link" $
      let content = "[[reflections/2026-03-31|⏮️]] [[reflections/2026-04-02|⏭️]]\n# Post"
          result = addForwardLink content "2026-04-03"
      in result @?= content
  , testCase "adds forward link when no back link present" $
      let content = "[[index|Home]] > [[reflections/index|Reflections]]\n# Post"
          result = addForwardLink content "2026-04-02"
      in do
        assertBool "contains forward arrow" (T.isInfixOf "⏭️" result)
        assertBool "links to target date" (T.isInfixOf "reflections/2026-04-02" result)
  ]

--------------------------------------------------------------------------------
-- insertPostLink
--------------------------------------------------------------------------------

insertPostLinkTests :: TestTree
insertPostLinkTests = testGroup "insertPostLink"
  [ testCase "creates new section when not present" $
      let content = "# 2026-04-01\n\nSome reflection"
          result = insertPostLink content sampleSeries "my-post" (testTitle "My Post") Nothing
      in do
        assertBool "contains section heading" (T.isInfixOf (buildSeriesSectionHeading sampleSeries) result)
        assertBool "contains post link" (T.isInfixOf "[[auto-blog-zero/my-post|My Post]]" result)
  , testCase "appends to existing section" $
      let heading = buildSeriesSectionHeading sampleSeries
          content = "# 2026-04-01\n\n" <> heading <> "\n- [[auto-blog-zero/old-post|Old Post]]\n"
          result = insertPostLink content sampleSeries "new-post" (testTitle "New Post") Nothing
      in do
        assertBool "contains old link" (T.isInfixOf "[[auto-blog-zero/old-post|Old Post]]" result)
        assertBool "contains new link" (T.isInfixOf "[[auto-blog-zero/new-post|New Post]]" result)
  , testCase "does not insert duplicate link" $
      let heading = buildSeriesSectionHeading sampleSeries
          content = "# 2026-04-01\n\n" <> heading <> "\n- [[auto-blog-zero/my-post|My Post]]\n"
          result = insertPostLink content sampleSeries "my-post" (testTitle "My Post") Nothing
      in result @?= content
  , testCase "replaces old link when replacingFilenameNoExt given" $
      let heading = buildSeriesSectionHeading sampleSeries
          content = "# 2026-04-01\n\n" <> heading <> "\n- [[auto-blog-zero/old-name|Old Title]]\n"
          result = insertPostLink content sampleSeries "new-name" (testTitle "New Title") (Just "old-name")
      in do
        assertBool "old link replaced" (not (T.isInfixOf "old-name" result))
        assertBool "new link present" (T.isInfixOf "[[auto-blog-zero/new-name|New Title]]" result)
  , testCase "inserts new section before embed sections" $
      let content = "# 2026-04-01\n\nBody\n\n## 🐦 Tweet\n\nTweet embed"
          result = insertPostLink content sampleSeries "post" (testTitle "Post") Nothing
      in do
        assertBool "section before tweet" $
          let sIdx = T.length $ fst $ T.breakOn (buildSeriesSectionHeading sampleSeries) result
              tIdx = T.length $ fst $ T.breakOn "## 🐦 Tweet" result
          in sIdx < tIdx
  , testCase "inserts new section before updates section" $
      let content = "# 2026-04-01\n\nBody\n\n## 🔄 Updates\n\n### 🖼️ Images\n\n- [[img|Img]]"
          result = insertPostLink content sampleSeries "post" (testTitle "Post") Nothing
      in do
        assertBool "section before updates" $
          let sIdx = T.length $ fst $ T.breakOn (buildSeriesSectionHeading sampleSeries) result
              uIdx = T.length $ fst $ T.breakOn "## 🔄 Updates" result
          in sIdx < uIdx
  , testCase "inserts new section before both updates and embed sections" $
      let content = "# 2026-04-01\n\nBody\n\n## 🔄 Updates\n\n### 🖼️ Images\n\n- [[img|Img]]\n\n## 🐦 Tweet\n\nTweet embed"
          result = insertPostLink content sampleSeries "post" (testTitle "Post") Nothing
      in do
        let sIdx = T.length $ fst $ T.breakOn (buildSeriesSectionHeading sampleSeries) result
            uIdx = T.length $ fst $ T.breakOn "## 🔄 Updates" result
            tIdx = T.length $ fst $ T.breakOn "## 🐦 Tweet" result
        assertBool "section before updates" (sIdx < uIdx)
        assertBool "updates before tweet" (uIdx < tIdx)
  , testCase "appends section at end when no embed sections" $
      let content = "# 2026-04-01\n\nBody text"
          result = insertPostLink content sampleSeries "post" (testTitle "Post") Nothing
      in assertBool "contains post link" (T.isInfixOf "[[auto-blog-zero/post|Post]]" result)
  , testCase "inserts new section before changes link without splitting H2" $
      let content = "# 2026-04-01\n\nBody\n\n## [[changes/2026-04-01|\128260 Changes]]\n"
          result = insertPostLink content sampleSeries "post" (testTitle "Post") Nothing
      in do
        assertBool "changes link retains H2 prefix" (T.isInfixOf "## [[changes/2026-04-01|" result)
        assertBool "no orphaned H2" (not $ T.isInfixOf "\n##\n" result)
        assertBool "no orphaned H2 at line end" (not $ T.isInfixOf "\n## \n" result)
        assertBool "section before changes link" $
          let sIdx = T.length $ fst $ T.breakOn (buildSeriesSectionHeading sampleSeries) result
              cIdx = T.length $ fst $ T.breakOn "## [[changes/" result
          in sIdx < cIdx
  ]

--------------------------------------------------------------------------------
-- AI blog section tests
--------------------------------------------------------------------------------

aiBlogSectionTests :: TestTree
aiBlogSectionTests = testGroup "AI blog section"
  [ testCase "creates AI Blog section heading with correct format" $
      buildSeriesSectionHeading aiBlogConfig @?= "## [[ai-blog/index|🤖 AI Blog]]"
  , testCase "creates AI blog post link with correct format" $
      buildPostLink "ai-blog" "2026-04-01-1-my-post" (testTitle "2026-04-01 | My Post 🤖")
        @?= "- [[ai-blog/2026-04-01-1-my-post|2026-04-01 | My Post 🤖]]"
  , testCase "insertPostLink creates AI Blog section in reflection" $
      let content = "# 2026-04-01\n\nSome reflection content"
          result = insertPostLink content aiBlogConfig "2026-04-01-1-my-post" (testTitle "2026-04-01 | My Post 🤖") Nothing
      in do
        assertBool "contains AI Blog section" (T.isInfixOf "## [[ai-blog/index|🤖 AI Blog]]" result)
        assertBool "contains post link" (T.isInfixOf "[[ai-blog/2026-04-01-1-my-post|" result)
  , testCase "AI Blog section inserted before Updates section" $
      let content = "# 2026-04-01\n\nBody\n\n## 🔄 Updates\n\n### 🖼️ Images\n\n- [[img|Img]]"
          result = insertPostLink content aiBlogConfig "2026-04-01-1-post" (testTitle "Post Title") Nothing
      in do
        let aIdx = T.length $ fst $ T.breakOn "## [[ai-blog/index|🤖 AI Blog]]" result
            uIdx = T.length $ fst $ T.breakOn "## 🔄 Updates" result
        assertBool "AI Blog section before Updates" (aIdx < uIdx)
  , testCase "AI Blog section inserted before social embed sections" $
      let content = "# 2026-04-01\n\nBody\n\n## 🐦 Tweet\n\nTweet embed"
          result = insertPostLink content aiBlogConfig "2026-04-01-1-post" (testTitle "Post Title") Nothing
      in do
        let aIdx = T.length $ fst $ T.breakOn "## [[ai-blog/index|🤖 AI Blog]]" result
            tIdx = T.length $ fst $ T.breakOn "## 🐦 Tweet" result
        assertBool "AI Blog section before Tweet" (aIdx < tIdx)
  , testCase "AI Blog section coexists with blog series section" $
      let heading = buildSeriesSectionHeading sampleSeries
          content = "# 2026-04-01\n\n" <> heading <> "\n- [[auto-blog-zero/post|Post]]"
          result = insertPostLink content aiBlogConfig "2026-04-01-1-ai-post" (testTitle "AI Post") Nothing
      in do
        assertBool "contains series section" (T.isInfixOf "Auto Blog Zero" result)
        assertBool "contains AI Blog section" (T.isInfixOf "## [[ai-blog/index|🤖 AI Blog]]" result)
        assertBool "contains AI blog link" (T.isInfixOf "[[ai-blog/2026-04-01-1-ai-post|AI Post]]" result)
  , testCase "appends to existing AI Blog section" $
      let heading = buildSeriesSectionHeading aiBlogConfig
          content = "# 2026-04-01\n\n" <> heading <> "\n- [[ai-blog/2026-04-01-1-first|First Post]]"
          result = insertPostLink content aiBlogConfig "2026-04-01-2-second" (testTitle "Second Post") Nothing
      in do
        assertBool "contains first link" (T.isInfixOf "[[ai-blog/2026-04-01-1-first|First Post]]" result)
        assertBool "contains second link" (T.isInfixOf "[[ai-blog/2026-04-01-2-second|Second Post]]" result)
  , testCase "idempotent: does not insert duplicate AI blog link" $
      let heading = buildSeriesSectionHeading aiBlogConfig
          content = "# 2026-04-01\n\n" <> heading <> "\n- [[ai-blog/2026-04-01-1-post|Post Title]]"
          result = insertPostLink content aiBlogConfig "2026-04-01-1-post" (testTitle "Post Title") Nothing
      in result @?= content
  ]

--------------------------------------------------------------------------------
-- property tests
--------------------------------------------------------------------------------

propertyTests :: TestTree
propertyTests = testGroup "properties"
  [ testProperty "buildReflectionContent always contains the formatted date" $
      \year month dayNum ->
        let day = fromGregorian year (abs month `mod` 12 + 1) (abs dayNum `mod` 28 + 1)
            result = buildReflectionContent day Nothing
        in T.isInfixOf (formatDay day) result
  , testProperty "addForwardLink is idempotent" $
      \(QC.ASCIIString dateStr) ->
        let date = T.pack dateStr
            content = "nav | [[reflections/prev|⏮️]]\n# Post"
            once = addForwardLink content date
            twice = addForwardLink once date
        in once == twice
  , testProperty "addForwardLink is idempotent without back link" $
      \(QC.ASCIIString dateStr) ->
        let date = T.pack dateStr
            content = "[[index|Home]] > [[reflections/index|Reflections]]\n# Post"
            once = addForwardLink content date
            twice = addForwardLink once date
        in once == twice
  , testProperty "insertPostLink is idempotent" $
      \(QC.ASCIIString slug) ->
        let filenameNoExt = T.pack slug
            content = "# 2026-04-01\n\nBody"
            once = insertPostLink content sampleSeries filenameNoExt (testTitle "Title") Nothing
            twice = insertPostLink once sampleSeries filenameNoExt (testTitle "Title") Nothing
        in once == twice
  ]
