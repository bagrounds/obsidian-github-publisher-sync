module Automation.BlogSeriesDiscoveryTest (tests) where

import Data.List.NonEmpty (NonEmpty ((:|)))
import qualified Data.Text as T
import Data.Time.LocalTime (TimeOfDay (..), todHour)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import Test.Tasty.QuickCheck (testProperty)
import qualified Test.QuickCheck as QC

import qualified Automation.Gemini as Gemini
import qualified Automation.BlogSeriesConfig as BSC
import Automation.BlogSeriesDiscovery
import Automation.ContextQuery (ContextQuery (..), defaultContextQueries)
import Automation.Scheduler (TaskId (..), ScheduleEntry (..))
import qualified Automation.Scheduler as Scheduler

tests :: TestTree
tests = testGroup "BlogSeriesDiscovery"
  [ parseSeriesConfigTests
  , derivationTests
  , validationTests
  , properties
  ]

parseSeries :: T.Text -> T.Text -> DiscoveredSeries
parseSeries identifier content =
  either (error . show) id (parseSeriesConfig identifier content)

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
      seriesName (parseSeries "garden-thoughts" minimalConfig) @?= "Garden Thoughts"

  , testCase "extracts correct icon" $
      seriesIcon (parseSeries "garden-thoughts" minimalConfig) @?= "\129793"

  , testCase "extracts correct schedule hour" $
      todHour (scheduleTime (parseSeries "garden-thoughts" minimalConfig)) @?= 11

  , testCase "extracts correct models" $
      let DiscoveredSeries{modelChain} = parseSeries "garden-thoughts" minimalConfig
      in modelChain @?= (Gemini.Gemini25Flash :| [Gemini.Gemini25FlashLite])

  , testCase "extracts correct post time" $
      scheduleTime (parseSeries "garden-thoughts" minimalConfig) @?= TimeOfDay 11 0 0

  , testCase "extracts priority user" $
      priorityUser (parseSeries "garden-thoughts" minimalConfig) @?= Just "bagrounds"

  , testCase "missing priority user defaults to Nothing" $
      priorityUser (parseSeries "solo-bot" configWithoutPriorityUser) @?= Nothing

  , testCase "null priority user gives Nothing" $
      priorityUser (parseSeries "solo-bot" configWithNullPriorityUser) @?= Nothing

  , testCase "sets series ID from argument" $
      let DiscoveredSeries{seriesId} = parseSeries "garden-thoughts" minimalConfig
      in seriesId @?= "garden-thoughts"

  , testCase "parses existing auto-blog-zero config" $ do
      let config = T.unlines
            [ "{"
            , "  \"name\": \"Auto Blog Zero\","
            , "  \"icon\": \"\129302\","
            , "  \"priorityUser\": \"bagrounds\","
            , "  \"scheduleHourPacific\": 8,"
            , "  \"models\": [\"gemini-3.1-flash-lite-preview\", \"gemini-3-flash-preview\"],"
            , "  \"enableGrounding\": false"
            , "}"
            ]
          discovered = parseSeries "auto-blog-zero" config
      seriesName discovered @?= "Auto Blog Zero"
      scheduleTime discovered @?= TimeOfDay 8 0 0
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
      BSC.identifier config @?= "garden-thoughts"

  , testCase "deriveBlogSeriesConfig derives author" $ do
      let config = deriveBlogSeriesConfig sampleDiscovered
      BSC.author config @?= "[[garden-thoughts]]"

  , testCase "deriveBlogSeriesConfig derives base URL" $ do
      let config = deriveBlogSeriesConfig sampleDiscovered
      BSC.baseUrl config @?= "https://bagrounds.org/garden-thoughts"

  , testCase "deriveBlogSeriesConfig preserves priority user" $ do
      let config = deriveBlogSeriesConfig sampleDiscovered
      BSC.priorityUser config @?= Just "bagrounds"

  , testCase "deriveBlogSeriesRunConfig sets correct series ID" $ do
      let config = deriveBlogSeriesRunConfig sampleDiscovered
      Scheduler.seriesId config @?= "garden-thoughts"

  , testCase "deriveBlogSeriesRunConfig sets correct model chain" $ do
      let config = deriveBlogSeriesRunConfig sampleDiscovered
      Scheduler.modelChain config @?= (Gemini.Gemini25Flash :| [Gemini.Gemini25FlashLite])

  , testCase "deriveBlogSeriesRunConfig sets correct env var" $ do
      let config = deriveBlogSeriesRunConfig sampleDiscovered
      Scheduler.priorityUserEnvVar config @?= "GARDEN_THOUGHTS_PRIORITY_USER"

  , testCase "deriveBlogSeriesRunConfig sets searchGrounding false for sampleDiscovered" $ do
      let config = deriveBlogSeriesRunConfig sampleDiscovered
      Scheduler.searchGrounding config @?= False

  , testCase "deriveBlogSeriesRunConfig passes searchGrounding true when set" $ do
      let discovered = parseSeries "grounded-series" configWithGrounding
          config = deriveBlogSeriesRunConfig discovered
      Scheduler.searchGrounding config @?= True

  , testCase "deriveScheduleEntry sets correct task ID" $ do
      let entry = deriveScheduleEntry sampleDiscovered
      taskId entry @?= BlogSeries "garden-thoughts"

  , testCase "deriveScheduleEntry sets correct hours" $ do
      let entry = deriveScheduleEntry sampleDiscovered
      hoursPacific entry @?= [11]

  , testCase "deriveScheduleEntry sets atOrAfter False" $ do
      let entry = deriveScheduleEntry sampleDiscovered
      atOrAfter entry @?= False
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
        isRight (parseSeriesConfig "test" configWithoutPriorityUser)

  , testCase "missing priorityUser defaults to Nothing" $
      priorityUser (parseSeries "test" configWithoutPriorityUser) @?= Nothing

  , testCase "parses config with contextSources" $
      let queries = contextQueries (parseSeries "test" configWithCrossSeries)
      in case queries of
        [first, second] -> do
          directories first @?= ["test"]
          limit first @?= Just 7
          directories second @?= ["other-a", "other-b"]
          limitPerSource second @?= Just 1
        _ -> assertBool ("expected 2 queries, got " <> show (length queries)) False

  , testCase "missing contextSources defaults to defaultContextQueries" $
      contextQueries (parseSeries "test" configWithoutPriorityUser) @?= defaultContextQueries "test"

  , testCase "absent contextSources uses defaultContextQueries" $
      contextQueries (parseSeries "test" configWithCrossSeriesFalse) @?= defaultContextQueries "test"

  , testCase "deriveBlogSeriesConfig preserves contextQueries" $ do
      let config = deriveBlogSeriesConfig (parseSeries "test" configWithCrossSeries)
      length (BSC.contextQueries config) @?= 2

  , testCase "deriveBlogSeriesConfig preserves empty contextQueries" $ do
      let config = deriveBlogSeriesConfig sampleDiscovered
      BSC.contextQueries config @?= []

  , testCase "missing enableGrounding defaults to False" $
      let DiscoveredSeries{searchGrounding} = parseSeries "test" configMissingEnableGrounding
      in searchGrounding @?= False

  , testCase "enableGrounding true is parsed correctly" $
      let DiscoveredSeries{searchGrounding} = parseSeries "grounded-series" configWithGrounding
      in searchGrounding @?= True

  , testCase "enableGrounding false is parsed correctly" $
      let DiscoveredSeries{searchGrounding} = parseSeries "ungrounded-series" configWithGroundingFalse
      in searchGrounding @?= False
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
        let DiscoveredSeries{seriesId} = discovered
        in BSC.identifier (deriveBlogSeriesConfig discovered) == seriesId

  , testProperty "deriveBlogSeriesConfig preserves icon" $
      QC.forAll genDiscoveredSeries $ \discovered ->
        BSC.icon (deriveBlogSeriesConfig discovered) == seriesIcon discovered

  , testProperty "deriveBlogSeriesConfig preserves name" $
      QC.forAll genDiscoveredSeries $ \discovered ->
        BSC.name (deriveBlogSeriesConfig discovered) == seriesName discovered

  , testProperty "deriveBlogSeriesRunConfig preserves searchGrounding" $
      QC.forAll genDiscoveredSeries $ \discovered ->
        let runConfigSearchGrounding = Scheduler.searchGrounding (deriveBlogSeriesRunConfig discovered)
            discoveredSearchGrounding = searchGrounding discovered
        in runConfigSearchGrounding == discoveredSearchGrounding
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
  , "  \"models\": [\"gemini-2.5-flash\", \"gemini-2.5-flash-lite\"],"
  , "  \"enableGrounding\": false"
  , "}"
  ]

