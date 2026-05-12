-- | Pure-logic unit tests for the Word Meter PureScript port. Kept on the
-- | core toolchain only (prelude / effect / console / exception) so the
-- | suite stays the same shape as `npm run test:ps` and CI does not need a
-- | separate test framework.
module Test.Main where

import Prelude

import Data.Array (head, length) as Array
import Data.Int as Int
import Data.Maybe (Maybe(..))
import Data.String (Pattern(..), contains) as String
import Effect (Effect)
import Effect.Console (log)
import Effect.Exception (throw)
import WordMeter.Capability.Clipboard
  ( runRecordingClipboardM
  , writeClipboardText
  )
import WordMeter.Capability.Clock
  ( currentTimeMillis
  , runFixedClockM
  )
import WordMeter.Capability.DomMount
  ( mountToHost
  , runRecordingDomMountM
  )
import WordMeter.Capability.Environment
  ( captureEnvironmentSnapshot
  , runStubEnvironmentM
  )
import WordMeter.Capability.SessionState
  ( readCurrentSession
  , runStatefulSessionM
  , updateSession
  )
import WordMeter.Diagnostics
  ( diagnosticsLimit
  , emptyEnvironment
  , formatDiagnostics
  , recordEntry
  )
import WordMeter.Recording
  ( Action(..)
  , Session
  , activeListeningMs
  , captionOpacity
  , diagnosticsText
  , eventLogLimit
  , formatDurationMs
  , formatRate
  , idleCopyStatus
  , initialSession
  , intervalDurationMs
  , intervalRate
  , longRate
  , minimumCaptionOpacity
  , overallRate
  , ratePerMinute
  , reduce
  , shortRate
  , wallSpanMs
  , wordsInTrailingWindow
  )
import WordMeter.Vdom (text)

main :: Effect Unit
main = do
  runRatePerMinuteTests
  runFormatRateTests
  runFormatDurationTests
  runReducerStatsTests
  runEventLogTests
  runCaptionDecayTests
  runDiagnosticsTests
  runCapabilityTests
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
  -- Slice 4: the event log records one LoggedInterval per completed
  -- counting session (start → stop), carrying the wall-clock range and the
  -- words accumulated during that interval. The log persists across stops
  -- and restarts and is capped at `eventLogLimit` intervals.
  let
    s0 = initialSession
    s1 = reduce (Toggle 0.0) s0
    s2 = reduce (InjectFinalTranscript "one two three" 5000.0) s1
    -- Stop after a 30s interval with 3 words → 6.0 wpm.
    s3 = reduce (Toggle 30000.0) s2
    -- A blank transcript while listening does not seed a new interval.
    s4 = reduce (Toggle 60000.0) s3
    s4' = reduce (InjectFinalTranscript "   " 60500.0) s4
    s5 = reduce (Toggle 120000.0) s4'
    -- An idle InjectFinalTranscript before any start does nothing.
    sIdle = reduce (InjectFinalTranscript "noise" 200.0) s0
  assertEqualInt "event log starts empty"
    (Array.length s0.eventLog) 0
  assertEqualInt "an open interval has not yet been logged"
    (Array.length s2.eventLog) 0
  assertEqualInt "stop pushes the closed interval into the event log"
    (Array.length s3.eventLog) 1
  assertEqualInt "idle utterances do not seed any interval"
    (Array.length sIdle.eventLog) 0
  assertEqualInt "stop/restart preserves prior intervals and adds the new one"
    (Array.length s5.eventLog) 2

  case s5.eventLog of
    [ first, second ] -> do
      assertEqualNumber "first interval started at 0ms" first.startedAt 0.0
      assertEqualNumber "first interval ended at 30000ms" first.endedAt 30000.0
      assertEqualInt "first interval word count" first.wordCount 3
      assertEqualNumber "first interval duration is 30s"
        (intervalDurationMs first) 30000.0
      assertEqualNumber "first interval rate is 6.0 wpm"
        (intervalRate first) 6.0
      assertEqualNumber "second interval started at 60000ms" second.startedAt 60000.0
      assertEqualNumber "second interval ended at 120000ms" second.endedAt 120000.0
      assertEqualInt "second interval (whitespace only) word count" second.wordCount 0
    _ -> throw "event log should contain exactly two intervals"

  -- Drive `eventLogLimit + 5` counting sessions; the oldest five evict.
  let overrun = stuffIntervals (eventLogLimit + 5) s0
  assertEqualInt "event log is capped at eventLogLimit intervals"
    (Array.length overrun.eventLog) eventLogLimit
  case Array.head overrun.eventLog of
    Just oldest ->
      -- Intervals are indexed 0..N-1; oldest surviving started at the 5th.
      assertEqualNumber
        "oldest surviving interval corresponds to the 5th counting session"
        oldest.startedAt
        (Int.toNumber 5 * 10000.0)
    Nothing -> throw "event log should not be empty after stuffing"

