module Automation.ObsidianSync.RetryTest (tests) where

import Data.List.NonEmpty (NonEmpty (..))
import qualified Data.List.NonEmpty as NonEmpty
import qualified Data.Text as T
import Data.Time (NominalDiffTime)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, assertEqual, assertBool)
import Test.Tasty.QuickCheck (testProperty, (==>), Gen, Positive (..), NonNegative (..), choose, forAll, elements, listOf1, vectorOf)

import Automation.ObsidianSync.Retry
  ( Attempt (..)
  , Decision (..)
  , FileCount (..)
  , Outcome (..)
  , Policy (..)
  , RetryableSyncFailure (..)
  , StopReason (..)
  , SyncFailure (..)
  , backoffDelay
  , classifySyncFailure
  , consecutiveStalledAttempts
  , decide
  , mkJitter
  , syncPolicy
  )

tests :: TestTree
tests = testGroup "ObsidianSync.Retry"
  [ classifySyncFailureTests
  , backoffDelayTests
  , decideTests
  ]

disconnectedDuringPull :: T.Text
disconnectedDuringPull = T.unlines
  [ "user error (Command: ob sync --path /tmp/obsidian-vault-2165"
  , "Exit code: 1"
  , "Stdout: Starting sync:"
  , "Connection successful. Detecting changes..."
  , "Downloading attachments/topics-spoonfedstudy.jpg"
  , "Disconnected from server"
  , ""
  , "Stderr: Sync error: Error: Disconnected"
  , "    at Zi.disconnect (/opt/hostedtoolcache/node/22.23.3/x64/lib/node_modules/obsidian-headless/cli.js:146:5845)"
  , "Error: Disconnected"
  , "Node.js v22.23.3"
  , ")"
  ]

lockContention :: T.Text
lockContention = T.unlines
  [ "user error (Command: ob sync --path /tmp/obsidian-vault-42"
  , "Exit code: 1"
  , "Stderr: Another sync instance is already running for this vault."
  , ")"
  ]

downloadedFileNamedLikeAnError :: T.Text
downloadedFileNamedLikeAnError = T.unlines
  [ "user error (Command: ob sync --path /tmp/obsidian-vault-7"
  , "Exit code: 1"
  , "Stdout: Downloading notes/Disconnected from server.md"
  , "Stderr: Vault not found"
  , ")"
  ]

classifySyncFailureTests :: TestTree
classifySyncFailureTests = testGroup "classifySyncFailure"
  [ testCase "WebSocket disconnect mid-pull is a lost connection" $
      assertEqual "disconnect" (Retryable ConnectionLost) (classifySyncFailure disconnectedDuringPull)

  , testCase "abnormal close with a status code is a lost connection" $
      assertEqual "close code" (Retryable ConnectionLost)
        (classifySyncFailure "Stderr: Sync error: Error: Disconnected. Code: 1001 Going Away")

  , testCase "failure to connect is a lost connection" $
      assertEqual "unable to connect" (Retryable ConnectionLost)
        (classifySyncFailure "Stderr: Error: Unable to connect to server.")

  , testCase "WebSocket error event is a lost connection" $
      assertEqual "socket error" (Retryable ConnectionLost)
        (classifySyncFailure "Stderr: Error: The connection to the server has encountered an error.")

  , testCase "another sync instance is lock contention" $
      assertEqual "lock" (Retryable LockContention) (classifySyncFailure lockContention)

  , testCase "a file name resembling a disconnect log line is not a lost connection" $
      assertEqual "file name" Unrecoverable
        (classifySyncFailure downloadedFileNamedLikeAnError)

  , testCase "expired subscription is unrecoverable" $
      assertEqual "subscription" Unrecoverable
        (classifySyncFailure "Stderr: Your subscription to Obsidian Sync has expired")

  , testProperty "messages without a known signature are unrecoverable" $ \message ->
      let text = T.pack message
          knownSignatures =
            [ "Another sync instance", "Error: Disconnected"
            , "Unable to connect to server", "The connection to the server has encountered an error" ]
      in not (any (`T.isInfixOf` text) knownSignatures)
           ==> classifySyncFailure text == Unrecoverable

  , testProperty "surrounding output never changes a lost connection classification" $ \prefix suffix ->
      let surrounded = T.pack prefix <> "Stderr: Sync error: Error: Disconnected" <> T.pack suffix
      in not ("Another sync instance" `T.isInfixOf` surrounded)
           ==> classifySyncFailure surrounded == Retryable ConnectionLost
  ]