configWithoutPriorityUser :: T.Text
configWithoutPriorityUser = T.unlines
  [ "{"
  , "  \"name\": \"Solo Bot\","
  , "  \"icon\": \"\129302\","
  , "  \"scheduleHourPacific\": 6,"
  , "  \"models\": [\"gemini-2.5-flash\"],"
  , "  \"enableGrounding\": false"
  , "}"
  ]

configWithNullPriorityUser :: T.Text
configWithNullPriorityUser = T.unlines
  [ "{"
  , "  \"name\": \"Solo Bot\","
  , "  \"icon\": \"\129302\","
  , "  \"priorityUser\": null,"
  , "  \"scheduleHourPacific\": 6,"
  , "  \"models\": [\"gemini-2.5-flash\"],"
  , "  \"enableGrounding\": false"
  , "}"
  ]

configMissingName :: T.Text
configMissingName = T.unlines
  [ "{"
  , "  \"icon\": \"\129793\","
  , "  \"scheduleHourPacific\": 11,"
  , "  \"models\": [\"gemini-2.5-flash\"],"
  , "  \"enableGrounding\": false"
  , "}"
  ]

configEmptyModels :: T.Text
configEmptyModels = T.unlines
  [ "{"
  , "  \"name\": \"Empty Models\","
  , "  \"icon\": \"\10060\","
  , "  \"scheduleHourPacific\": 11,"
  , "  \"models\": [],"
  , "  \"enableGrounding\": false"
  , "}"
  ]

