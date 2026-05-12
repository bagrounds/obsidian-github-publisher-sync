-- | Pure-logic unit tests for the Word Meter PureScript port. Kept on the
-- | core toolchain only (prelude / effect / console / exception) so the
-- | suite stays the same shape as `npm run test:ps` and CI does not need a
-- | separate test framework.
module Test.Main where

import Prelude

import Data.Array (head, length) as Array
import Data.Int as Int
import Data.Maybe (Maybe(..))
import Effect (Effect)
import Effect.Console (log)
import Effect.Exception (throw)
import WordMeter.Recording
  ( Action(..)
  , Session
  , activeListeningMs
  , eventLogLimit
  , formatDurationMs
  , formatRate
  , initialSession
  , longRate
  , overallRate
  , ratePerMinute
  , reduce
  , shortRate
  , wallSpanMs
  , wordsInTrailingWindow
  )

main :: Effect Unit
main = do
  runRatePerMinuteTests
  runFormatRateTests
  runFormatDurationTests
  runReducerStatsTests
  runEventLogTests
  log "word-meter: all PureScript unit tests passed"

runRatePerMinuteTests :: Effect Unit
runRatePerMinuteTests = do
  assertEqualNumber "ratePerMinute 60 words / 60s = 60"
    (ratePerMinute 60 60000.0) 60.0
  assertEqualNumber "ratePerMinute 30 words / 60s = 30"
    (ratePerMinute 30 60000.0) 30.0
  assertEqualNumber "ratePerMinute with zero elapsed returns 0"
    (ratePerMinute 5 0.0) 0.0
  assertEqualNumber "ratePerMinute with negative elapsed returns 0"
    (ratePerMinute 5 (-1.0)) 0.0

runFormatRateTests :: Effect Unit
runFormatRateTests = do
  assertEqualString "formatRate 0 = \"0\"" (formatRate 0.0) "0"
  assertEqualString "formatRate negative = \"0\"" (formatRate (-3.0)) "0"
  assertEqualString "formatRate 12.34 = \"12.3\"" (formatRate 12.34) "12.3"
  assertEqualString "formatRate 99.96 lands in the decimal branch like JS toFixed(1)"
    (formatRate 99.96) "100.0"
  assertEqualString "formatRate 99.4 = \"99.4\""
    (formatRate 99.4) "99.4"
  assertEqualString "formatRate 100 = \"100\"" (formatRate 100.0) "100"
  assertEqualString "formatRate 137.6 rounds to whole" (formatRate 137.6) "138"

runFormatDurationTests :: Effect Unit
runFormatDurationTests = do
  assertEqualString "formatDurationMs 0 ms" (formatDurationMs 0.0) "0s"
  assertEqualString "formatDurationMs 15 s" (formatDurationMs 15000.0) "15s"
  assertEqualString "formatDurationMs 1m 5s"
    (formatDurationMs 65000.0) "1m 5s"
  assertEqualString "formatDurationMs 2h 5m"
    (formatDurationMs (2.0 * 3600000.0 + 5.0 * 60000.0)) "2h 5m"

runReducerStatsTests :: Effect Unit
runReducerStatsTests = do
  -- A simple end-to-end run through the reducer that exercises the new
  -- stats math: start at t=0, say six words at t=10s, tick at t=60s.
  let
    s0 = initialSession
    s1 = reduce (Toggle 0.0) s0
    s2 = reduce (InjectFinalTranscript "one two three four five six" 10000.0) s1
    s3 = reduce (Tick 60000.0) s2
  assertEqualBoolean "after Toggle, listening is true" s1.listening true
  assertEqualInt "after a six-word utterance, totalWords = 6"
    s2.totalWords 6
  assertEqualNumber "wallSpanMs at t=60s is 60000" (wallSpanMs s3) 60000.0
  assertEqualInt "wordsInTrailingWindow short = 6"
    (wordsInTrailingWindow 60000.0 s3) 6
  assertEqualNumber "shortRate over a one-minute span is 6 wpm"
    (shortRate s3) 6.0
  assertEqualNumber "longRate also surfaces the 6 words"
    (longRate s3) 6.0
  assertEqualNumber "overallRate at 6 words / 60s active listening is 6 wpm"
    (overallRate s3) 6.0

  -- Stop at t=90s; active listening = 90s, no new words → 4 wpm overall.
  let s4 = reduce (Toggle 90000.0) s3
  assertEqualBoolean "after second Toggle, listening flips back to false"
    s4.listening false
  assertEqualNumber "activeListeningMs after a 90s interval is 90000"
    (activeListeningMs s4) 90000.0
  assertEqualNumber "overallRate after stop reflects active listening only"
    (overallRate s4) 4.0

  -- firstStartedAt is sticky across stops.
  case s4.firstStartedAt of
    Just t -> assertEqualNumber "firstStartedAt preserved on stop" t 0.0
    Nothing -> throw "firstStartedAt should remain set after stop"

