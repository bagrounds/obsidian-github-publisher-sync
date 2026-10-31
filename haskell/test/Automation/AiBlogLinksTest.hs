module Automation.AiBlogLinksTest (tests) where

import qualified Data.Text as T
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import Test.Tasty.QuickCheck (testProperty)
import qualified Test.Tasty.QuickCheck as QC

import System.FilePath ((</>))
import qualified Data.Text.IO as TIO
import System.IO.Temp (withSystemTempDirectory)

import Automation.AiBlogLinks
import Automation.BlogSeriesConfig (BlogSeriesConfig (..))
import Automation.Title (unTitle)

tests :: TestTree
tests = testGroup "AiBlogLinks"
  [ constantTests
  , aiBlogConfigTests
  , buildNavLineTests
  , updateNavLinksTests
  , normalizeNavLineTests
  , navLinksMatchTests
  , extractPostDateTests
  , buildReflectionLinksTests
  , propertyTests
  ]

constantTests :: TestTree
constantTests = testGroup "constants"
  [ testCase "aiBlogNavPrefix starts with Home link" $
      assertBool "starts with [[index|" (T.isPrefixOf "[[index|" aiBlogNavPrefix)
  , testCase "aiBlogNavPrefix contains AI Blog link" $
      assertBool "contains AI Blog" (T.isInfixOf "AI Blog" aiBlogNavPrefix)
  ]

aiBlogConfigTests :: TestTree
aiBlogConfigTests = testGroup "aiBlogConfig"
  [ testCase "has ai-blog as id" $
      identifier aiBlogConfig @?= "ai-blog"
  , testCase "has robot emoji as icon" $
      icon aiBlogConfig @?= "🤖"
  , testCase "has AI Blog as name" $
      name aiBlogConfig @?= "AI Blog"
  ]

buildNavLineTests :: TestTree
buildNavLineTests = testGroup "buildNavLine"
  [ testCase "no previous, no next" $
      buildNavLine Nothing Nothing @?= aiBlogNavPrefix
  , testCase "previous only" $
      let result = buildNavLine (Just "prev.md") Nothing
      in do
        assertBool "starts with prefix" (T.isPrefixOf aiBlogNavPrefix result)
        assertBool "contains back link" (T.isInfixOf "⏮️" result)
        assertBool "no forward link" (not (T.isInfixOf "⏭️" result))
  , testCase "next only" $
      let result = buildNavLine Nothing (Just "next.md")
      in do
        assertBool "starts with prefix" (T.isPrefixOf aiBlogNavPrefix result)
        assertBool "contains forward link" (T.isInfixOf "⏭️" result)
        assertBool "no back link" (not (T.isInfixOf "⏮️" result))
  , testCase "both previous and next" $
      let result = buildNavLine (Just "prev.md") (Just "next.md")
      in do
        assertBool "starts with prefix" (T.isPrefixOf aiBlogNavPrefix result)
        assertBool "contains back link" (T.isInfixOf "⏮️" result)
        assertBool "contains forward link" (T.isInfixOf "⏭️" result)
        assertBool "has separator" (T.isInfixOf " | " result)
  , testCase "both links have correct structure" $
      let result = buildNavLine (Just "2026-01-01-1-a.md") (Just "2026-01-03-1-c.md")
      in do
        assertBool "back link path" (T.isInfixOf "[[ai-blog/2026-01-01-1-a|⏮️]]" result)
        assertBool "forward link path" (T.isInfixOf "[[ai-blog/2026-01-03-1-c|⏭️]]" result)
  ]