configMissingEnableGrounding :: T.Text
configMissingEnableGrounding = T.unlines
  [ "{"
  , "  \"name\": \"Forgot Grounding Flag\","
  , "  \"icon\": \"\128736\","
  , "  \"scheduleHourPacific\": 11,"
  , "  \"models\": [\"gemini-2.5-flash\"]"
  , "}"
  ]

configWithCrossSeries :: T.Text
configWithCrossSeries = T.unlines
  [ "{"
  , "  \"name\": \"Cross Series Test\","
  , "  \"icon\": \"\128279\","
  , "  \"scheduleHourPacific\": 10,"
  , "  \"models\": [\"gemini-2.5-flash\"],"
  , "  \"contextSources\": [{\"from\": [\"test\"], \"limit\": 7}, {\"from\": [\"other-a\", \"other-b\"], \"limitPerSource\": 1}],"
  , "  \"enableGrounding\": false"
  , "}"
  ]

configWithCrossSeriesFalse :: T.Text
configWithCrossSeriesFalse = T.unlines
  [ "{"
  , "  \"name\": \"No Cross Series\","
  , "  \"icon\": \"\128736\","
  , "  \"scheduleHourPacific\": 11,"
  , "  \"models\": [\"gemini-2.5-flash\"],"
  , "  \"enableGrounding\": false"
  , "}"
  ]

sampleDiscovered :: DiscoveredSeries
sampleDiscovered = DiscoveredSeries
  { seriesId = "garden-thoughts"
  , seriesName = "Garden Thoughts"
  , seriesIcon = "\129793"
  , priorityUser = Just "bagrounds"
  , scheduleTime = TimeOfDay 11 0 0
  , modelChain = Gemini.Gemini25Flash :| [Gemini.Gemini25FlashLite]
  , contextQueries = []
  , searchGrounding = False
  }

configWithGrounding :: T.Text
configWithGrounding = T.unlines
  [ "{"
  , "  \"name\": \"Grounded Series\","
  , "  \"icon\": \"\128269\","
  , "  \"scheduleHourPacific\": 8,"
  , "  \"models\": [\"gemini-2.5-flash\"],"
  , "  \"enableGrounding\": true"
  , "}"
  ]

configWithGroundingFalse :: T.Text
configWithGroundingFalse = T.unlines
  [ "{"
  , "  \"name\": \"Ungrounded Series\","
  , "  \"icon\": \"\128269\","
  , "  \"scheduleHourPacific\": 8,"
  , "  \"models\": [\"gemini-2.5-flash\"],"
  , "  \"enableGrounding\": false"
  , "}"
  ]

genSeriesId :: QC.Gen T.Text
genSeriesId = do
  parts <- QC.listOf1 genWord
  pure (T.intercalate "-" parts)
  where
    genWord = T.pack <$> QC.listOf1 (QC.elements ['a'..'z'])

genDiscoveredSeries :: QC.Gen DiscoveredSeries
genDiscoveredSeries = do
  seriesIdValue <- genSeriesId
  name <- T.pack <$> QC.listOf1 (QC.elements ['A'..'Z'])
  icon <- QC.elements ["\129793", "\129302", "\128020", "\127963\65039", "\127925"]
  priorityUserValue <- QC.oneof [pure Nothing, Just . T.pack <$> QC.listOf1 (QC.elements ['a'..'z'])]
  hour <- QC.choose (0, 23)
  contextQueriesValue <- QC.elements [[], defaultContextQueries seriesIdValue]
  searchGroundingValue <- QC.arbitrary
  pure DiscoveredSeries
    { seriesId = seriesIdValue
    , seriesName = name
    , seriesIcon = icon
    , priorityUser = priorityUserValue
    , scheduleTime = TimeOfDay hour 0 0
    , modelChain = Gemini.Gemini25Flash :| []
    , contextQueries = contextQueriesValue
    , searchGrounding = searchGroundingValue
    }
