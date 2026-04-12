module Automation.BlogSeriesDiscoveryTest (tests) where

import Data.List.NonEmpty (NonEmpty ((:|)))
import qualified Data.Text as T
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import Test.Tasty.QuickCheck (testProperty)
import qualified Test.QuickCheck as QC

import qualified Automation.Gemini as Gemini
import Automation.BlogSeriesConfig (BlogSeriesConfig (..))
import Automation.BlogSeriesDiscovery
import Automation.Scheduler (TaskId (..), ScheduleEntry (..), BlogSeriesRunConfig (..))

tests :: TestTree
tests = testGroup "BlogSeriesDiscovery"
  [ parseSeriesConfigTests
  , derivationTests
  , validationTests
  , properties
  ]

unsafeParse :: T.Text -> T.Text -> DiscoveredSeries
unsafeParse seriesId content =
  case parseSeriesConfig seriesId content of
    Right discovered -> discovered
    Left errors -> error $ "Test setup failed: " <> show errors

parseSeriesConfigTests :: TestTree
parseSeriesConfigTests = testGroup "parseSeriesConfig"
  [ testCase "parses minimal valid config" $
      assertBool "should parse successfully" $
        isRight (parseSeriesConfig "garden-thoughts" minimalConfig)

  , testCase "parses config without priority user" $
      assertBool "should parse successfully" $
        isRight (parseSeriesConfig "solo-bot" configWithoutPriorityUser)

  , testCase "parses config with null priority user" $
      assertBool "should parse config with null priority" $
        isRight (parseSeriesConfig "solo-bot" configWithNullPriorityUser)

  , testCase "rejects empty input" $
      assertBool "should fail on empty" $
        isLeft (parseSeriesConfig "test" "")

  , testCase "rejects malformed JSON" $
      assertBool "should fail on malformed" $
        isLeft (parseSeriesConfig "test" "not json")

  , testCase "extracts correct name" $
      dsName (unsafeParse "garden-thoughts" minimalConfig) @?= "Garden Thoughts"

  , testCase "extracts correct icon" $
      dsIcon (unsafeParse "garden-thoughts" minimalConfig) @?= "\129793"

  , testCase "extracts correct schedule hour" $
      dsScheduleHourPacific (unsafeParse "garden-thoughts" minimalConfig) @?= 11

  , testCase "extracts correct models" $
      dsModels (unsafeParse "garden-thoughts" minimalConfig)
        @?= (Gemini.Gemini25Flash :| [Gemini.Gemini25FlashLite])

  , testCase "extracts correct post time" $
      dsScheduleHourPacific (unsafeParse "garden-thoughts" minimalConfig) @?= 11

  , testCase "extracts priority user" $
      dsPriorityUser (unsafeParse "garden-thoughts" minimalConfig) @?= Just "bagrounds"

  , testCase "missing priority user defaults to Nothing" $
      dsPriorityUser (unsafeParse "solo-bot" configWithoutPriorityUser) @?= Nothing

  , testCase "null priority user gives Nothing" $
      dsPriorityUser (unsafeParse "solo-bot" configWithNullPriorityUser) @?= Nothing

  , testCase "sets series ID from argument" $
      dsId (unsafeParse "garden-thoughts" minimalConfig) @?= "garden-thoughts"

  , testCase "parses existing auto-blog-zero config" $ do
      let config = T.unlines
            [ "{"
            , "  \"name\": \"Auto Blog Zero\","
            , "  \"icon\": \"\129302\","
            , "  \"priorityUser\": \"bagrounds\","
            , "  \"scheduleHourPacific\": 8,"
            , "  \"models\": [\"gemini-3.1-flash-lite-preview\", \"gemini-3-flash-preview\"]"
            , "}"
            ]
          discovered = unsafeParse "auto-blog-zero" config
      dsName discovered @?= "Auto Blog Zero"
      dsScheduleHourPacific discovered @?= 8
  ]