updateNavLinksTests :: TestTree
updateNavLinksTests = testGroup "updateNavLinks"
  [ testCase "updates existing nav line" $
      let content = aiBlogNavPrefix <> "\n# My Post\n\nBody"
          result = updateNavLinks content (Just "prev.md") Nothing
      in do
        assertBool "contains updated nav" (T.isInfixOf "⏮️" result)
        assertBool "contains body" (T.isInfixOf "Body" result)
  , testCase "returns content unchanged when no nav prefix found" $
      let content = "# No Nav Here\n\nBody"
          result = updateNavLinks content (Just "prev.md") Nothing
      in result @?= content
  , testCase "returns content unchanged when nav already matches" $
      let navLine = buildNavLine (Just "prev.md") (Just "next.md")
          content = navLine <> "\n# Post\n\nBody"
          result = updateNavLinks content (Just "prev.md") (Just "next.md")
      in result @?= content
  , testCase "replaces old nav line with new one" $
      let oldNav = buildNavLine (Just "old-prev.md") Nothing
          content = oldNav <> "\n# Post\n\nBody"
          result = updateNavLinks content (Just "new-prev.md") (Just "new-next.md")
      in do
        assertBool "has new back link" (T.isInfixOf "new-prev" result)
        assertBool "has new forward link" (T.isInfixOf "new-next" result)
        assertBool "old link removed" (not (T.isInfixOf "old-prev" result))
  , testCase "preserves content before and after nav line" $
      let content = "---\ntitle: Test\n---\n" <> aiBlogNavPrefix <> "\n# My Post\n\nBody text here"
          result = updateNavLinks content (Just "p.md") Nothing
      in do
        assertBool "preserves frontmatter" (T.isInfixOf "title: Test" result)
        assertBool "preserves body" (T.isInfixOf "Body text here" result)
  ]

dominationFrontmatter :: T.Text
dominationFrontmatter = T.unlines
  [ "---"
  , "share: true"
  , "title: 2026-10-30 | 💬 Tooltips That Stay on Screen ⚓"
  , "URL: https://bagrounds.org/ai-blog/2026-10-30-tooltips-that-stay-on-screen"
  , "tags:"
  , "---"
  ]

normalizeNavLineTests :: TestTree
normalizeNavLineTests = testGroup "normalizeNavLine"
  [ testCase "replaces a markdown nav line with the wiki nav prefix" $
      let content = dominationFrontmatter
            <> "[🏠 Home](../) > [🤖 AI Blog](./) | [⏮️ 2026-10-30 | 🤖 Bots](./2026-10-30-finishing-the-bot-players)\n"
            <> "\n# 💬 2026-10-30 | Tooltips That Stay on Screen ⚓\n\nBody\n"
      in normalizeNavLine content @?= dominationFrontmatter
            <> aiBlogNavPrefix <> "\n"
            <> "\n# 💬 2026-10-30 | Tooltips That Stay on Screen ⚓\n\nBody\n"
  , testCase "replaces a markdown nav line using the garden house emoji" $
      let content = dominationFrontmatter <> "[🏡 Home](../index.md) > [🤖 AI Blog](./index.md)\n# Post\n"
      in normalizeNavLine content @?= dominationFrontmatter <> aiBlogNavPrefix <> "\n# Post\n"
  , testCase "inserts the nav prefix directly after frontmatter when missing" $
      let content = dominationFrontmatter <> "# 2026-03-11 | 🏗️ From GitLab to GitHub 🤖\n\nBody\n"
      in normalizeNavLine content @?= dominationFrontmatter
            <> aiBlogNavPrefix <> "\n# 2026-03-11 | 🏗️ From GitLab to GitHub 🤖\n\nBody\n"
  , testCase "inserts the nav prefix at the top when there is no frontmatter" $
      normalizeNavLine "# Post\n\nBody" @?= aiBlogNavPrefix <> "\n# Post\n\nBody"
  , testCase "inserts the nav prefix on its own line after frontmatter without a trailing newline" $
      normalizeNavLine "---\ntitle: Test\n---" @?= "---\ntitle: Test\n---\n" <> aiBlogNavPrefix <> "\n"
  , testCase "keeps blank lines that precede the replaced markdown nav line" $
      let content = dominationFrontmatter <> "\n[🏠 Home](../) > [🤖 AI Blog](./)\n# Post"
      in normalizeNavLine content @?= dominationFrontmatter <> "\n" <> aiBlogNavPrefix <> "\n# Post"
  , testCase "leaves content with a wiki nav line unchanged" $
      let content = dominationFrontmatter <> buildNavLine (Just "prev.md") Nothing <> "\n# Post\n"
      in normalizeNavLine content @?= content
  , testCase "does not replace a markdown Home link deeper in the body" $
      let content = dominationFrontmatter <> "# Post\n\n[🏠 Home](../) is where the heart is\n"
      in normalizeNavLine content @?= dominationFrontmatter <> aiBlogNavPrefix <> "\n" <> "# Post\n\n[🏠 Home](../) is where the heart is\n"
  , testCase "keeps the reversed-emoji H1 of a domination post as-is" $
      let heading = "# 💬 2026-10-30 | Tooltips That Stay on Screen ⚓"
          content = dominationFrontmatter <> "[🏠 Home](../) > [🤖 AI Blog](./)\n\n" <> heading <> "\n"
      in assertBool "heading preserved" (heading `elem` T.lines (normalizeNavLine content))
  , testCase "normalized post gets full prev/next nav from updateNavLinks" $
      let content = dominationFrontmatter <> "[🏠 Home](../) > [🤖 AI Blog](./) | [⏮️ Old](./old)\n# Post\n"
          updated = updateNavLinks (normalizeNavLine content) (Just "2026-10-29-1-a.md") (Just "2026-10-31-1-b.md")
      in do
        navLinksMatch updated (Just "2026-10-29-1-a.md") (Just "2026-10-31-1-b.md") @?= True
        assertBool "markdown nav removed" (not (T.isInfixOf "](./old)" updated))
  ]

