module Automation.ObsidianSync.ReportTest (tests) where

import Data.List.NonEmpty (NonEmpty (..))
import qualified Data.List.NonEmpty as NonEmpty
import qualified Data.Text as T
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, assertEqual, assertBool)
import Test.Tasty.QuickCheck (testProperty, NonNegative (..), choose, forAll, listOf)

import Automation.ObsidianSync.Report
  ( Direction (..)
  , Report (..)
  , formatCount
  , formatDuration
  , formatGain
  , headline
  , render
  )
import Automation.ObsidianSync.Retry
  ( Attempt (..)
  , FileCount (..)
  , Outcome (..)
  , RetryableSyncFailure (..)
  , StopReason (..)
  , SyncFailure (..)
  )

tests :: TestTree
tests = testGroup "ObsidianSync.Report"
  [ formattingTests
  , headlineTests
  , renderTests
  ]

attemptWith :: Outcome -> Int -> Int -> Attempt
attemptWith outcome before after = Attempt
  { outcome
  , filesBefore = FileCount before
  , filesAfter = FileCount after
  , duration = 372
  }

recoveredPull :: Report
recoveredPull = Report
  { direction = Pull
  , attempts =
      attemptWith (Failed (Retryable ConnectionLost)) 0 2804
        :| [ attemptWith (Failed (Retryable ConnectionLost)) 2804 7733
           , attemptWith Succeeded 7733 10852 ]
  , stopReason = SyncCompleted
  , elapsed = 1045
  }

stalledPush :: Report
stalledPush = Report
  { direction = Push
  , attempts = attemptWith (Failed (Retryable LockContention)) 10852 10852 :| []
  , stopReason = NoProgress 6
  , elapsed = 125
  }

formattingTests :: TestTree
formattingTests = testGroup "formatting"
  [ testCase "short durations keep one decimal place" $
      assertEqual "seconds" "1.4s" (formatDuration 1.42)

  , testCase "minute durations show minutes and seconds" $
      assertEqual "minutes" "6m 12s" (formatDuration 372)

  , testCase "hour durations show hours, minutes, and seconds" $
      assertEqual "hours" "1h 2m 3s" (formatDuration 3723)

  , testCase "counts use thousands separators" $ do
      assertEqual "zero" "0" (formatCount 0)
      assertEqual "hundreds" "999" (formatCount 999)
      assertEqual "thousands" "10,734" (formatCount 10734)
      assertEqual "millions" "1,000,000" (formatCount 1000000)

  , testCase "gains are signed" $ do
      assertEqual "positive" "+2,804" (formatGain 2804)
      assertEqual "zero" "0" (formatGain 0)
      assertEqual "negative" "-3" (formatGain (-3))

  , testProperty "removing separators from a formatted count gives back the number" $
      \(NonNegative count) -> T.filter (/= ',') (formatCount count) == T.pack (show count)
  ]

headlineTests :: TestTree
headlineTests = testGroup "headline"
  [ testCase "a recovered pull reports success, attempts, time, and files" $
      assertEqual "recovered"
        "✅ Obsidian Sync pull completed after 3 attempts in 17m 25s, with 10,852 files on disk."
        (headline recoveredPull)

  , testCase "an abandoned push explains why it gave up" $
      assertEqual "abandoned"
        "🛑 Obsidian Sync push gave up after 1 attempt in 2m 5s because no new files arrived in the last 6 failed attempts, with 10,852 files on disk."
        (headline stalledPush)
  ]

renderTests :: TestTree
renderTests = testGroup "render"
  [ testCase "the report starts with a heading and the headline" $
      assertBool "heading and headline"
        (T.isPrefixOf ("### 📥 Obsidian Sync pull\n\n" <> headline recoveredPull) (render recoveredPull))

  , testCase "each attempt describes its result, duration, and files" $
      assertBool "first attempt"
        (T.isInfixOf "| 1 | 🔌 Connection lost | 6m 12s | 2,804 | +2,804 |" (render recoveredPull))

  , testCase "the final attempt of a successful pull is marked completed" $
      assertBool "completed attempt"
        (T.isInfixOf "| 3 | ✅ Completed | 6m 12s | 10,852 | +3,119 |" (render recoveredPull))

  , testCase "the report ends with a blank line so later sections stay separate" $
      assertBool "trailing newline" (T.isSuffixOf "\n\n" (render stalledPush))

  , testProperty "the table has one row per attempt" $
      forAll (listOf (choose (0, 500))) $ \gains ->
        let fileCounts = scanl (+) 0 gains
            attemptList = zipWith (attemptWith (Failed (Retryable ConnectionLost))) fileCounts (drop 1 fileCounts)
            report = recoveredPull { attempts = attemptWith Succeeded 0 0 :| attemptList }
            tableRows = filter (T.isPrefixOf "| ") (T.lines (render report))
        in length tableRows == NonEmpty.length (attempts report) + 1
  ]
