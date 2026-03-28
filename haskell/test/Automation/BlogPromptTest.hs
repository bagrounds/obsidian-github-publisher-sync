module Automation.BlogPromptTest (tests) where

import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import qualified Data.Text as T

import Automation.BlogPrompt
import Automation.BlogSeriesConfig (lookupSeries)

tests :: TestTree
tests = testGroup "BlogPrompt"
  [ testCase "stripEmbedSections removes tweet section" $
      let body = "Content here\n\n## 🐦 Tweet\n\nSome embed"
      in stripEmbedSections body @?= "Content here"

  , testCase "stripEmbedSections preserves content without embeds" $
      let body = "Just normal content"
      in stripEmbedSections body @?= "Just normal content"

  , testCase "quoteForYaml wraps in double quotes" $
      assertBool "should be quoted" $
        T.head (quoteForYaml "hello") == '"'

  , testCase "quoteForYaml escapes internal quotes" $
      assertBool "should escape" $
        "\\\"" `T.isInfixOf` quoteForYaml "say \"hi\""

  , testCase "buildBackLink produces wiki link" $
      let Right series = lookupSeries "chickie-loo"
          result = buildBackLink series "2026-03-25-test"
      in assertBool "should be wiki link with back emoji" $
           "⏮️" `T.isInfixOf` result && "[[" `T.isPrefixOf` result

  , testCase "buildForwardLink produces wiki link" $
      let Right series = lookupSeries "chickie-loo"
          result = buildForwardLink series "2026-03-27-test.md"
      in assertBool "should be wiki link with forward emoji" $
           "⏭️" `T.isInfixOf` result && "[[" `T.isPrefixOf` result

  , testCase "assembleFrontmatter generates share: true" $
      let Right series = lookupSeries "auto-blog-zero"
          fm = assembleFrontmatter series "2026-03-12" "My Great Post" "my-great-post"
      in assertBool "should include share: true" $
           "share: true" `T.isInfixOf` fm

  , testCase "assembleFrontmatter includes display title with date and icon" $
      let Right series = lookupSeries "auto-blog-zero"
          fm = assembleFrontmatter series "2026-03-12" "My Great Post" "my-great-post"
      in assertBool "should include display title" $
           "2026-03-12 | 🤖 My Great Post 🤖" `T.isInfixOf` fm

  , testCase "assembleFrontmatter includes URL with date prefix" $
      let Right series = lookupSeries "auto-blog-zero"
          fm = assembleFrontmatter series "2026-03-12" "My Great Post" "my-great-post"
      in assertBool "should include URL with date-slug" $
           "URL: https://bagrounds.org/auto-blog-zero/2026-03-12-my-great-post" `T.isInfixOf` fm

  , testCase "assembleFrontmatter quotes Author with wikilink" $
      let Right series = lookupSeries "auto-blog-zero"
          fm = assembleFrontmatter series "2026-03-12" "My Great Post" "my-great-post"
      in assertBool "should include quoted Author" $
           "Author: \"[[auto-blog-zero]]\"" `T.isInfixOf` fm

  , testCase "assembleFrontmatter quotes title with colons for YAML safety" $
      let Right series = lookupSeries "auto-blog-zero"
          fm = assembleFrontmatter series "2026-03-26" "The Silence After the Forge: Processing the Aftermath" "the-silence-after-the-forge-processing-the-aftermath"
      in assertBool "title should be quoted" $
           "title: \"2026-03-26 | 🤖 The Silence After the Forge: Processing the Aftermath 🤖\"" `T.isInfixOf` fm

  , testCase "assembleFrontmatter quotes aliases with colons for YAML safety" $
      let Right series = lookupSeries "auto-blog-zero"
          fm = assembleFrontmatter series "2026-03-26" "The Silence After the Forge: Processing the Aftermath" "the-silence-after-the-forge-processing-the-aftermath"
      in assertBool "aliases should be quoted" $
           "- \"2026-03-26 | 🤖 The Silence After the Forge: Processing the Aftermath 🤖\"" `T.isInfixOf` fm

  , testCase "assembleFrontmatter does not include date field" $
      let Right series = lookupSeries "auto-blog-zero"
          fm = assembleFrontmatter series "2026-03-12" "My Great Post" "my-great-post"
      in assertBool "should not have date field" $
           not ("\ndate:" `T.isInfixOf` fm)

  , testCase "buildDisplayTitle constructs correct format" $
      let Right series = lookupSeries "chickie-loo"
          result = buildDisplayTitle series "2026-03-28" "My Post"
      in result @?= "2026-03-28 | 🐔 My Post 🐔"

  , testCase "assembleFrontmatter works for chickie-loo series" $
      let Right series = lookupSeries "chickie-loo"
          fm = assembleFrontmatter series "2026-03-12" "My Great Post" "my-great-post"
      in assertBool "should include chickie-loo Author" $
           "Author: \"[[chickie-loo]]\"" `T.isInfixOf` fm
  ]
