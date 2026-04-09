module Automation.BlogPromptTest (tests) where

import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import qualified Data.Text as T
import Data.Time (fromGregorian)

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
          Right slug = mkSlug "my-great-post"
          fm = assembleFrontmatter series (fromGregorian 2026 3 12) "My Great Post" slug
      in assertBool "should include share: true" $
           "share: true" `T.isInfixOf` fm

  , testCase "assembleFrontmatter includes display title with date and icon" $
      let Right series = lookupSeries "auto-blog-zero"
          Right slug = mkSlug "my-great-post"
          fm = assembleFrontmatter series (fromGregorian 2026 3 12) "My Great Post" slug
      in assertBool "should include display title" $
           "2026-03-12 | 🤖 My Great Post 🤖" `T.isInfixOf` fm

  , testCase "assembleFrontmatter includes quoted URL with date prefix" $
      let Right series = lookupSeries "auto-blog-zero"
          Right slug = mkSlug "my-great-post"
          fm = assembleFrontmatter series (fromGregorian 2026 3 12) "My Great Post" slug
      in assertBool "should include quoted URL with date-slug" $
           "URL: \"https://bagrounds.org/auto-blog-zero/2026-03-12-my-great-post\"" `T.isInfixOf` fm

  , testCase "assembleFrontmatter quotes Author with wikilink" $
      let Right series = lookupSeries "auto-blog-zero"
          Right slug = mkSlug "my-great-post"
          fm = assembleFrontmatter series (fromGregorian 2026 3 12) "My Great Post" slug
      in assertBool "should include quoted Author" $
           "Author: \"[[auto-blog-zero]]\"" `T.isInfixOf` fm

  , testCase "assembleFrontmatter quotes title with colons for YAML safety" $
      let Right series = lookupSeries "auto-blog-zero"
          Right slug = mkSlug "the-silence-after-the-forge-processing-the-aftermath"
          fm = assembleFrontmatter series (fromGregorian 2026 3 26) "The Silence After the Forge: Processing the Aftermath" slug
      in assertBool "title should be quoted" $
           "title: \"2026-03-26 | 🤖 The Silence After the Forge: Processing the Aftermath 🤖\"" `T.isInfixOf` fm

  , testCase "assembleFrontmatter quotes aliases with colons for YAML safety" $
      let Right series = lookupSeries "auto-blog-zero"
          Right slug = mkSlug "the-silence-after-the-forge-processing-the-aftermath"
          fm = assembleFrontmatter series (fromGregorian 2026 3 26) "The Silence After the Forge: Processing the Aftermath" slug
      in assertBool "aliases should be quoted" $
           "- \"2026-03-26 | 🤖 The Silence After the Forge: Processing the Aftermath 🤖\"" `T.isInfixOf` fm

  , testCase "assembleFrontmatter does not include date field" $
      let Right series = lookupSeries "auto-blog-zero"
          Right slug = mkSlug "my-great-post"
          fm = assembleFrontmatter series (fromGregorian 2026 3 12) "My Great Post" slug
      in assertBool "should not have date field" $
           not ("\ndate:" `T.isInfixOf` fm)

  , testCase "assembleFrontmatter does not include empty tags field" $
      let Right series = lookupSeries "auto-blog-zero"
          Right slug = mkSlug "my-great-post"
          fm = assembleFrontmatter series (fromGregorian 2026 3 12) "My Great Post" slug
      in assertBool "should not have tags field" $
           not ("tags:" `T.isInfixOf` fm)

  , testCase "buildDisplayTitle constructs correct format" $
      let Right series = lookupSeries "chickie-loo"
          (DisplayTitle result) = buildDisplayTitle series (fromGregorian 2026 3 28) "My Post"
      in result @?= "2026-03-28 | 🐔 My Post 🐔"

  , testCase "assembleFrontmatter works for chickie-loo series" $
      let Right series = lookupSeries "chickie-loo"
          Right slug = mkSlug "my-great-post"
          fm = assembleFrontmatter series (fromGregorian 2026 3 12) "My Great Post" slug
      in assertBool "should include chickie-loo Author" $
           "Author: \"[[chickie-loo]]\"" `T.isInfixOf` fm

  , testCase "mkSlug rejects empty slug" $
      case mkSlug "" of
        Left _ -> pure ()
        Right _ -> assertBool "empty slug should be rejected" False

  , testCase "mkSlug rejects slug with spaces" $
      case mkSlug "has spaces" of
        Left _ -> pure ()
        Right _ -> assertBool "slug with spaces should be rejected" False

  , testCase "mkSlug rejects slug with leading hyphen" $
      case mkSlug "-leading" of
        Left _ -> pure ()
        Right _ -> assertBool "leading hyphen should be rejected" False

  , testCase "mkSlug accepts valid slug" $
      case mkSlug "my-great-post" of
        Right (Slug s) -> s @?= "my-great-post"
        Left _ -> assertBool "valid slug should be accepted" False

  , testCase "formatDay formats Day as YYYY-MM-DD" $
      formatDay (fromGregorian 2026 3 28) @?= "2026-03-28"

  , testCase "formatDay zero-pads single-digit month and day" $
      formatDay (fromGregorian 2026 1 5) @?= "2026-01-05"

  -- sanitizeTitle tests (TDD: reproducing double-date bug)
  , testCase "sanitizeTitle passes through clean title unchanged" $
      let Right series = lookupSeries "auto-blog-zero"
      in sanitizeTitle series "My Great Post" @?= "My Great Post"

  , testCase "sanitizeTitle strips date pipe prefix" $
      let Right series = lookupSeries "auto-blog-zero"
      in sanitizeTitle series "2026-03-30 | The Architecture of Doubt" @?= "The Architecture of Doubt"

  , testCase "sanitizeTitle strips date pipe prefix and leading icon" $
      let Right series = lookupSeries "auto-blog-zero"
      in sanitizeTitle series "2026-03-30 | 🤖 The Architecture of Doubt" @?= "The Architecture of Doubt"

  , testCase "sanitizeTitle strips leading and trailing series icon" $
      let Right series = lookupSeries "auto-blog-zero"
      in sanitizeTitle series "🤖 The Architecture of Doubt 🤖" @?= "The Architecture of Doubt"

  , testCase "sanitizeTitle strips full display title format" $
      let Right series = lookupSeries "auto-blog-zero"
      in sanitizeTitle series "🤖 2026-03-30 | 🧩 The Architecture of Doubt: Calibrating Our First Adversary 🤖"
           @?= "🧩 The Architecture of Doubt: Calibrating Our First Adversary"

  , testCase "sanitizeTitle strips date prefix for chickie-loo" $
      let Right series = lookupSeries "chickie-loo"
      in sanitizeTitle series "2026-04-02 | 🐔 🐣 Finding Our Rhythm in the Morning Light 🌾"
           @?= "🐣 Finding Our Rhythm in the Morning Light 🌾"

  , testCase "sanitizeTitle strips full display title for chickie-loo" $
      let Right series = lookupSeries "chickie-loo"
      in sanitizeTitle series "🐔 2026-04-02 | 🐣 Finding Our Rhythm 🐔"
           @?= "🐣 Finding Our Rhythm"

  , testCase "sanitizeTitle preserves non-series emoji in title" $
      let Right series = lookupSeries "auto-blog-zero"
      in sanitizeTitle series "🧩 The Architecture of Doubt" @?= "🧩 The Architecture of Doubt"

  , testCase "sanitizeTitle handles date without pipe separator" $
      let Right series = lookupSeries "auto-blog-zero"
      in sanitizeTitle series "2026-03-30 The Architecture of Doubt" @?= "The Architecture of Doubt"
  ]
