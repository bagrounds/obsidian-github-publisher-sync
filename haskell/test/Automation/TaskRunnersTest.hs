module Automation.TaskRunnersTest (tests) where

import Data.List.NonEmpty (NonEmpty ((:|)))
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.LocalTime (TimeOfDay (..))
import Network.HTTP.Client (newManager, defaultManagerSettings)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import Test.Tasty.QuickCheck (testProperty)
import qualified Test.QuickCheck as QC

import Automation.Context (AppContext, mkAppContext)
import Automation.BlogSeriesDiscovery (DiscoveredSeries (..))
import qualified Automation.Gemini as Gemini
import Automation.ObsidianSync (ObsidianCredentials (..))
import Automation.Scheduler (TaskId (..))
import Automation.Secret (Secret (..))
import Automation.TaskRunners (taskRunners)

mkTestContext :: IO AppContext
mkTestContext = do
  manager <- newManager defaultManagerSettings
  let credentials = ObsidianCredentials
        { ocAuthToken = Secret "test-token"
        , ocVaultName = "test-vault"
        , ocVaultPassword = Nothing
        }
  case mkAppContext manager "/tmp/vault" "/tmp/repo" (Secret "test-key") credentials of
    Right context -> pure context
    Left err -> fail $ "Failed to create test context: " <> err

mkTestSeries :: Text -> DiscoveredSeries
mkTestSeries seriesId = DiscoveredSeries
  { dsId = seriesId
  , dsName = "Test Series " <> seriesId
  , dsIcon = "🧪"
  , dsPriorityUser = Nothing
  , dsScheduleTime = TimeOfDay 6 0 0
  , dsModels = Gemini.Gemini25Flash :| []
  , dsContextQueries = []
  , dsEnableGrounding = False
  }

tests :: TestTree
tests = testGroup "TaskRunners"
  [ taskRunnersRegistryTests
  , taskRunnersPropertyTests
  ]

taskRunnersRegistryTests :: TestTree
taskRunnersRegistryTests = testGroup "taskRunners registry"
  [ testCase "includes all static task runners" $ do
      context <- mkTestContext
      let runners = taskRunners context Map.empty Map.empty [] []
          expectedStaticTasks =
            [ BackfillBlogImages
            , InternalLinking
            , SocialPosting
            , AiFiction
            , ReflectionTitle
            , DailyAnalytics
            ]
      mapM_ (\taskIdentifier ->
        assertBool ("runner registered for " <> show taskIdentifier) $
          Map.member taskIdentifier runners
        ) expectedStaticTasks

  , testCase "static runner count is 6 with no blog series" $ do
      context <- mkTestContext
      let runners = taskRunners context Map.empty Map.empty [] []
      Map.size runners @?= 6

  , testCase "includes dynamic blog series runners" $ do
      context <- mkTestContext
      let discovered =
            [ mkTestSeries "test-series"
            , mkTestSeries "other-series"
            ]
          runners = taskRunners context Map.empty Map.empty [] discovered
      assertBool "test-series registered" $
        Map.member (BlogSeries "test-series") runners
      assertBool "other-series registered" $
        Map.member (BlogSeries "other-series") runners

  , testCase "total runner count includes blog series" $ do
      context <- mkTestContext
      let discovered =
            [ mkTestSeries "series-a"
            , mkTestSeries "series-b"
            ]
          runners = taskRunners context Map.empty Map.empty [] discovered
      Map.size runners @?= 8
  ]

taskRunnersPropertyTests :: TestTree
taskRunnersPropertyTests = testGroup "properties"
  [ testProperty "runner count equals 6 plus number of unique blog series" $
      QC.forAll genUniqueSeriesIds $ \seriesIds -> QC.ioProperty $ do
        context <- mkTestContext
        let discovered = fmap mkTestSeries seriesIds
            runners = taskRunners context Map.empty Map.empty [] discovered
        pure (Map.size runners == 6 + length seriesIds)

  , testProperty "all static tasks are always registered" $
      QC.forAll genUniqueSeriesIds $ \seriesIds -> QC.ioProperty $ do
        context <- mkTestContext
        let discovered = fmap mkTestSeries seriesIds
            runners = taskRunners context Map.empty Map.empty [] discovered
            staticTasks = [BackfillBlogImages, InternalLinking, SocialPosting, AiFiction, ReflectionTitle, DailyAnalytics]
        pure (all (`Map.member` runners) staticTasks)
  ]

genUniqueSeriesIds :: QC.Gen [Text]
genUniqueSeriesIds = fmap (fmap (T.pack . QC.getASCIIString) . deduplicate) (QC.listOf (QC.resize 10 QC.arbitrary))
  where
    deduplicate = Map.elems . Map.fromList . fmap (\asciiString -> (QC.getASCIIString asciiString, asciiString))