runCaptionDecayTests :: Effect Unit
runCaptionDecayTests = do
  -- Slice 2 (rework): captions are pruned once they age past `captionWindowMs`
  -- (30 seconds in legacy parity), and their opacity fades linearly with age
  -- down to `minimumCaptionOpacity`.
  let
    s0 = reduce (Toggle 0.0) initialSession
    s1 = reduce (InjectFinalTranscript "early word" 0.0) s0
    s2 = reduce (InjectFinalTranscript "later words" 25000.0) s1
    -- Tick past the 30s window for the first caption; it should fall off.
    s3 = reduce (Tick 35000.0) s2
  assertEqualInt "two captions are kept while both are inside the 30s window"
    (Array.length s2.captions) 2
  assertEqualInt "a caption older than 30s is pruned on the next tick"
    (Array.length s3.captions) 1
  case Array.head s3.captions of
    Just kept ->
      assertEqualString "the surviving caption is the more recent one"
        kept.transcript "later words"
    Nothing -> throw "expected the 25s caption to survive"
  assertEqualNumber "a brand-new caption has full opacity (1.0)"
    (captionOpacity 0.0 0.0) 1.0
  assertEqualNumber "a half-aged caption (15s) sits at 0.5 opacity"
    (captionOpacity 15000.0 0.0) 0.5
  assertEqualNumber "a caption past the window floors at minimumCaptionOpacity"
    (captionOpacity 60000.0 0.0) minimumCaptionOpacity

stuffIntervals :: Int -> Session -> Session
stuffIntervals total = go 0
  where
  go :: Int -> Session -> Session
  go index session
    | index >= total = session
    | otherwise =
        let
          startTs = Int.toNumber index * 10000.0
          endTs = startTs + 1000.0
          started = reduce (Toggle startTs) session
        in
          go (index + 1) (reduce (Toggle endTs) started)

