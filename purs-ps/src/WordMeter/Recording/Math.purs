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
  ) where

import Prelude

import Data.Array (filter, foldl)
import Data.Int as Int
import Data.Maybe (Maybe(..))
import Data.Number (isFinite)
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

activeListeningMs :: Session -> Number
activeListeningMs session =
  session.completedActiveMs + case session.currentIntervalStart of
    Just start -> max 0.0 (session.now - start)
    Nothing -> 0.0

wallSpanMs :: Session -> Number
wallSpanMs session = case session.firstStartedAt of
  Nothing -> 0.0
  Just first -> max 0.0 (session.now - first)

wordsInTrailingWindow :: Number -> Session -> Int
wordsInTrailingWindow windowMs session =
  let
    cutoff = session.now - windowMs
    inWindow event = event.timestamp >= cutoff
  in
    foldl (\acc event -> acc + event.wordCount) 0
      (filter inWindow session.wordEvents)

wordsPerMinute :: Int -> Number -> Number
wordsPerMinute wordCount elapsedMs
  | elapsedMs <= 0.0 = 0.0
  | otherwise = Int.toNumber wordCount * millisecondsPerMinute / elapsedMs

intervalDurationMs :: LoggedInterval -> Number
intervalDurationMs interval = max 0.0 (interval.endedAt - interval.startedAt)

intervalRate :: LoggedInterval -> Number
intervalRate interval =
  wordsPerMinute interval.wordCount (max 1.0 (intervalDurationMs interval))

captionOpacity :: Number -> Number -> Number
captionOpacity nowMs captionTimestamp =
  let
    ageFraction = max 0.0 (nowMs - captionTimestamp) / captionWindowMs
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
