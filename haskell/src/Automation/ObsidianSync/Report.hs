module Automation.ObsidianSync.Report
  ( Direction (..)
  , Report (..)
  , describeOutcome
  , describeStopReason
  , formatCount
  , formatDuration
  , formatGain
  , headline
  , render
  ) where

import Data.List.NonEmpty (NonEmpty)
import qualified Data.List.NonEmpty as NonEmpty
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (NominalDiffTime)
import Numeric (showFFloat)

import Automation.ObsidianSync.Retry
  ( Attempt (..)
  , FileCount (..)
  , Outcome (..)
  , RetryableSyncFailure (..)
  , StopReason (..)
  , SyncFailure (..)
  , filesGained
  )

data Direction = Pull | Push
  deriving (Show, Eq, Bounded, Enum)

data Report = Report
  { direction  :: Direction
  , attempts   :: NonEmpty Attempt
  , stopReason :: StopReason
  , elapsed    :: NominalDiffTime
  } deriving (Show, Eq)

directionEmoji :: Direction -> Text
directionEmoji = \case
  Pull -> "📥"
  Push -> "📤"

directionName :: Direction -> Text
directionName = \case
  Pull -> "Obsidian Sync pull"
  Push -> "Obsidian Sync push"

formatDuration :: NominalDiffTime -> Text
formatDuration timeSpan
  | timeSpan < 60 = T.pack (showFFloat (Just 1) (realToFrac timeSpan :: Double) "s")
  | hours == 0 = T.pack (show minutes <> "m " <> show seconds <> "s")
  | otherwise = T.pack (show hours <> "h " <> show minutes <> "m " <> show seconds <> "s")
  where
    totalSeconds = round timeSpan :: Int
    (hours, secondsIntoHour) = totalSeconds `divMod` 3600
    (minutes, seconds) = secondsIntoHour `divMod` 60

formatCount :: Int -> Text
formatCount count
  | count < 0 = "-" <> formatCount (negate count)
  | otherwise = T.reverse . T.intercalate "," . T.chunksOf 3 . T.reverse . T.pack . show $ count

formatGain :: Int -> Text
formatGain gain
  | gain > 0 = "+" <> formatCount gain
  | otherwise = formatCount gain

describeOutcome :: Outcome -> Text
describeOutcome = \case
  Succeeded -> "✅ Completed"
  Failed (Retryable ConnectionLost) -> "🔌 Connection lost"
  Failed (Retryable LockContention) -> "⚠️ Lock contention"
  Failed Unrecoverable -> "🛑 Unrecoverable failure"

describeStopReason :: StopReason -> Text
describeStopReason = \case
  SyncCompleted -> "the sync completed"
  UnrecoverableFailure -> "the last failure cannot be retried"
  NoProgress stalledAttempts ->
    "no new files arrived in the last " <> formatCount stalledAttempts <> " failed attempts"
  DeadlineReached nextRetryStart ->
    "the next retry would start at " <> formatDuration nextRetryStart <> ", past the retry deadline"

pluralizeAttempts :: Int -> Text
pluralizeAttempts = \case
  1 -> "1 attempt"
  count -> formatCount count <> " attempts"

filesOnDisk :: Report -> Text
filesOnDisk Report {..} =
  let FileCount count = filesAfter (NonEmpty.last attempts)
  in formatCount count <> " files on disk"

headline :: Report -> Text
headline report@Report {..} = case stopReason of
  SyncCompleted ->
    "✅ " <> directionName direction <> " completed after " <> attemptsAndTime
      <> ", with " <> filesOnDisk report <> "."
  reason ->
    "🛑 " <> directionName direction <> " gave up after " <> attemptsAndTime
      <> " because " <> describeStopReason reason <> ", with " <> filesOnDisk report <> "."
  where
    attemptsAndTime = pluralizeAttempts (NonEmpty.length attempts) <> " in " <> formatDuration elapsed

attemptRow :: Int -> Attempt -> Text
attemptRow attemptNumber attempt@Attempt {..} =
  let FileCount count = filesAfter
  in "| " <> T.intercalate " | "
       [ formatCount attemptNumber
       , describeOutcome outcome
       , formatDuration duration
       , formatCount count
       , formatGain (filesGained attempt)
       ]
     <> " |"

render :: Report -> Text
render report@Report {..} =
  T.unlines
    ( [ "### " <> directionEmoji direction <> " " <> directionName direction
      , ""
      , headline report
      , ""
      , "| Attempt | Result | Duration | Files on disk | Gained |"
      , "|---:|---|---:|---:|---:|"
      ]
      <> zipWith attemptRow [1 ..] (NonEmpty.toList attempts)
    )
    <> "\n"