assertEqualNumber :: String -> Number -> Number -> Effect Unit
assertEqualNumber label actual expected =
  if actual == expected then pure unit
  else throw $ label <> ": expected " <> show expected
    <> " but got " <> show actual

assertEqualInt :: String -> Int -> Int -> Effect Unit
assertEqualInt label actual expected =
  if actual == expected then pure unit
  else throw $ label <> ": expected " <> show expected
    <> " but got " <> show actual

assertEqualString :: String -> String -> String -> Effect Unit
assertEqualString label actual expected =
  if actual == expected then pure unit
  else throw $ label <> ": expected " <> show expected
    <> " but got " <> show actual

assertEqualBoolean :: String -> Boolean -> Boolean -> Effect Unit
assertEqualBoolean label actual expected =
  if actual == expected then pure unit
  else throw $ label <> ": expected " <> show expected
    <> " but got " <> show actual

runEventLogTests :: Effect Unit
runEventLogTests = do
  -- Slice 4: the reducer records a LoggedEvent for every non-empty final
  -- transcript heard while listening, preserves them across stop/start, and
  -- caps the log at `eventLogLimit` entries (oldest evicted first).
  let
    started = reduce (Toggle 0.0) initialSession
    first = reduce (InjectFinalTranscript "alpha" 1000.0) started
    idleNoise = reduce (InjectFinalTranscript "ignored" 1500.0) initialSession
    blank = reduce (InjectFinalTranscript "   " 2000.0) first
    stopped = reduce (Toggle 3000.0) blank
    restarted = reduce (Toggle 4000.0) stopped
    second = reduce (InjectFinalTranscript "beta gamma" 5000.0) restarted
  assertEqualInt "event log starts empty"
    (Array.length initialSession.eventLog) 0
  assertEqualInt "an utterance while listening adds one entry"
    (Array.length first.eventLog) 1
  assertEqualInt "an utterance while idle does not log"
    (Array.length idleNoise.eventLog) 0
  assertEqualInt "a blank transcript does not log"
    (Array.length blank.eventLog) 1
  assertEqualInt "event log is preserved across stop/restart"
    (Array.length second.eventLog) 2
  case second.eventLog of
    [ a, b ] -> do
      assertEqualString "first logged transcript" a.transcript "alpha"
      assertEqualNumber "first logged timestamp" a.timestamp 1000.0
      assertEqualInt "first logged word count" a.wordCount 1
      assertEqualString "second logged transcript" b.transcript "beta gamma"
      assertEqualNumber "second logged timestamp" b.timestamp 5000.0
      assertEqualInt "second logged word count" b.wordCount 2
    _ -> throw "event log should contain exactly two entries"

  -- Drive `eventLogLimit + 5` utterances; the oldest five must be evicted.
  let overrun = stuffEvents (eventLogLimit + 5) started
  assertEqualInt "event log is capped at eventLogLimit entries"
    (Array.length overrun.eventLog) eventLogLimit
  -- The first surviving entry is utterance #5 (after evicting #0..#4).
  case Array.head overrun.eventLog of
    Just entry -> assertEqualString
      "oldest surviving entry corresponds to the 5th utterance"
      entry.transcript
      "utterance 5"
    Nothing -> throw "event log should not be empty after stuffing"

stuffEvents :: Int -> Session -> Session
stuffEvents total = go 0
  where
  go :: Int -> Session -> Session
  go index session
    | index >= total = session
    | otherwise =
        go (index + 1)
          (reduce
            (InjectFinalTranscript ("utterance " <> show index)
              (Int.toNumber (index + 1) * 100.0))
            session)