derivationTests :: TestTree
derivationTests = testGroup "derivation functions"
  [ testCase "deriveAuthor wraps ID in wikilink" $
      deriveAuthor "garden-thoughts" @?= "[[garden-thoughts]]"

  , testCase "deriveBaseUrl prepends domain" $
      deriveBaseUrl "garden-thoughts" @?= "https://bagrounds.org/garden-thoughts"

  , testCase "deriveNavLink builds correct nav" $
      deriveNavLink "garden-thoughts" "\129793" "Garden Thoughts"
        @?= "[[index|Home]] > [[garden-thoughts/index|\129793 Garden Thoughts]]"

  , testCase "derivePriorityUserEnvVar converts to env var format" $
      derivePriorityUserEnvVar "auto-blog-zero" @?= "AUTO_BLOG_ZERO_PRIORITY_USER"

  , testCase "derivePriorityUserEnvVar handles hyphens" $
      derivePriorityUserEnvVar "systems-for-public-good" @?= "SYSTEMS_FOR_PUBLIC_GOOD_PRIORITY_USER"

  , testCase "deriveTaskId creates BlogSeries" $
      deriveTaskId "garden-thoughts" @?= BlogSeries "garden-thoughts"

  , testCase "deriveBlogSeriesConfig sets correct ID" $ do
      let config = deriveBlogSeriesConfig sampleDiscovered
      bscId config @?= "garden-thoughts"

  , testCase "deriveBlogSeriesConfig derives author" $ do
      let config = deriveBlogSeriesConfig sampleDiscovered
      bscAuthor config @?= "[[garden-thoughts]]"

  , testCase "deriveBlogSeriesConfig derives base URL" $ do
      let config = deriveBlogSeriesConfig sampleDiscovered
      bscBaseUrl config @?= "https://bagrounds.org/garden-thoughts"

  , testCase "deriveBlogSeriesConfig preserves priority user" $ do
      let config = deriveBlogSeriesConfig sampleDiscovered
      bscPriorityUser config @?= Just "bagrounds"

  , testCase "deriveBlogSeriesRunConfig sets correct series ID" $ do
      let config = deriveBlogSeriesRunConfig sampleDiscovered
      bsrcSeriesId config @?= "garden-thoughts"

  , testCase "deriveBlogSeriesRunConfig sets correct model chain" $ do
      let config = deriveBlogSeriesRunConfig sampleDiscovered
      bsrcModelChain config @?= (Gemini.Gemini25Flash :| [Gemini.Gemini25FlashLite])

  , testCase "deriveBlogSeriesRunConfig sets correct env var" $ do
      let config = deriveBlogSeriesRunConfig sampleDiscovered
      bsrcPriorityUserEnvVar config @?= "GARDEN_THOUGHTS_PRIORITY_USER"

  , testCase "deriveScheduleEntry sets correct task ID" $ do
      let entry = deriveScheduleEntry sampleDiscovered
      seTaskId entry @?= BlogSeries "garden-thoughts"

  , testCase "deriveScheduleEntry sets correct hours" $ do
      let entry = deriveScheduleEntry sampleDiscovered
      seHoursPacific entry @?= [11]

  , testCase "deriveScheduleEntry sets atOrAfter False" $ do
      let entry = deriveScheduleEntry sampleDiscovered
      seAtOrAfter entry @?= False
  ]

validationTests :: TestTree
validationTests = testGroup "validation"
  [ testCase "rejects config missing required fields" $
      assertBool "should fail without name" $
        isLeft (parseSeriesConfig "test" configMissingName)

  , testCase "rejects empty models list" $
      assertBool "should reject empty models" $
        isLeft (parseSeriesConfig "test" configEmptyModels)

  , testCase "accepts config without priorityUser" $
      assertBool "should accept missing priorityUser" $
        isRight (parseSeriesConfig "test" configNoPriorityUser)

  , testCase "missing priorityUser defaults to Nothing" $
      dsPriorityUser (unsafeParse "test" configNoPriorityUser) @?= Nothing
  ]

properties :: TestTree
properties = testGroup "properties"
  [ testProperty "deriveAuthor always wraps in double brackets" $
      QC.forAll genSeriesId $ \seriesId ->
        let author = deriveAuthor seriesId
        in T.isPrefixOf "[[" author && T.isSuffixOf "]]" author

  , testProperty "deriveBaseUrl always starts with https" $
      QC.forAll genSeriesId $ \seriesId ->
        T.isPrefixOf "https://bagrounds.org/" (deriveBaseUrl seriesId)

  , testProperty "derivePriorityUserEnvVar always ends with PRIORITY_USER" $
      QC.forAll genSeriesId $ \seriesId ->
        T.isSuffixOf "_PRIORITY_USER" (derivePriorityUserEnvVar seriesId)

  , testProperty "derivePriorityUserEnvVar contains no hyphens" $
      QC.forAll genSeriesId $ \seriesId ->
        not (T.any (== '-') (derivePriorityUserEnvVar seriesId))

  , testProperty "deriveTaskId creates BlogSeries with same ID" $
      QC.forAll genSeriesId $ \seriesId ->
        case deriveTaskId seriesId of
          BlogSeries extractedId -> extractedId == seriesId
          _ -> False

  , testProperty "deriveBlogSeriesConfig preserves ID" $
      QC.forAll genDiscoveredSeries $ \discovered ->
        bscId (deriveBlogSeriesConfig discovered) == dsId discovered

  , testProperty "deriveBlogSeriesConfig preserves icon" $
      QC.forAll genDiscoveredSeries $ \discovered ->
        bscIcon (deriveBlogSeriesConfig discovered) == dsIcon discovered

  , testProperty "deriveBlogSeriesConfig preserves name" $
      QC.forAll genDiscoveredSeries $ \discovered ->
        bscName (deriveBlogSeriesConfig discovered) == dsName discovered
  ]

