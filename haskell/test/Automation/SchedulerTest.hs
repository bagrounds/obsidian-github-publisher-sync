module Automation.SchedulerTest (tests) where

import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import Test.Tasty.QuickCheck (testProperty)
import qualified Test.QuickCheck as QC

import Automation.Scheduler
import Automation.PacificTime (pacificHour)
import Automation.TestGenerators (genUTCTime)

testDynamicEntries :: [ScheduleEntry]
testDynamicEntries =
  [ ScheduleEntry (BlogSeries "chickie-loo") [7] False
  , ScheduleEntry (BlogSeries "auto-blog-zero") [8] False
  , ScheduleEntry (BlogSeries "systems-for-public-good") [9] False
  ]

testSchedule :: [ScheduleEntry]
testSchedule = buildSchedule testDynamicEntries

testBlogSeriesTaskIds :: [TaskId]
testBlogSeriesTaskIds = fmap seTaskId testDynamicEntries

tests :: TestTree
tests = testGroup "Scheduler"
  [ testCase "getScheduledTasks at hour 7 includes chickie-loo" $
      assertBool "chickie-loo should be scheduled" $
        BlogSeries "chickie-loo" `elem` getScheduledTasks testSchedule 7

  , testCase "getScheduledTasks at hour 6 excludes chickie-loo" $
      assertBool "chickie-loo should not be scheduled before 7" $
        BlogSeries "chickie-loo" `notElem` getScheduledTasks testSchedule 6

  , testCase "blog series uses at-or-after semantics" $
      assertBool "chickie-loo at hour 10 (after 7)" $
        BlogSeries "chickie-loo" `elem` getScheduledTasks testSchedule 10

  , testCase "backfill runs every hour" $
      assertBool "backfill at hour 3" $
        BackfillBlogImages `elem` getScheduledTasks testSchedule 3

  , testCase "social-posting runs at even hours" $
      assertBool "social-posting at hour 4" $
        SocialPosting `elem` getScheduledTasks testSchedule 4

  , testCase "social-posting skipped at odd hours" $
      assertBool "social-posting not at hour 5" $
        SocialPosting `notElem` getScheduledTasks testSchedule 5

  , testCase "ai-fiction eligible at hour 22" $
      assertBool "ai-fiction at 22" $
        AiFiction `elem` getScheduledTasks testSchedule 22

  , testCase "ai-fiction not eligible before 22" $
      assertBool "ai-fiction not at 21" $
        AiFiction `notElem` getScheduledTasks testSchedule 21

  , testCase "reflection-title eligible at hour 23" $
      assertBool "reflection-title at 23 (at-or-after 22)" $
        ReflectionTitle `elem` getScheduledTasks testSchedule 23

  , testCase "isValidTaskId accepts known IDs" $
      isValidTaskId testSchedule "backfill-blog-images" @?= True

  , testCase "isValidTaskId rejects unknown IDs" $
      isValidTaskId testSchedule "unknown-task" @?= False

  , testCase "extractSeriesId from blog-series task" $
      extractSeriesId (BlogSeries "chickie-loo") @?= Just "chickie-loo"

  , testCase "extractSeriesId from non-series task" $
      extractSeriesId BackfillBlogImages @?= Nothing

  , testCase "taskIdToText round-trips for static tasks" $
      taskIdFromText [] (taskIdToText SocialPosting) @?= Just SocialPosting

  , testCase "taskIdToText round-trips for blog series" $
      taskIdFromText testBlogSeriesTaskIds (taskIdToText (BlogSeries "chickie-loo"))
        @?= Just (BlogSeries "chickie-loo")

  , testCase "all static task IDs are valid" $
      assertBool "all valid" $
        all (isValidTaskId testSchedule . taskIdToText)
          [BackfillBlogImages, InternalLinking, SocialPosting, AiFiction, ReflectionTitle]

  , testCase "all blog series task IDs are valid" $
      assertBool "all valid" $
        all (isValidTaskId testSchedule . taskIdToText)
          [BlogSeries "chickie-loo", BlogSeries "auto-blog-zero", BlogSeries "systems-for-public-good"]

  , pacificHourTests
  , blogPostMatchesTodayTests
  ]

pacificHourTests :: TestTree
pacificHourTests = testGroup "pacificHour"
  [ testProperty "result is always 0-23" $
      QC.forAll genUTCTime $ \utc ->
        let h = pacificHour utc
        in h >= 0 && h <= 23

  , testCase "PST: midnight UTC on Jan 1 is 4pm previous day" $
      pacificHour (UTCTime (fromGregorian 2026 1 1) 0) @?= 16

  , testCase "PST: noon UTC on Jan 15 is 4am Pacific" $
      pacificHour (UTCTime (fromGregorian 2026 1 15) (secondsToDiffTime (12 * 3600))) @?= 4

  , testCase "PDT: noon UTC on Jul 15 is 5am Pacific" $
      pacificHour (UTCTime (fromGregorian 2026 7 15) (secondsToDiffTime (12 * 3600))) @?= 5

  , testCase "PDT: midnight UTC on Jul 1 is 5pm previous day" $
      pacificHour (UTCTime (fromGregorian 2026 7 1) 0) @?= 17
  ]

blogPostMatchesTodayTests :: TestTree
blogPostMatchesTodayTests = testGroup "blogPostMatchesToday"
  [ testCase "matches file starting with today" $
      blogPostMatchesToday "2026-04-08" ["2026-04-08-my-post.md"] @?= True

  , testCase "no match when no files" $
      blogPostMatchesToday "2026-04-08" [] @?= False

  , testCase "no match when files are different dates" $
      blogPostMatchesToday "2026-04-08" ["2026-04-07-old.md", "2026-04-09-future.md"] @?= False

  , testCase "matches among multiple files" $
      blogPostMatchesToday "2026-04-08"
        ["2026-04-07-old.md", "2026-04-08-today.md", "index.md"] @?= True

  , testCase "ignores non-date files" $
      blogPostMatchesToday "2026-04-08" ["readme.md", "index.md"] @?= False
  ]
