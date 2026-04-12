module Automation.BlogPromptTest (tests) where

import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import Test.Tasty.QuickCheck (testProperty)
import qualified Test.QuickCheck as QC
import Data.Char (isAsciiLower, isAsciiUpper, isDigit)
import qualified Data.Text as T
import Data.Time (fromGregorian)

import Automation.BlogPrompt
import Automation.PacificTime (formatDay)
import Automation.BlogSeriesConfig (BlogSeriesConfig (..), lookupSeriesIn)
import Automation.BlogSeriesDiscovery (deriveBlogSeriesConfig, DiscoveredSeries (..))
import qualified Automation.Gemini as Gemini
import Data.List.NonEmpty (NonEmpty ((:|)))
import qualified Data.Map.Strict as Map

testSeriesMap :: Map.Map T.Text BlogSeriesConfig
testSeriesMap = Map.fromList
  [ ("chickie-loo", deriveBlogSeriesConfig DiscoveredSeries
      { dsId = "chickie-loo", dsName = "Chickie Loo", dsIcon = "🐔"
      , dsPriorityUser = Just "ChickieLoo", dsScheduleHourPacific = 7
      , dsModels = Gemini.Gemini31FlashLite :| [Gemini.Gemini3Flash]
      })
  , ("auto-blog-zero", deriveBlogSeriesConfig DiscoveredSeries
      { dsId = "auto-blog-zero", dsName = "Auto Blog Zero", dsIcon = "🤖"
      , dsPriorityUser = Just "bagrounds", dsScheduleHourPacific = 8
      , dsModels = Gemini.Gemini31FlashLite :| [Gemini.Gemini3Flash]
      })
  , ("systems-for-public-good", deriveBlogSeriesConfig DiscoveredSeries
      { dsId = "systems-for-public-good", dsName = "Systems for Public Good", dsIcon = "🏛️"
      , dsPriorityUser = Just "bagrounds", dsScheduleHourPacific = 9
      , dsModels = Gemini.Gemini25Flash :| [Gemini.Gemini25FlashLite, Gemini.Gemini31FlashLite]
      })
  ]

unsafeLookupSeries :: T.Text -> BlogSeriesConfig
unsafeLookupSeries name = case lookupSeriesIn testSeriesMap name of
  Right config -> config
  Left err -> error $ "Test setup failed: " <> T.unpack err

unsafeMkSlug :: T.Text -> Slug
unsafeMkSlug name = case mkSlug name of
  Right slug -> slug
  Left err -> error $ "Test setup failed: " <> T.unpack err