runDiagnosticsTests :: Effect Unit
runDiagnosticsTests = do
  -- Slice 5: every Toggle on/off and every counted utterance appends a
  -- diagnostic entry; the log is capped at `diagnosticsLimit`; the
  -- formatted text always contains the snapshot prefix when one has
  -- been captured; SetCopyStatus updates the copyStatus field.
  let
    s0 = initialSession
    s1 = reduce (Toggle 0.0) s0
    s2 = reduce (InjectFinalTranscript "hello there general kenobi" 1000.0) s1
    s3 = reduce (InjectFinalTranscript "   " 2000.0) s2
    s4 = reduce (Toggle 30000.0) s3
  assertEqualString "initialSession.copyStatus is empty"
    s0.copyStatus idleCopyStatus
  assertEqualInt "initialSession has no diagnostic entries"
    (Array.length s0.diagnostics) 0
  assertEqualInt "Toggle on appends one entry"
    (Array.length s1.diagnostics) 1
  assertEqualInt "non-empty transcript appends an entry"
    (Array.length s2.diagnostics) 2
  assertEqualInt "whitespace-only transcript does not append an entry"
    (Array.length s3.diagnostics) 2
  assertEqualInt "Toggle off appends a stop-counting entry"
    (Array.length s4.diagnostics) 3

  case Array.head s4.diagnostics of
    Just first -> assertEqualString "first entry is start counting"
      first.label "start counting"
    Nothing -> throw "expected the first entry to be start counting"

  -- recordEntry caps the array at diagnosticsLimit.
  let
    sample = { timestamp: 0.0, label: "noisy", detail: "" }
    overrun = stuffEntries (diagnosticsLimit + 7) sample []
  assertEqualInt "diagnostics log is capped at diagnosticsLimit"
    (Array.length overrun) diagnosticsLimit

  -- Snapshot prefix appears in the rendered text.
  let env = emptyEnvironment { version = "9.9.9", userAgent = "ua", navigatorLanguage = "en-US" }
      txtWith = formatDiagnostics (Just env) []
      txtWithout = formatDiagnostics Nothing []
  assertEqualBoolean "rendered text with snapshot mentions version"
    (containsSubstring "9.9.9" txtWith) true
  assertEqualBoolean "rendered text without snapshot has the placeholder"
    (containsSubstring "(no events yet" txtWithout) true

  -- diagnosticsText uses the session's environment + diagnostics.
  let s4WithEnv = reduce (SetEnvironment env) s4
  assertEqualBoolean "diagnosticsText includes the snapshot version"
    (containsSubstring "9.9.9" (diagnosticsText s4WithEnv)) true

  -- SetCopyStatus updates the field exactly.
  let s5 = reduce (SetCopyStatus "Copied!") s4
  assertEqualString "SetCopyStatus writes the field" s5.copyStatus "Copied!"

stuffEntries
  :: Int
  -> { timestamp :: Number, label :: String, detail :: String }
  -> Array { timestamp :: Number, label :: String, detail :: String }
  -> Array { timestamp :: Number, label :: String, detail :: String }
stuffEntries n entry entries
  | n <= 0 = entries
  | otherwise = stuffEntries (n - 1) entry (recordEntry entry entries)

containsSubstring :: String -> String -> Boolean
containsSubstring needle haystack = String.contains (String.Pattern needle) haystack

runCapabilityTests :: Effect Unit
runCapabilityTests = do
  let
    fixedClockTime = 1_700_000_000_000.0
    sampledClockTime = runFixedClockM fixedClockTime currentTimeMillis
  assertEqualNumber "FixedClockM hands back the configured clock value"
    sampledClockTime fixedClockTime

  let
    canned =
      { userAgent: "test-agent"
      , navigatorLanguage: "en-US"
      , version: "0.0.1-test"
      }
    captured = runStubEnvironmentM canned
      (captureEnvironmentSnapshot "ignored-version")
  assertEqualString "StubEnvironmentM ignores the version argument and returns the canned userAgent"
    captured.userAgent canned.userAgent
  assertEqualString "StubEnvironmentM hands back the canned language"
    captured.navigatorLanguage canned.navigatorLanguage

  let
    clipboardOutcome = runRecordingClipboardM do
      writeClipboardText "first payload" (pure unit) (\_ -> pure unit)
      writeClipboardText "second payload" (pure unit) (\_ -> pure unit)
  assertEqualInt "RecordingClipboardM records every write in order"
    (Array.length clipboardOutcome.writes) 2
  case Array.head clipboardOutcome.writes of
    Just firstWrite ->
      assertEqualString "RecordingClipboardM preserves the payload"
        firstWrite "first payload"
    Nothing -> throw "RecordingClipboardM should have captured a write"

  let
    domOutcome = runRecordingDomMountM do
      mountToHost "host-one" (text "alpha")
      mountToHost "host-two" (text "beta")
  assertEqualInt "RecordingDomMountM records every mount call"
    (Array.length domOutcome.mounts) 2

  let
    sessionOutcome = runStatefulSessionM initialSession do
      updateSession (Toggle 1000.0)
      updateSession (InjectFinalTranscript "hello world" 2000.0)
      readCurrentSession
  assertEqualInt "StatefulSessionM threads reducer updates through pure state"
    sessionOutcome.result.totalWords 2
  assertEqualBoolean "StatefulSessionM observes listening state after Toggle"
    sessionOutcome.result.listening true