backoffDelayTests :: TestTree
backoffDelayTests = testGroup "backoffDelay"
  [ testCase "first retry waits between one and two seconds" $ do
      assertEqual "no jitter" 1 (backoffDelay syncPolicy 1 (mkJitter 0))
      assertEqual "full jitter" 2 (backoffDelay syncPolicy 1 (mkJitter 1))

  , testCase "delay doubles with each retry" $
      assertEqual "fourth retry" 16 (backoffDelay syncPolicy 4 (mkJitter 1))

  , testCase "delay is capped at one minute" $
      assertEqual "twentieth retry" 60 (backoffDelay syncPolicy 20 (mkJitter 1))

  , testCase "jitter outside the unit interval is clamped" $ do
      assertEqual "below zero" (backoffDelay syncPolicy 3 (mkJitter 0)) (backoffDelay syncPolicy 3 (mkJitter (-4)))
      assertEqual "above one" (backoffDelay syncPolicy 3 (mkJitter 1)) (backoffDelay syncPolicy 3 (mkJitter 9))

  , testProperty "delay always stays between half the base delay and the maximum delay" $
      \(Positive retryNumber) jitterFraction ->
        let delay = backoffDelay syncPolicy retryNumber (mkJitter jitterFraction)
        in delay >= baseDelay syncPolicy / 2 && delay <= maximumDelay syncPolicy

  , testProperty "delay never shrinks as retries accumulate" $
      \(Positive retryNumber) jitterFraction ->
        let jitter = mkJitter jitterFraction
        in backoffDelay syncPolicy retryNumber jitter <= backoffDelay syncPolicy (retryNumber + 1) jitter
  ]

attemptWith :: Outcome -> Int -> Int -> Attempt
attemptWith outcome before after = Attempt
  { outcome
  , filesBefore = FileCount before
  , filesAfter = FileCount after
  , duration = 60
  }

disconnectAfterDownloading :: Int -> Int -> Attempt
disconnectAfterDownloading = attemptWith (Failed (Retryable ConnectionLost))

stalledDisconnect :: Attempt
stalledDisconnect = disconnectAfterDownloading 900 900

lockContended :: Attempt
lockContended = attemptWith (Failed (Retryable LockContention)) 0 0

historyFromFileCounts :: NonEmpty Int -> NonEmpty Attempt
historyFromFileCounts counts =
  NonEmpty.zipWith disconnectAfterDownloading (0 :| NonEmpty.init counts) counts

tenMinutes :: NominalDiffTime
tenMinutes = 10 * 60

decideMidway :: NonEmpty Attempt -> Decision
decideMidway = decide syncPolicy (mkJitter 0.5) tenMinutes

isRetry :: Decision -> Bool
isRetry (RetryAfter _) = True
isRetry (Stop _) = False

genFailure :: Gen SyncFailure
genFailure = elements [Retryable ConnectionLost, Retryable LockContention, Unrecoverable]

genAttempt :: Gen Attempt
genAttempt = do
  failure <- genFailure
  before <- choose (0, 20000)
  gained <- choose (0, 3000)
  pure (attemptWith (Failed failure) before (before + gained))