navLinksMatchTests :: TestTree
navLinksMatchTests = testGroup "navLinksMatch"
  [ testCase "matches when nav line is correct" $
      let navLine = buildNavLine (Just "prev.md") (Just "next.md")
          content = "before\n" <> navLine <> "\nafter"
      in navLinksMatch content (Just "prev.md") (Just "next.md") @?= True
  , testCase "does not match when nav line differs" $
      let navLine = buildNavLine (Just "old.md") Nothing
          content = "before\n" <> navLine <> "\nafter"
      in navLinksMatch content (Just "new.md") Nothing @?= False
  , testCase "matches with no links" $
      let content = "before\n" <> aiBlogNavPrefix <> "\nafter"
      in navLinksMatch content Nothing Nothing @?= True
  , testCase "does not match when no nav line present" $
      navLinksMatch "no nav here" Nothing Nothing @?= False
  ]

extractPostDateTests :: TestTree
extractPostDateTests = testGroup "extractPostDate"
  [ testCase "extracts date from standard filename" $
      extractPostDate "2026-03-28-1-my-post.md" @?= Just "2026-03-28"
  , testCase "extracts date from date-only filename" $
      extractPostDate "2026-03-28.md" @?= Just "2026-03-28"
  , testCase "returns Nothing for short filename" $
      extractPostDate "short.md" @?= Nothing
  , testCase "returns Nothing for invalid format" $
      extractPostDate "abcdefghij.md" @?= Nothing
  , testCase "returns Nothing for empty filename" $
      extractPostDate "" @?= Nothing
  , testCase "returns Nothing when dashes in wrong place" $
      extractPostDate "20260328ab.md" @?= Nothing
  ]

buildReflectionLinksTests :: TestTree
buildReflectionLinksTests = testGroup "buildReflectionLinks"
  [ testCase "includes unmodified posts in reflection links" $
      withSystemTempDirectory "ai-blog-test" $ \temporaryDirectory -> do
        let postFile = temporaryDirectory </> "2026-04-03-1-my-post.md"
        TIO.writeFile postFile "---\ntitle: \"My Post Title\"\n---\n[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]\n# My Post"
        let results =
              [ NavLinkResult { filename = "2026-04-03-1-my-post.md", modified = False }
              ]
        links <- buildReflectionLinks temporaryDirectory results
        assertBool "should include unmodified post" (length links == 1)
        case links of
          ((relPath, title, date):_) -> do
            relPath @?= "ai-blog/2026-04-03-1-my-post.md"
            unTitle title @?= "My Post Title"
            date @?= "2026-04-03"
          [] -> assertBool "should have at least one link" False
  , testCase "includes both modified and unmodified posts" $
      withSystemTempDirectory "ai-blog-test" $ \temporaryDirectory -> do
        TIO.writeFile (temporaryDirectory </> "2026-04-01-1-old.md") "---\ntitle: \"Old Post\"\n---\nContent"
        TIO.writeFile (temporaryDirectory </> "2026-04-03-1-new.md") "---\ntitle: \"New Post\"\n---\nContent"
        let results =
              [ NavLinkResult { filename = "2026-04-01-1-old.md", modified = True }
              , NavLinkResult { filename = "2026-04-03-1-new.md", modified = False }
              ]
        links <- buildReflectionLinks temporaryDirectory results
        assertBool "should include both posts" (length links == 2)
  , testCase "still filters out posts without valid dates" $
      withSystemTempDirectory "ai-blog-test" $ \temporaryDirectory -> do
        TIO.writeFile (temporaryDirectory </> "no-date.md") "---\ntitle: \"No Date\"\n---\nContent"
        let results =
              [ NavLinkResult { filename = "no-date.md", modified = False }
              ]
        links <- buildReflectionLinks temporaryDirectory results
        assertBool "should exclude posts without valid dates" (null links)
  ]

