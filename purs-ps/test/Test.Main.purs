-- | Pure-logic unit tests for the Word Meter PureScript port. Kept on the
-- | core toolchain only (prelude / effect / console / exception) so the
-- | suite stays the same shape as `npm run test:ps` and CI does not need a
-- | separate test framework.
module Test.Main where

import Prelude

import Data.Maybe (Maybe(..))
import Effect (Effect)
import Effect.Console (log)
import Effect.Exception (throw)
import WordMeter.Recording
  ( Action(..)
  , activeListeningMs
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
