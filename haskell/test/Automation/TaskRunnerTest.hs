module Automation.TaskRunnerTest (tests) where

import Control.Exception (throwIO, ErrorCall (..), try, SomeException, fromException)
import Data.IORef (newIORef, readIORef, modifyIORef')
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Text as T
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import Test.Tasty.QuickCheck (testProperty)
import qualified Test.QuickCheck as QC

import Automation.Scheduler (TaskId (..))
import Automation.TaskRunner (TaskError (..), failTask, interTaskDelayMicroseconds, inferenceDashboards, runTasksWithDelay)

tests :: TestTree
tests = testGroup "TaskRunner"
  [ runTasksTests
  , taskErrorTests
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

taskErrorTests :: TestTree
taskErrorTests = testGroup "TaskError"
  [ testCase "Show displays message without constructor" $ do
      let err = TaskError "something went wrong"
      show err @?= "something went wrong"

  , testCase "Show preserves unicode in message" $ do
      let err = TaskError "Blog generation failed: ❌ rate limit"
      show err @?= "Blog generation failed: ❌ rate limit"

  , testCase "failTask throws TaskError catchable as SomeException" $ do
      result <- try (failTask "test failure") :: IO (Either SomeException ())
      case result of
        Left exception ->
          assertBool "exception message contains test failure" $
            "test failure" `T.isInfixOf` T.pack (show exception)
        Right () -> fail "Expected exception but got success"

  , testCase "failTask throws TaskError with correct message" $ do
      result <- try (failTask "specific error message") :: IO (Either SomeException ())
      case result of
        Left exception -> case fromException exception of
          Just (TaskError message) -> message @?= "specific error message"
          Nothing -> fail "Expected TaskError but got different exception type"
        Right () -> fail "Expected exception but got success"

  , testCase "TaskError caught by runTasks marks task as failed" $ do
      let runners = Map.fromList [(SocialPosting, failTask "task error")]
      results <- runTasksWithDelay 0 runners [SocialPosting]
      case results of
        [(taskIdentifier, success, Just errorMessage)] -> do
          taskIdentifier @?= SocialPosting
          success @?= False
          assertBool "error message contains task error" $
            "task error" `T.isInfixOf` errorMessage
        _ -> fail $ "Expected single failed result, got: " <> show results

  , testCase "TaskError message appears in run summary" $ do
      let runners = Map.fromList [(AiFiction, failTask "Gemini API error: rate limited")]
      results <- runTasksWithDelay 0 runners [AiFiction]
      case results of
        [(_, False, Just errorMessage)] ->
          errorMessage @?= "Gemini API error: rate limited"
        _ -> fail $ "Expected failed result with message, got: " <> show results
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
        all (\(_, url) -> T.isPrefixOf "https://" url) inferenceDashboards
  ]

properties :: TestTree
properties = testGroup "properties"
  [ testProperty "result count always equals task count" $
      QC.forAll genTaskList $ \taskIdentifiers -> QC.ioProperty $ do
        let runners = Map.fromList (fmap (, pure ()) taskIdentifiers)
        results <- runTasksWithDelay 0 runners taskIdentifiers
        pure (length results == length taskIdentifiers)

  , testProperty "all tasks in results match input tasks" $
      QC.forAll genTaskList $ \taskIdentifiers -> QC.ioProperty $ do
        let runners = Map.fromList (fmap (, pure ()) taskIdentifiers)
        results <- runTasksWithDelay 0 runners taskIdentifiers
        let resultIds = fmap (\(taskIdentifier, _, _) -> taskIdentifier) results
        pure (resultIds == taskIdentifiers)

  , testProperty "failTask message round-trips through catch" $
      QC.forAll (QC.arbitrary :: QC.Gen String) $ \arbitraryMessage -> QC.ioProperty $ do
        let textMessage = T.pack arbitraryMessage
        result <- try (failTask textMessage) :: IO (Either SomeException ())
        pure $ case result of
          Left exception -> T.pack (show exception) == textMessage
          Right () -> False
  ]

genTaskList :: QC.Gen [TaskId]
genTaskList = QC.sublistOf allTaskIds
  where
    allTaskIds =
      [ BlogSeries "chickie-loo"
      , BlogSeries "auto-blog-zero"
      , BlogSeries "systems-for-public-good"
      , BackfillBlogImages
      , InternalLinking
      , SocialPosting
      , AiFiction
      , ReflectionTitle
      ]