propertyTests :: TestTree
propertyTests = testGroup "properties"
  [ testProperty "buildNavLine always starts with aiBlogNavPrefix" $
      \(QC.ASCIIString prev) (QC.ASCIIString next) ->
        let prev' = filter (\character -> character /= '\n' && character /= '\r') prev
            next' = filter (\character -> character /= '\n' && character /= '\r') next
            prevM = if null prev' then Nothing else Just (T.pack prev' <> ".md")
            nextM = if null next' then Nothing else Just (T.pack next' <> ".md")
        in T.isPrefixOf aiBlogNavPrefix (buildNavLine prevM nextM)
  , testProperty "navLinksMatch agrees with buildNavLine" $
      \(QC.ASCIIString prev) (QC.ASCIIString next) ->
        let prev' = filter (\character -> character /= '\n' && character /= '\r') prev
            next' = filter (\character -> character /= '\n' && character /= '\r') next
            prevM = if null prev' then Nothing else Just (T.pack prev' <> ".md")
            nextM = if null next' then Nothing else Just (T.pack next' <> ".md")
            navLine = buildNavLine prevM nextM
            content = "header\n" <> navLine <> "\nbody"
        in navLinksMatch content prevM nextM
  , testProperty "updateNavLinks is idempotent" $
      \(QC.ASCIIString prev) ->
        let prev' = filter (\character -> character /= '\n' && character /= '\r') prev
            prevM = if null prev' then Nothing else Just (T.pack prev' <> ".md")
            content = aiBlogNavPrefix <> "\n# Post\n\nBody"
            once = updateNavLinks content prevM Nothing
            twice = updateNavLinks once prevM Nothing
        in once == twice
  , testProperty "normalizeNavLine is idempotent" $
      QC.forAll genMarkdown $ \content ->
        let once = normalizeNavLine content
        in normalizeNavLine once == once
  , testProperty "normalizeNavLine always yields a line starting with aiBlogNavPrefix" $
      QC.forAll genMarkdown $ \content ->
        any (T.isPrefixOf aiBlogNavPrefix) (T.lines (normalizeNavLine content))
  , testProperty "normalizeNavLine never drops a heading line" $
      QC.forAll genMarkdown $ \content ->
        let headings = filter (T.isPrefixOf "# ") (T.lines content)
        in all (`elem` T.lines (normalizeNavLine content)) headings
  , testProperty "normalizeNavLine only prepends the nav line to a body that starts with a heading" $
      QC.forAll (withoutWikiNavLines <$> genMarkdown) $ \body ->
        let content = dominationFrontmatter <> "# Post\n" <> body
        in normalizeNavLine content == dominationFrontmatter <> aiBlogNavPrefix <> "\n# Post\n" <> body
  ]

genMarkdown :: QC.Gen T.Text
genMarkdown = T.intercalate "\n" <$> QC.listOf genMarkdownLine

withoutWikiNavLines :: T.Text -> T.Text
withoutWikiNavLines = T.intercalate "\n" . filter (not . T.isPrefixOf aiBlogNavPrefix) . T.splitOn "\n"

genMarkdownLine :: QC.Gen T.Text
genMarkdownLine = QC.oneof
  [ T.pack . QC.getPrintableString <$> QC.arbitrary
  , QC.elements
      [ ""
      , "---"
      , "title: Example"
      , "# 💬 2026-10-30 | Heading"
      , "[🏠 Home](../) > [🤖 AI Blog](./)"
      , "[🏡 Home](../index.md) > [🤖 AI Blog](./index.md)"
      , aiBlogNavPrefix
      ]
  ]
