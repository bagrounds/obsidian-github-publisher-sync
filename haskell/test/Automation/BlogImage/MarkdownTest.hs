module Automation.BlogImage.MarkdownTest (tests) where

import qualified Data.Text as T
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import Test.Tasty.QuickCheck (testProperty)

import Automation.BlogImage.Markdown

tests :: TestTree
tests = testGroup "BlogImage.Markdown"
  [ testGroup "insertImageEmbed"
      [ testCase "inserts after H1" $
          insertImageEmbed "# Title\nbody text" "photo.jpg"
            @?= "# Title\n![[attachments/photo.jpg]]\nbody text"
      , testCase "returns unchanged if no H1" $
          insertImageEmbed "no heading\nbody" "photo.jpg"
            @?= "no heading\nbody"
      , testCase "handles frontmatter before H1" $
          insertImageEmbed "---\ntitle: test\n---\n# Title\nbody" "img.png"
            @?= "---\ntitle: test\n---\n# Title\n![[attachments/img.png]]\nbody"
      ]
  , testGroup "removeImageEmbed"
      [ testCase "removes Obsidian embed and returns name" $
          let (content, mName) = removeImageEmbed "before\n![[attachments/photo.jpg]]\nafter"
          in do
            assertBool "should remove embed" $ not (T.isInfixOf "![[" content)
            mName @?= Just "photo.jpg"
      , testCase "returns Nothing when no embed" $
          let (_, mName) = removeImageEmbed "no images here"
          in mName @?= Nothing
      , testCase "strips attachments prefix from name" $
          let (_, mName) = removeImageEmbed "![[attachments/img.png]]\nrest"
          in mName @?= Just "img.png"
      ]
  , testGroup "removeHeadings"
      [ testCase "strips H1" $
          removeHeadings "# Hello\nbody" @?= "Hello\nbody\n"
      , testCase "strips H2" $
          removeHeadings "## Subtitle" @?= "Subtitle\n"
      , testCase "strips all heading levels" $ do
          assertBool "H3" $ not (T.isPrefixOf "###" (removeHeadings "### H3"))
          assertBool "H4" $ not (T.isPrefixOf "####" (removeHeadings "#### H4"))
          assertBool "H5" $ not (T.isPrefixOf "#####" (removeHeadings "##### H5"))
          assertBool "H6" $ not (T.isPrefixOf "######" (removeHeadings "###### H6"))
      , testCase "leaves non-heading text unchanged" $
          removeHeadings "plain text" @?= "plain text\n"
      ]
  , testGroup "removeObsidianEmbeds"
      [ testCase "removes wiki-style embed" $
          removeObsidianEmbeds "before ![[some-file]] after" @?= "before  after"
      , testCase "removes image embed" $
          removeObsidianEmbeds "![[attachments/photo.jpg]]" @?= ""
      ]
  , testGroup "removeMarkdownImages"
      [ testCase "removes markdown image" $
          removeMarkdownImages "before ![alt](path.png) after" @?= "before  after"
      , testCase "leaves text without images unchanged" $
          removeMarkdownImages "plain text" @?= "plain text"
      ]
  , testGroup "removeMarkdownLinks"
      [ testCase "keeps link text, removes URL" $
          removeMarkdownLinks "[my link](http://example.com)" @?= "my link"
      , testCase "leaves non-link text unchanged" $
          removeMarkdownLinks "no links" @?= "no links"
      ]
  , testGroup "removeCodeBlocks"
      [ testCase "removes fenced code block" $
          removeCodeBlocks "before\n```python\nprint('hello')\n```\nafter"
            @?= "before\nafter"
      , testCase "leaves text without code blocks unchanged" $
          removeCodeBlocks "plain text" @?= "plain text"
      ]
  , testGroup "removeInlineCode"
      [ testCase "removes inline code" $
          removeInlineCode "text `code` more" @?= "text  more"
      , testCase "leaves text without inline code unchanged" $
          removeInlineCode "plain text" @?= "plain text"
      ]
  , testGroup "stripMarkdownSyntax"
      [ testCase "strips headings" $
          assertBool "no heading markers" $
            not (T.isInfixOf "# " (stripMarkdownSyntax "# Hello\n## World"))
      , testCase "strips emphasis" $
          assertBool "no asterisks" $
            not (T.any (== '*') (stripMarkdownSyntax "**bold** and *italic*"))
      , testCase "strips code blocks and inline code" $ do
          let result = stripMarkdownSyntax "text `inline` more\n```\nblock\n```\nend"
          assertBool "no backticks" $ not (T.any (== '`') result)
      ]
  , testGroup "cleanContentForPrompt"
      [ testCase "strips frontmatter" $
          assertBool "no frontmatter delimiters" $
            not (T.isInfixOf "---" (cleanContentForPrompt "---\ntitle: test\n---\n# Hello\nbody"))
      , testCase "strips markdown syntax" $
          assertBool "no heading markers" $
            not (T.isPrefixOf "# " (cleanContentForPrompt "# Hello World"))
      ]
  , testGroup "buildImagePrompt"
      [ testCase "starts with instruction prefix" $
          assertBool "starts with generate prefix" $
            T.isPrefixOf "generate an image" (buildImagePrompt "# My Post\nSome content")
      , testCase "respects max length" $
          assertBool "does not exceed 2048 chars" $
            T.length (buildImagePrompt (T.replicate 5000 "word ")) <= 2048
      ]
  , testGroup "properties"
      [ testProperty "buildImagePrompt never exceeds max length" $
          \content -> T.length (buildImagePrompt (T.pack content)) <= 2048
      , testProperty "insertImageEmbed is idempotent on content without H1" $
          \s -> let t = T.pack s
                    noH1 = not (T.isInfixOf "\n# " t) && not (T.isPrefixOf "# " t)
                in noH1 ==> (insertImageEmbed t "test.jpg" == t)
      ]
  ]
  where
    (==>) :: Bool -> Bool -> Bool
    (==>) False _ = True
    (==>) True  b = b