isRight :: Either a b -> Bool
isRight (Right _) = True
isRight (Left _)  = False

isLeft :: Either a b -> Bool
isLeft (Left _)  = True
isLeft (Right _) = False

minimalConfig :: T.Text
minimalConfig = T.unlines
  [ "{"
  , "  \"name\": \"Garden Thoughts\","
  , "  \"icon\": \"\129793\","
  , "  \"priorityUser\": \"bagrounds\","
  , "  \"scheduleHourPacific\": 11,"
  , "  \"models\": [\"gemini-2.5-flash\", \"gemini-2.5-flash-lite\"]"
  , "}"
  ]

configWithoutPriorityUser :: T.Text
configWithoutPriorityUser = T.unlines
  [ "{"
  , "  \"name\": \"Solo Bot\","
  , "  \"icon\": \"\129302\","
  , "  \"scheduleHourPacific\": 6,"
  , "  \"models\": [\"gemini-2.5-flash\"]"
  , "}"
  ]

configWithNullPriorityUser :: T.Text
configWithNullPriorityUser = T.unlines
  [ "{"
  , "  \"name\": \"Solo Bot\","
  , "  \"icon\": \"\129302\","
  , "  \"priorityUser\": null,"
  , "  \"scheduleHourPacific\": 6,"
  , "  \"models\": [\"gemini-2.5-flash\"]"
  , "}"
  ]

configMissingName :: T.Text
configMissingName = T.unlines
  [ "{"
  , "  \"icon\": \"\129793\","
  , "  \"scheduleHourPacific\": 11,"
  , "  \"models\": [\"gemini-2.5-flash\"]"
  , "}"
  ]

configEmptyModels :: T.Text
configEmptyModels = T.unlines
  [ "{"
  , "  \"name\": \"Empty Models\","
  , "  \"icon\": \"\10060\","
  , "  \"scheduleHourPacific\": 11,"
  , "  \"models\": []"
  , "}"
  ]

configNoPriorityUser :: T.Text
configNoPriorityUser = T.unlines
  [ "{"
  , "  \"name\": \"No Priority\","
  , "  \"icon\": \"\128736\","
  , "  \"scheduleHourPacific\": 11,"
  , "  \"models\": [\"gemini-2.5-flash\"]"
  , "}"
  ]

sampleDiscovered :: DiscoveredSeries
sampleDiscovered = DiscoveredSeries
  { dsId = "garden-thoughts"
  , dsName = "Garden Thoughts"
  , dsIcon = "\129793"
  , dsPriorityUser = Just "bagrounds"
  , dsScheduleHourPacific = 11
  , dsModels = Gemini.Gemini25Flash :| [Gemini.Gemini25FlashLite]
  }

genSeriesId :: QC.Gen T.Text
genSeriesId = do
  parts <- QC.listOf1 genWord
  pure (T.intercalate "-" parts)
  where
    genWord = T.pack <$> QC.listOf1 (QC.elements ['a'..'z'])

genDiscoveredSeries :: QC.Gen DiscoveredSeries
genDiscoveredSeries = do
  seriesId <- genSeriesId
  name <- T.pack <$> QC.listOf1 (QC.elements ['A'..'Z'])
  icon <- QC.elements ["\129793", "\129302", "\128020", "\127963\65039", "\127925"]
  priorityUser <- QC.oneof [pure Nothing, Just . T.pack <$> QC.listOf1 (QC.elements ['a'..'z'])]
  hour <- QC.choose (0, 23)
  pure DiscoveredSeries
    { dsId = seriesId
    , dsName = name
    , dsIcon = icon
    , dsPriorityUser = priorityUser
    , dsScheduleHourPacific = hour
    , dsModels = Gemini.Gemini25Flash :| []
    }