tests :: TestTree
tests = testGroup "BlogPrompt"
  [ testCase "stripEmbedSections removes tweet section" $
      let body = "Content here\n\n## 🐦 Tweet\n\nSome embed"
      in stripEmbedSections body @?= "Content here"

  , testCase "stripEmbedSections preserves content without embeds" $
      let body = "Just normal content"
      in stripEmbedSections body @?= "Just normal content"

  , testCase "buildBackLink produces wiki link" $
      let series = unsafeLookupSeries "chickie-loo"
          result = buildBackLink series "2026-03-25-test"
      in assertBool "should be wiki link with back emoji" $
           "⏮️" `T.isInfixOf` result && "[[" `T.isPrefixOf` result

  , testCase "buildForwardLink produces wiki link" $
      let series = unsafeLookupSeries "chickie-loo"
          result = buildForwardLink series "2026-03-27-test.md"
      in assertBool "should be wiki link with forward emoji" $
           "⏭️" `T.isInfixOf` result && "[[" `T.isPrefixOf` result

  , testCase "assembleFrontmatter generates share: true" $
      let series = unsafeLookupSeries "auto-blog-zero"
          slug = unsafeMkSlug "my-great-post"
          fm = assembleFrontmatter series (fromGregorian 2026 3 12) "My Great Post" slug
      in assertBool "should include share: true" $
           "share: true" `T.isInfixOf` fm

  , testCase "assembleFrontmatter includes display title with date and icon" $
      let series = unsafeLookupSeries "auto-blog-zero"
          slug = unsafeMkSlug "my-great-post"
          fm = assembleFrontmatter series (fromGregorian 2026 3 12) "My Great Post" slug
      in assertBool "should include display title" $
           "2026-03-12 | 🤖 My Great Post 🤖" `T.isInfixOf` fm

  , testCase "assembleFrontmatter includes quoted URL with date prefix" $
      let series = unsafeLookupSeries "auto-blog-zero"
          slug = unsafeMkSlug "my-great-post"
          fm = assembleFrontmatter series (fromGregorian 2026 3 12) "My Great Post" slug
      in assertBool "should include quoted URL with date-slug" $
           "URL: \"https://bagrounds.org/auto-blog-zero/2026-03-12-my-great-post\"" `T.isInfixOf` fm

  , testCase "assembleFrontmatter quotes Author with wikilink" $
      let series = unsafeLookupSeries "auto-blog-zero"
          slug = unsafeMkSlug "my-great-post"
          fm = assembleFrontmatter series (fromGregorian 2026 3 12) "My Great Post" slug
      in assertBool "should include quoted Author" $
           "Author: \"[[auto-blog-zero]]\"" `T.isInfixOf` fm

  , testCase "assembleFrontmatter quotes title with colons for YAML safety" $
      let series = unsafeLookupSeries "auto-blog-zero"
          slug = unsafeMkSlug "the-silence-after-the-forge-processing-the-aftermath"
          fm = assembleFrontmatter series (fromGregorian 2026 3 26) "The Silence After the Forge: Processing the Aftermath" slug
      in assertBool "title should be quoted" $
           "title: \"2026-03-26 | 🤖 The Silence After the Forge: Processing the Aftermath 🤖\"" `T.isInfixOf` fm

  , testCase "assembleFrontmatter quotes aliases with colons for YAML safety" $
      let series = unsafeLookupSeries "auto-blog-zero"
          slug = unsafeMkSlug "the-silence-after-the-forge-processing-the-aftermath"
          fm = assembleFrontmatter series (fromGregorian 2026 3 26) "The Silence After the Forge: Processing the Aftermath" slug
      in assertBool "aliases should be quoted" $
           "- \"2026-03-26 | 🤖 The Silence After the Forge: Processing the Aftermath 🤖\"" `T.isInfixOf` fm

  , testCase "assembleFrontmatter does not include date field" $
      let series = unsafeLookupSeries "auto-blog-zero"
          slug = unsafeMkSlug "my-great-post"
          fm = assembleFrontmatter series (fromGregorian 2026 3 12) "My Great Post" slug
      in assertBool "should not have date field" $
           not ("\ndate:" `T.isInfixOf` fm)

  , testCase "assembleFrontmatter does not include empty tags field" $
      let series = unsafeLookupSeries "auto-blog-zero"
          slug = unsafeMkSlug "my-great-post"
          fm = assembleFrontmatter series (fromGregorian 2026 3 12) "My Great Post" slug
      in assertBool "should not have tags field" $
           not ("tags:" `T.isInfixOf` fm)

  , testCase "buildDisplayTitle constructs correct format" $
      let series = unsafeLookupSeries "chickie-loo"
          (DisplayTitle result) = buildDisplayTitle series (fromGregorian 2026 3 28) "My Post"
      in result @?= "2026-03-28 | 🐔 My Post 🐔"

  , testCase "assembleFrontmatter works for chickie-loo series" $
      let series = unsafeLookupSeries "chickie-loo"
          slug = unsafeMkSlug "my-great-post"
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
      let series = unsafeLookupSeries "auto-blog-zero"
      in sanitizeTitle series "My Great Post" @?= "My Great Post"

  , testCase "sanitizeTitle strips date pipe prefix" $
      let series = unsafeLookupSeries "auto-blog-zero"
      in sanitizeTitle series "2026-03-30 | The Architecture of Doubt" @?= "The Architecture of Doubt"

  , testCase "sanitizeTitle strips date pipe prefix and leading icon" $
      let series = unsafeLookupSeries "auto-blog-zero"
      in sanitizeTitle series "2026-03-30 | 🤖 The Architecture of Doubt" @?= "The Architecture of Doubt"

  , testCase "sanitizeTitle strips leading and trailing series icon" $
      let series = unsafeLookupSeries "auto-blog-zero"
      in sanitizeTitle series "🤖 The Architecture of Doubt 🤖" @?= "The Architecture of Doubt"

  , testCase "sanitizeTitle strips full display title format" $
      let series = unsafeLookupSeries "auto-blog-zero"
      in sanitizeTitle series "🤖 2026-03-30 | 🧩 The Architecture of Doubt: Calibrating Our First Adversary 🤖"
           @?= "🧩 The Architecture of Doubt: Calibrating Our First Adversary"

  , testCase "sanitizeTitle strips date prefix for chickie-loo" $
      let series = unsafeLookupSeries "chickie-loo"
      in sanitizeTitle series "2026-04-02 | 🐔 🐣 Finding Our Rhythm in the Morning Light 🌾"
           @?= "🐣 Finding Our Rhythm in the Morning Light 🌾"

  , testCase "sanitizeTitle strips full display title for chickie-loo" $
      let series = unsafeLookupSeries "chickie-loo"
      in sanitizeTitle series "🐔 2026-04-02 | 🐣 Finding Our Rhythm 🐔"
           @?= "🐣 Finding Our Rhythm"

  , testCase "sanitizeTitle preserves non-series emoji in title" $
      let series = unsafeLookupSeries "auto-blog-zero"
      in sanitizeTitle series "🧩 The Architecture of Doubt" @?= "🧩 The Architecture of Doubt"

  , testCase "sanitizeTitle handles date without pipe separator" $
      let series = unsafeLookupSeries "auto-blog-zero"
      in sanitizeTitle series "2026-03-30 The Architecture of Doubt" @?= "The Architecture of Doubt"

  , testCase "buildBlogPrompt user prompt includes human-readable date" $
      let series = unsafeLookupSeries "chickie-loo"
          ctx = BlogContext
            { bcxSeries = series
            , bcxAgentsMd = ""
            , bcxPreviousPosts = []
            , bcxComments = []
            , bcxToday = fromGregorian 2026 4 11
            }
          (_, userPrompt) = buildBlogPrompt ctx
      in assertBool "should include human-readable date" $
           "Today is Saturday, April 11, 2026." `T.isInfixOf` userPrompt

  , testCase "buildBlogPrompt user prompt includes YYYY-MM-DD date" $
      let series = unsafeLookupSeries "chickie-loo"
          ctx = BlogContext
            { bcxSeries = series
            , bcxAgentsMd = ""
            , bcxPreviousPosts = []
            , bcxComments = []
            , bcxToday = fromGregorian 2026 4 11
            }
          (_, userPrompt) = buildBlogPrompt ctx
      in assertBool "should include YYYY-MM-DD date" $
           "2026-04-11" `T.isInfixOf` userPrompt

  , generateSlugTests
  ]

