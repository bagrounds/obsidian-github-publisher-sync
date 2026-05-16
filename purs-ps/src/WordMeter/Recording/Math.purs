module WordMeter.Recording.Math
  ( activeListeningMs
  , wallSpanMs
  , wordsInTrailingWindow
  , wordsPerMinute
  , shortRate
  , longRate
  , overallRate
  , intervalDurationMs
  , intervalRate
  , captionOpacity
  , formatRate
  , formatDurationMs
  , millisecondsBetween
  ) where

import Prelude

import Data.Array (filter, foldl)
import Data.DateTime.Instant (Instant, diff)
import Data.Int as Int
import Data.Maybe (Maybe(..))
import Data.Number (isFinite)
import Data.Time.Duration (Milliseconds(..))
import WordMeter.Recording.Session
  ( LoggedInterval
  , Session
  , captionWindowMs
  , longWindowMs
  , minimumCaptionOpacity
  , shortWindowMs
  )

millisecondsPerMinute :: Number
millisecondsPerMinute = 60000.0

millisecondsPerSecond :: Number
millisecondsPerSecond = 1000.0

-- | Compute the signed difference `a - b` in milliseconds.
-- | Wraps `Data.DateTime.Instant.diff` and unwraps the result so
-- | arithmetic expressions remain readable without reintroducing raw
-- | `Number` timestamps.
millisecondsBetween :: Instant -> Instant -> Number
millisecondsBetween a b =
  let Milliseconds ms = (diff a b :: Milliseconds)
  in ms

activeListeningMs :: Session -> Number
activeListeningMs session =
  let Milliseconds completed = session.completedActiveMs
  in
    completed + case session.currentIntervalStart of
      Just start -> max 0.0 (millisecondsBetween session.now start)
      Nothing -> 0.0

wallSpanMs :: Session -> Number
wallSpanMs session = case session.firstStartedAt of
  Nothing -> 0.0
  Just first -> max 0.0 (millisecondsBetween session.now first)

wordsInTrailingWindow :: Number -> Session -> Int
wordsInTrailingWindow windowMs session =
  let
    inWindow event =
      millisecondsBetween session.now event.timestamp <= windowMs
  in
    foldl (\acc event -> acc + event.wordCount) 0
      (filter inWindow session.wordEvents)

wordsPerMinute :: Int -> Number -> Number
wordsPerMinute wordCount elapsedMs
  | elapsedMs <= 0.0 = 0.0
  | otherwise = Int.toNumber wordCount * millisecondsPerMinute / elapsedMs

intervalDurationMs :: LoggedInterval -> Number
intervalDurationMs interval =
  max 0.0 (millisecondsBetween interval.endedAt interval.startedAt)

intervalRate :: LoggedInterval -> Number
intervalRate interval =
  wordsPerMinute interval.wordCount (max 1.0 (intervalDurationMs interval))

captionOpacity :: Instant -> Instant -> Number
captionOpacity nowInstant captionTimestamp =
  let
    ageFraction =
      max 0.0 (millisecondsBetween nowInstant captionTimestamp) / captionWindowMs
  in
    max minimumCaptionOpacity (1.0 - ageFraction)

shortRate :: Session -> Number
shortRate session =
  let
    elapsed = min shortWindowMs (max 1.0 (wallSpanMs session))
  in
    wordsPerMinute (wordsInTrailingWindow shortWindowMs session) elapsed

longRate :: Session -> Number
longRate session =
  let
    elapsed = min longWindowMs (max 1.0 (wallSpanMs session))
  in
    wordsPerMinute (wordsInTrailingWindow longWindowMs session) elapsed

overallRate :: Session -> Number
overallRate session =
  wordsPerMinute session.totalWords (max 1.0 (activeListeningMs session))

formatRate :: Number -> String
formatRate rate
  | not (isFinite rate) = "0"
  | rate <= 0.0 = "0"
  | rate >= 100.0 = show (Int.round rate)
  | otherwise =
      let
        scaled = Int.round (rate * 10.0)
        wholePart = scaled `div` 10
        fracPart = scaled `mod` 10
      in
        show wholePart <> "." <> show fracPart

formatDurationMs :: Number -> String
formatDurationMs ms =
  let
    totalSeconds = max 0 (Int.floor (ms / millisecondsPerSecond))
  in
    if totalSeconds < 60 then show totalSeconds <> "s"
    else
      let
        totalMinutes = totalSeconds `div` 60
        seconds = totalSeconds `mod` 60
      in
        if totalMinutes < 60 then show totalMinutes <> "m " <> show seconds <> "s"
        else
          let
            hours = totalMinutes `div` 60
            minutes = totalMinutes `mod` 60
          in
            show hours <> "h " <> show minutes <> "m"
