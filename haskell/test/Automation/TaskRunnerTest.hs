module Automation.TaskRunnerTest (tests) where

import Control.Exception (throwIO, ErrorCall (..))
import Data.IORef (newIORef, readIORef, modifyIORef')
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import Test.Tasty.QuickCheck (testProperty)
import qualified Test.QuickCheck as QC

import Automation.Scheduler (TaskId (..))
import Automation.TaskRunner (TaskResult, interTaskDelayMicroseconds, inferenceDashboards, runTasksWithDelay)

tests :: TestTree
tests = testGroup "TaskRunner"
  [ runTasksTests
  , constantsTests
  , properties
  ]

runTasksTests :: TestTree
runTasksTests = testGroup "runTasks"
  [ testCase "empty task list returns empty results" $ do
      let runners = Map.empty :: Map TaskId (IO ())
      results <- runTasksWithDelay 0 runners []
      results @?= []

  , testCase "successful task returns True with no error" $ do
      let runners = Map.fromList [(SocialPosting, pure ())]
      results <- runTasksWithDelay 0 runners [SocialPosting]
      results @?= [(SocialPosting, True, Nothing)]

  , testCase "failing task returns False with error message" $ do
      let runners = Map.fromList [(AiFiction, throwIO (ErrorCall "test failure"))]
      results <- runTasksWithDelay 0 runners [AiFiction]
      case results of
        [(taskIdentifier, success, Just _)] -> do
          taskIdentifier @?= AiFiction
          success @?= False
        _ -> fail $ "Expected single failed result, got: " <> show (length results)

  , testCase "unknown task returns False with no runner message" $ do
      let runners = Map.empty :: Map TaskId (IO ())
      results <- runTasksWithDelay 0 runners [InternalLinking]
      results @?= [(InternalLinking, False, Just "no runner registered")]

  , testCase "mixed results preserve order" $ do
      let runners = Map.fromList
            [ (SocialPosting, pure ())
            , (AiFiction, throwIO (ErrorCall "boom"))
            , (ReflectionTitle, pure ())
            ]
      results <- runTasksWithDelay 0 runners [SocialPosting, AiFiction, ReflectionTitle]
      case results of
        [(identifier1, success1, _), (identifier2, success2, _), (identifier3, success3, _)] -> do
          identifier1 @?= SocialPosting
          success1 @?= True
          identifier2 @?= AiFiction
          success2 @?= False
          identifier3 @?= ReflectionTitle
          success3 @?= True
        _ -> fail $ "Expected 3 results, got: " <> show (length results)

  , testCase "tasks execute in order" $ do
      executionOrder <- newIORef ([] :: [TaskId])
      let runners = Map.fromList
            [ (SocialPosting, modifyIORef' executionOrder (SocialPosting :))
            , (ReflectionTitle, modifyIORef' executionOrder (ReflectionTitle :))
            ]
      _ <- runTasksWithDelay 0 runners [SocialPosting, ReflectionTitle]
      order <- readIORef executionOrder
      order @?= [ReflectionTitle, SocialPosting]

  , testCase "result count equals input count" $ do
      let runners = Map.fromList
            [ (SocialPosting, pure ())
            , (AiFiction, pure ())
            ]
      results <- runTasksWithDelay 0 runners [SocialPosting, AiFiction]
      length results @?= 2
  ]

constantsTests :: TestTree
constantsTests = testGroup "constants"
  [ testCase "interTaskDelayMicroseconds is 30 seconds" $
      interTaskDelayMicroseconds @?= 30000000

  , testCase "inferenceDashboards has 5 entries" $
      length inferenceDashboards @?= 5

  , testCase "all dashboard entries have non-empty names" $
      assertBool "all names non-empty" $
        all (\(name, _) -> name /= "") inferenceDashboards

  , testCase "all dashboard URLs start with https" $
      assertBool "all URLs start with https" $
        all (\(_, url) -> "https://" `isPrefixOfText` url) inferenceDashboards
  ]

properties :: TestTree
properties = testGroup "properties"
  [ testProperty "result count always equals task count" $
      QC.forAll genTaskList $ \taskIdentifiers -> QC.ioProperty $ do
        let runners = Map.fromList (fmap (\taskIdentifier -> (taskIdentifier, pure ())) taskIdentifiers)
        results <- runTasksWithDelay 0 runners taskIdentifiers
        pure (length results == length taskIdentifiers)

  , testProperty "all tasks in results match input tasks" $
      QC.forAll genTaskList $ \taskIdentifiers -> QC.ioProperty $ do
        let runners = Map.fromList (fmap (\taskIdentifier -> (taskIdentifier, pure ())) taskIdentifiers)
        results <- runTasksWithDelay 0 runners taskIdentifiers
        let resultIds = fmap (\(taskIdentifier, _, _) -> taskIdentifier) results
        pure (resultIds == taskIdentifiers)
  ]

isPrefixOfText :: Text -> Text -> Bool
isPrefixOfText prefix text = prefix == T.take (T.length prefix) text

genTaskList :: QC.Gen [TaskId]
genTaskList = QC.sublistOf allTaskIds
  where
    allTaskIds =
      [ BlogSeriesChickieLoo
      , BlogSeriesAutoBlogZero
      , BlogSeriesSystemsForPublicGood
      , BackfillBlogImages
      , InternalLinking
      , SocialPosting
      , AiFiction
      , ReflectionTitle
      ]