generateSlugTests :: TestTree
generateSlugTests = testGroup "generateSlug"
  [ testCase "lowercases and converts spaces to hyphens" $
      generateSlug "Hello World" @?= "hello-world"

  , testCase "strips emojis" $
      generateSlug "🎉 Party Time 🎈" @?= "party-time"

  , testCase "removes special characters" $
      generateSlug "What's the Plan?" @?= "what-s-the-plan"

  , testCase "trims leading and trailing hyphens" $
      generateSlug "-Hello-" @?= "hello"

  , testCase "collapses multiple spaces into single hyphen" $
      generateSlug "Too   Many   Spaces" @?= "too-many-spaces"

  , testCase "handles empty string" $
      generateSlug "" @?= ""

  , testCase "handles string with only emojis" $
      generateSlug "🎉🎈🎊" @?= ""

  , testCase "preserves digits" $
      generateSlug "Chapter 42 Notes" @?= "chapter-42-notes"

  , testCase "handles mixed case with hyphens" $
      generateSlug "My-Cool-Title" @?= "my-cool-title"

  , testCase "strips leading whitespace before processing" $
      generateSlug "  Spaced Out  " @?= "spaced-out"

  , testProperty "result never contains uppercase letters" $
      QC.forAll (QC.listOf1 QC.arbitraryASCIIChar) $ \chars ->
        let slug = generateSlug (T.pack chars)
        in T.all (not . isAsciiUpper) slug

  , testProperty "result never starts or ends with hyphen" $
      QC.forAll (QC.listOf1 QC.arbitraryASCIIChar) $ \chars ->
        let slug = generateSlug (T.pack chars)
        in T.null slug || (T.head slug /= '-' && T.last slug /= '-')

  , testProperty "result contains only lowercase alphanumeric and hyphens" $
      QC.forAll (QC.listOf1 QC.arbitraryASCIIChar) $ \chars ->
        let slug = generateSlug (T.pack chars)
        in T.all (\c -> isAsciiLower c || isDigit c || c == '-') slug
  ]