decideTests :: TestTree
decideTests = testGroup "decide"
  [ testCase "a completed attempt stops the loop as a success" $
      assertEqual "completed" (Stop SyncCompleted)
        (decideMidway (attemptWith Succeeded 0 10875 :| []))

  , testCase "an unrecoverable failure stops immediately even after progress" $
      assertEqual "unrecoverable" (Stop UnrecoverableFailure)
        (decideMidway (attemptWith (Failed Unrecoverable) 0 4000 :| []))

  , testCase "a lost connection after downloading files is retried" $
      assertBool "retry" (isRetry (decideMidway (disconnectAfterDownloading 0 2804 :| [])))

  , testCase "run 4738 keeps retrying because every attempt downloaded files" $
      assertBool "retry after five progressing retries"
        (isRetry (decideMidway (historyFromFileCounts (2804 :| [7733, 8715, 9523, 9819, 9992]))))

  , testCase "run 4746 keeps retrying because every attempt downloaded files" $
      assertBool "retry after five progressing retries"
        (isRetry (decideMidway (historyFromFileCounts (200 :| [875, 942, 950, 963, 3106]))))

  , testCase "five consecutive stalled retries are still allowed" $
      assertBool "retry" (isRetry (decideMidway (stalledDisconnect :| replicate 4 stalledDisconnect)))

  , testCase "a sixth consecutive stalled failure gives up for lack of progress" $
      assertEqual "no progress" (Stop (NoProgress 6))
        (decideMidway (stalledDisconnect :| replicate 5 stalledDisconnect))

  , testCase "an attempt that downloads files resets the stall count" $
      assertBool "retry"
        (isRetry (decideMidway
          (stalledDisconnect :| replicate 4 stalledDisconnect
            <> [disconnectAfterDownloading 900 950]
            <> replicate 5 (disconnectAfterDownloading 950 950))))

  , testCase "lock contention keeps the old limit of five retries" $
      assertEqual "no progress" (Stop (NoProgress 6))
        (decideMidway (lockContended :| replicate 5 lockContended))

  , testCase "a retry that would start after the deadline gives up" $
      assertEqual "deadline" (Stop (DeadlineReached (deadline syncPolicy + 0.5)))
        (decide syncPolicy (mkJitter 0) (deadline syncPolicy - 0.5) (disconnectAfterDownloading 0 2804 :| []))

  , testCase "a retry that starts exactly at the deadline is allowed" $
      assertBool "retry"
        (isRetry (decide syncPolicy (mkJitter 0) (deadline syncPolicy - 1) (disconnectAfterDownloading 0 2804 :| [])))

  , testProperty "the stall count is the number of trailing attempts without new files" $
      forAll (listOf1 genAttempt) $ \history ->
        consecutiveStalledAttempts (NonEmpty.fromList history)
          == length (takeWhile (\attempt -> filesAfter attempt <= filesBefore attempt) (reverse history))

  , testProperty "retries never start after the deadline" $
      forAll (listOf1 genAttempt) $ \history (NonNegative extraSeconds) jitterFraction ->
        let elapsed = deadline syncPolicy + fromInteger extraSeconds
        in not (isRetry (decide syncPolicy (mkJitter jitterFraction) elapsed (NonEmpty.fromList history)))

  , testProperty "a retry always waits the backoff delay for the next retry number" $
      forAll (listOf1 genAttempt) $ \history jitterFraction ->
        let attempts = NonEmpty.fromList history
            jitter = mkJitter jitterFraction
        in case decide syncPolicy jitter tenMinutes attempts of
             RetryAfter delay -> delay == backoffDelay syncPolicy (length attempts) jitter
             Stop _ -> True

  , testProperty "stalled failures within the stall limit are retried" $
      forAll (choose (1, maximumStalledRetries syncPolicy)) $ \stalledFailures ->
        forAll (genStalledHistory stalledFailures) $ \history ->
          isRetry (decideMidway history)

  , testProperty "stalled failures beyond the stall limit give up for lack of progress" $
      forAll (choose (maximumStalledRetries syncPolicy + 1, 3 * maximumStalledRetries syncPolicy)) $ \stalledFailures ->
        forAll (genStalledHistory stalledFailures) $ \history ->
          decideMidway history == Stop (NoProgress stalledFailures)
  ]

genStalledHistory :: Int -> Gen (NonEmpty Attempt)
genStalledHistory stalledFailures =
  NonEmpty.fromList <$> vectorOf stalledFailures (elements [stalledDisconnect, lockContended])
