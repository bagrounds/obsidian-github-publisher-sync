module Automation.BlogSeriesDiscoveryTest (tests) where

import Data.List.NonEmpty (NonEmpty ((:|)))
import qualified Data.Text as T
import Data.Time.LocalTime (TimeOfDay (..))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))
import Test.Tasty.QuickCheck (testProperty)
import qualified Test.QuickCheck as QC

import qualified Automation.Gemini as Gemini
import qualified Automation.BlogSeriesConfig as BSC
import Automation.BlogSeriesDiscovery
import Automation.ContextQuery (defaultContextQueries)
import Automation.Scheduler (TaskId (..), ScheduleEntry (..))
import qualified Automation.Scheduler as Scheduler

tests :: TestTree
tests = testGroup "BlogSeriesDiscovery"
  [ derivationTests
  , contextQueryTests
  , properties
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
      let config = deriveBlogSeriesConfig sampleSeries
      BSC.identifier config @?= "garden-thoughts"

  , testCase "deriveBlogSeriesConfig derives author" $ do
      let config = deriveBlogSeriesConfig sampleSeries
      BSC.author config @?= "[[garden-thoughts]]"

  , testCase "deriveBlogSeriesConfig derives base URL" $ do
      let config = deriveBlogSeriesConfig sampleSeries
      BSC.baseUrl config @?= "https://bagrounds.org/garden-thoughts"

  , testCase "deriveBlogSeriesConfig preserves priority user" $ do
      let config = deriveBlogSeriesConfig sampleSeries
      BSC.priorityUser config @?= Just "bagrounds"

  , testCase "deriveBlogSeriesRunConfig sets correct series ID" $ do
      let config = deriveBlogSeriesRunConfig sampleSeries
      Scheduler.seriesId config @?= "garden-thoughts"

  , testCase "deriveBlogSeriesRunConfig sets correct model chain" $ do
      let config = deriveBlogSeriesRunConfig sampleSeries
      Scheduler.modelChain config @?= (Gemini.Gemini25Flash :| [Gemini.Gemini25FlashLite])

  , testCase "deriveBlogSeriesRunConfig sets correct env var" $ do
      let config = deriveBlogSeriesRunConfig sampleSeries
      Scheduler.priorityUserEnvVar config @?= "GARDEN_THOUGHTS_PRIORITY_USER"

  , testCase "deriveBlogSeriesRunConfig sets searchGrounding false for sampleSeries" $ do
      let config = deriveBlogSeriesRunConfig sampleSeries
      Scheduler.searchGrounding config @?= False

  , testCase "deriveBlogSeriesRunConfig passes searchGrounding true when set" $ do
      let config = deriveBlogSeriesRunConfig sampleSeries { searchGrounding = True }
      Scheduler.searchGrounding config @?= True

  , testCase "deriveScheduleEntry sets correct task ID" $ do
      let entry = deriveScheduleEntry sampleSeries
      taskId entry @?= BlogSeries "garden-thoughts"

  , testCase "deriveScheduleEntry sets correct hours" $ do
      let entry = deriveScheduleEntry sampleSeries
      hoursPacific entry @?= [11]

  , testCase "deriveScheduleEntry sets atOrAfter False" $ do
      let entry = deriveScheduleEntry sampleSeries
      atOrAfter entry @?= False
  ]

contextQueryTests :: TestTree
contextQueryTests = testGroup "context queries"
  [ testCase "deriveBlogSeriesConfig preserves contextQueries" $ do
      let discovered = sampleSeries { contextQueries = defaultContextQueries "garden-thoughts" }
          config = deriveBlogSeriesConfig discovered
      length (BSC.contextQueries config) @?= 1

  , testCase "deriveBlogSeriesConfig preserves empty contextQueries" $ do
      let config = deriveBlogSeriesConfig sampleSeries
      BSC.contextQueries config @?= []
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
      QC.forAll genAutoBlogSeries $ \discovered ->
        let AutoBlogSeries{seriesId} = discovered
        in BSC.identifier (deriveBlogSeriesConfig discovered) == seriesId

  , testProperty "deriveBlogSeriesConfig preserves icon" $
      QC.forAll genAutoBlogSeries $ \discovered ->
        BSC.icon (deriveBlogSeriesConfig discovered) == seriesIcon discovered

  , testProperty "deriveBlogSeriesConfig preserves name" $
      QC.forAll genAutoBlogSeries $ \discovered ->
        BSC.name (deriveBlogSeriesConfig discovered) == seriesName discovered

  , testProperty "deriveBlogSeriesRunConfig preserves searchGrounding" $
      QC.forAll genAutoBlogSeries $ \discovered ->
        let runConfigSearchGrounding = Scheduler.searchGrounding (deriveBlogSeriesRunConfig discovered)
            discoveredSearchGrounding = searchGrounding discovered
        in runConfigSearchGrounding == discoveredSearchGrounding
  ]

sampleSeries :: AutoBlogSeries
sampleSeries = AutoBlogSeries
  { seriesId = "garden-thoughts"
  , seriesName = "Garden Thoughts"
  , seriesIcon = "\129793"
  , priorityUser = Just "bagrounds"
  , scheduleTime = TimeOfDay 11 0 0
  , modelChain = Gemini.Gemini25Flash :| [Gemini.Gemini25FlashLite]
  , contextQueries = []
  , searchGrounding = False
  }

genSeriesId :: QC.Gen T.Text
genSeriesId = do
  parts <- QC.listOf1 genWord
  pure (T.intercalate "-" parts)
  where
    genWord = T.pack <$> QC.listOf1 (QC.elements ['a'..'z'])

genAutoBlogSeries :: QC.Gen AutoBlogSeries
genAutoBlogSeries = do
  seriesIdValue <- genSeriesId
  name <- T.pack <$> QC.listOf1 (QC.elements ['A'..'Z'])
  icon <- QC.elements ["\129793", "\129302", "\128020", "\127963\65039", "\127925"]
  priorityUserValue <- QC.oneof [pure Nothing, Just . T.pack <$> QC.listOf1 (QC.elements ['a'..'z'])]
  hour <- QC.choose (0, 23)
  contextQueriesValue <- QC.elements [[], defaultContextQueries seriesIdValue]
  searchGroundingValue <- QC.arbitrary
  pure AutoBlogSeries
    { seriesId = seriesIdValue
    , seriesName = name
    , seriesIcon = icon
    , priorityUser = priorityUserValue
    , scheduleTime = TimeOfDay hour 0 0
    , modelChain = Gemini.Gemini25Flash :| []
    , contextQueries = contextQueriesValue
    , searchGrounding = searchGroundingValue
    }
