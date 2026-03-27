module Automation.SchedulerTest (tests) where

import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)

import Automation.Scheduler

tests :: TestTree
tests = testGroup "Scheduler"
  [ testCase "getScheduledTasks at hour 7 includes chickie-loo" $
      assertBool "chickie-loo should be scheduled" $
        BlogSeriesChickieLoo `elem` getScheduledTasks 7

  , testCase "getScheduledTasks at hour 6 excludes chickie-loo" $
      assertBool "chickie-loo should not be scheduled before 7" $
        BlogSeriesChickieLoo `notElem` getScheduledTasks 6

  , testCase "blog series uses at-or-after semantics" $
      assertBool "chickie-loo at hour 10 (after 7)" $
        BlogSeriesChickieLoo `elem` getScheduledTasks 10

  , testCase "backfill runs every hour" $
      assertBool "backfill at hour 3" $
        BackfillBlogImages `elem` getScheduledTasks 3

  , testCase "social-posting runs at even hours" $
      assertBool "social-posting at hour 4" $
        SocialPosting `elem` getScheduledTasks 4

  , testCase "social-posting skipped at odd hours" $
      assertBool "social-posting not at hour 5" $
        SocialPosting `notElem` getScheduledTasks 5

  , testCase "ai-fiction eligible at hour 22" $
      assertBool "ai-fiction at 22" $
        AiFiction `elem` getScheduledTasks 22

  , testCase "ai-fiction not eligible before 22" $
      assertBool "ai-fiction not at 21" $
        AiFiction `notElem` getScheduledTasks 21

  , testCase "reflection-title eligible at hour 23" $
      assertBool "reflection-title at 23 (at-or-after 22)" $
        ReflectionTitle `elem` getScheduledTasks 23

  , testCase "isValidTaskId accepts known IDs" $
      isValidTaskId "backfill-blog-images" @?= True

  , testCase "isValidTaskId rejects unknown IDs" $
      isValidTaskId "unknown-task" @?= False

  , testCase "extractSeriesId from blog-series task" $
      extractSeriesId BlogSeriesChickieLoo @?= Just "chickie-loo"

  , testCase "extractSeriesId from non-series task" $
      extractSeriesId BackfillBlogImages @?= Nothing

  , testCase "taskIdToText round-trips" $
      taskIdFromText (taskIdToText SocialPosting) @?= Just SocialPosting

  , testCase "all task IDs are valid" $
      assertBool "all valid" $
        all (\t -> isValidTaskId (taskIdToText t)) [minBound .. maxBound]
  ]
