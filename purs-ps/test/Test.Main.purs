module Test.Main where

import Prelude

import Data.Array (any, head, length) as Array
import Data.DateTime.Instant (Instant, instant, unInstant)
import Data.Either (Either(..), isLeft)
import Data.Int as Int
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Foldable (sequence_)
import Data.Newtype (unwrap)
import Data.Ord (abs)
import Data.String (Pattern(..), contains, length) as String
import Data.Time.Duration (Milliseconds(..))
import Effect (Effect)
import Effect.Console (log)
import Effect.Exception (throw)
import Test.QuickCheck (quickCheck)
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
import WordMeter.Capability.Recognition
  ( RecognitionEvent(..)
  , runRecordingRecognitionM
  , onDeviceLanguagePackApiAvailable
  , prepareOnDeviceLanguagePack
  , recognitionApiAvailable
  , scheduleAutoRestart
  , cancelAutoRestart
  , startOnDeviceRecognition
  , startRecognition
  , stopRecognition
  )
import WordMeter.Capability.SessionState
  ( readCurrentSession
  , runStatefulSessionM
  , updateSession
  )
import WordMeter.Capability.Storage
  ( clearPersistedSnapshot
  , loadPersistedSnapshot
  , persistSnapshot
  , runInMemoryStorageM
  )
import WordMeter.Capability.WakeLock
  ( WakeLockEvent(..)
  , releaseScreenWakeLock
  , requestScreenWakeLock
  , runRecordingWakeLockM
  )
import WordMeter.Diagnostics
  ( diagnosticsLimit
  , emptyEnvironment
  , formatDiagnostics
  , recordEntry
  )
import WordMeter.Persistence (decodePersistedData, encodePersistedData)
import WordMeter.RecognitionError
  ( RecognitionErrorCode(..)
  , classifyRecognitionError
  , genericRecognitionErrorBanner
  , isPermissionDenied
  , isTransient
  , networkErrorBanner
  , noRecognitionErrorBanner
  , permissionDeniedBanner
  , recognitionErrorBannerText
  , renderRecognitionErrorDiagnosticDetail
  )
import WordMeter.Recognition.Delta
  ( TranscriptIntegration(..)
  , classifyFinalizedTranscript
  , isWordBoundaryExtension
  , normalizeTranscript
  )
import WordMeter.FFI.Recognition
  ( OnDeviceAvailable(..)
  , OnDeviceUnavailable(..)
  , renderOnDeviceUnavailable
  )
import WordMeter.Recognition.Path (RecognitionPath(..))
import WordMeter.Locale (Locale(..))
import WordMeter.Recording.Math
  ( activeListeningMs
  , captionOpacity
  , formatDurationMs
  , formatPercent
  , formatRate
  , intervalDurationMs
  , intervalRate
  , longRate
  , overallRate
  , sampleFraction
  , shortRate
  , wallSpanMs
  , wordsInTrailingWindow
  , wordsPerDay
  , wordsPerMinute
  )
import WordMeter.Recording.Reducer
  ( Action(..)
  , reduce
  , toPersistedData
  )
import WordMeter.Recording.Session
  ( Session
  , WakeLockState(..)
  , downloadingOnDeviceStatus
  , epochInstant
  , eventLogLimit
  , idleCopyStatus
  , idleErrorBanner
  , idleRecognitionStatusOverride
  , initialSession
  , minimumCaptionOpacity
  , renderWakeLockStatus
  , resetConfirmationPrompt
  )
import WordMeter.Recording.View (diagnosticsText)
import WordMeter.Vdom (text)
import WordMeter.WordStats
  ( addTranscript
  , emptyWordStats
  , isEmptyWordStats
  , longestWord
  , mostFrequentWord
  , topWords
  )

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
  runPersistenceTests
  runKeepAwakeTests
  runRecognitionErrorTests
  runRecognitionDeltaTests
  runRecognitionCapabilityTests
  runOnDevicePreflightTests
  runRecognitionStatusReducerTests
  runIntegrateFinalizedTranscriptReducerTests
  runCloudFallbackReducerTests
  runDiagnosticsDrawerReducerTests
  runMultiDayStatsTests
  runWordStatsTests
  runPropertyTests
  log "word-meter: all PureScript unit tests passed"

runRatePerMinuteTests :: Effect Unit
runRatePerMinuteTests = do
  assertEqualNumber "wordsPerMinute 60 words / 60s = 60"
    (wordsPerMinute 60 60000.0) 60.0
  assertEqualNumber "wordsPerMinute 30 words / 60s = 30"
    (wordsPerMinute 30 60000.0) 30.0
  assertEqualNumber "wordsPerMinute with zero elapsed returns 0"
    (wordsPerMinute 5 0.0) 0.0
  assertEqualNumber "wordsPerMinute with negative elapsed returns 0"
    (wordsPerMinute 5 (-1.0)) 0.0

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
    s1 = reduce (Toggle (testInstant 0.0)) s0
    s2 = reduce (InjectFinalTranscript "one two three four five six" (testInstant 10000.0)) s1
    s3 = reduce (Tick (testInstant 60000.0)) s2
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
  let s4 = reduce (Toggle (testInstant 90000.0)) s3
  assertEqualBoolean "after second Toggle, listening flips back to false"
    s4.listening false
  assertEqualNumber "activeListeningMs after a 90s interval is 90000"
    (activeListeningMs s4) 90000.0
  assertEqualNumber "overallRate after stop reflects active listening only"
    (overallRate s4) 4.0

  -- firstStartedAt is sticky across stops.
  case s4.firstStartedAt of
    Just startedAt -> assertEqualNumber "firstStartedAt preserved on stop" (instantMs startedAt) 0.0
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

-- | Convert a raw millisecond timestamp (as used throughout the test
-- | suite) to an `Instant`, falling back to the epoch for any value
-- | outside the valid `Instant` range (impossible in practice for test
-- | timestamps).
testInstant :: Number -> Instant
testInstant ms = fromMaybe epochInstant (instant (Milliseconds ms))

-- | Extract the millisecond value from an `Instant` for use in
-- | numeric assertions.
instantMs :: Instant -> Number
instantMs inst = unwrap (unInstant inst)

runEventLogTests :: Effect Unit
runEventLogTests = do
  -- Slice 4: the event log records one LoggedInterval per completed
  -- counting session (start → stop), carrying the wall-clock range and the
  -- words accumulated during that interval. The log persists across stops
  -- and restarts and is capped at `eventLogLimit` intervals.
  let
    s0 = initialSession
    s1 = reduce (Toggle (testInstant 0.0)) s0
    s2 = reduce (InjectFinalTranscript "one two three" (testInstant 5000.0)) s1
    -- Stop after a 30s interval with 3 words → 6.0 wpm.
    s3 = reduce (Toggle (testInstant 30000.0)) s2
    -- A blank transcript while listening does not seed a new interval.
    s4 = reduce (Toggle (testInstant 60000.0)) s3
    s4' = reduce (InjectFinalTranscript "   " (testInstant 60500.0)) s4
    s5 = reduce (Toggle (testInstant 120000.0)) s4'
    -- An idle InjectFinalTranscript before any start does nothing.
    sIdle = reduce (InjectFinalTranscript "noise" (testInstant 200.0)) s0
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
      assertEqualNumber "first interval started at 0ms" (instantMs first.startedAt) 0.0
      assertEqualNumber "first interval ended at 30000ms" (instantMs first.endedAt) 30000.0
      assertEqualInt "first interval word count" first.wordCount 3
      assertEqualNumber "first interval duration is 30s"
        (intervalDurationMs first) 30000.0
      assertEqualNumber "first interval rate is 6.0 wpm"
        (intervalRate first) 6.0
      assertEqualNumber "second interval started at 60000ms" (instantMs second.startedAt) 60000.0
      assertEqualNumber "second interval ended at 120000ms" (instantMs second.endedAt) 120000.0
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
        (instantMs oldest.startedAt)
        (Int.toNumber 5 * 10000.0)
    Nothing -> throw "event log should not be empty after stuffing"

runCaptionDecayTests :: Effect Unit
runCaptionDecayTests = do
  -- Slice 2 (rework): captions are pruned once they age past `captionWindowMs`
  -- (30 seconds in legacy parity), and their opacity fades linearly with age
  -- down to `minimumCaptionOpacity`.
  let
    s0 = reduce (Toggle (testInstant 0.0)) initialSession
    s1 = reduce (InjectFinalTranscript "early word" (testInstant 0.0)) s0
    s2 = reduce (InjectFinalTranscript "later words" (testInstant 25000.0)) s1
    -- Tick past the 30s window for the first caption; it should fall off.
    s3 = reduce (Tick (testInstant 35000.0)) s2
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
    (captionOpacity (testInstant 0.0) (testInstant 0.0)) 1.0
  assertEqualNumber "a half-aged caption (15s) sits at 0.5 opacity"
    (captionOpacity (testInstant 15000.0) (testInstant 0.0)) 0.5
  assertEqualNumber "a caption past the window floors at minimumCaptionOpacity"
    (captionOpacity (testInstant 60000.0) (testInstant 0.0)) minimumCaptionOpacity

stuffIntervals :: Int -> Session -> Session
stuffIntervals total = go 0
  where
  go :: Int -> Session -> Session
  go index session
    | index >= total = session
    | otherwise =
        let
          startTs = testInstant (Int.toNumber index * 10000.0)
          endTs = testInstant (Int.toNumber index * 10000.0 + 1000.0)
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
    s1 = reduce (Toggle (testInstant 0.0)) s0
    s2 = reduce (InjectFinalTranscript "hello there general kenobi" (testInstant 1000.0)) s1
    s3 = reduce (InjectFinalTranscript "   " (testInstant 2000.0)) s2
    s4 = reduce (Toggle (testInstant 30000.0)) s3
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
    sample = { timestamp: testInstant 0.0, label: "noisy", detail: "" }
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
  -> { timestamp :: Instant, label :: String, detail :: String }
  -> Array { timestamp :: Instant, label :: String, detail :: String }
  -> Array { timestamp :: Instant, label :: String, detail :: String }
stuffEntries count entry entries
  | count <= 0 = entries
  | otherwise = stuffEntries (count - 1) entry (recordEntry entry entries)

containsSubstring :: String -> String -> Boolean
containsSubstring needle haystack = String.contains (String.Pattern needle) haystack

runCapabilityTests :: Effect Unit
runCapabilityTests = do
  let
    fixedClockTime = testInstant 1_700_000_000_000.0
    sampledClockTime = runFixedClockM fixedClockTime currentTimeMillis
  assertEqualBoolean "FixedClockM hands back the configured clock value"
    (sampledClockTime == fixedClockTime) true

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
      updateSession (Toggle (testInstant 1000.0))
      updateSession (InjectFinalTranscript "hello world" (testInstant 2000.0))
      readCurrentSession
  assertEqualInt "StatefulSessionM threads reducer updates through pure state"
    sessionOutcome.result.totalWords 2
  assertEqualBoolean "StatefulSessionM observes listening state after Toggle"
    sessionOutcome.result.listening true

runPersistenceTests :: Effect Unit
runPersistenceTests = do
  let
    seeded =
      reduce (InjectFinalTranscript "alpha beta" (testInstant 1500.0))
        (reduce (Toggle (testInstant 1000.0)) initialSession)
    seededStopped = reduce (Toggle (testInstant 5000.0)) seeded
    projected = toPersistedData seededStopped
  assertEqualInt "toPersistedData preserves totalWords"
    projected.totalWords 2
  assertEqualInt "toPersistedData preserves eventLog length"
    (Array.length projected.eventLog) 1
  case projected.firstStartedAt of
    Just startedAt -> assertEqualNumber "toPersistedData preserves firstStartedAt"
      startedAt 1000.0
    Nothing -> throw "toPersistedData should have preserved firstStartedAt"

  let
    encoded = encodePersistedData projected
    roundTrip = decodePersistedData encoded
  case roundTrip of
    Right decoded -> do
      assertEqualInt "round-trip preserves totalWords"
        decoded.totalWords projected.totalWords
      assertEqualInt "round-trip preserves wordEvents length"
        (Array.length decoded.wordEvents) (Array.length projected.wordEvents)
      assertEqualInt "round-trip preserves eventLog length"
        (Array.length decoded.eventLog) (Array.length projected.eventLog)
      case decoded.firstStartedAt of
        Just startedAt -> assertEqualNumber "round-trip preserves firstStartedAt"
          startedAt 1000.0
        Nothing -> throw "round-trip should have preserved firstStartedAt"
    Left _ -> throw "round-trip failed: expected Right PersistedData"

  let
    untouched = toPersistedData initialSession
    encodedUntouched = encodePersistedData untouched
  assertEqualBoolean "untouched session encodes firstStartedAt as null"
    (containsSubstring "\"firstStartedAt\":null" encodedUntouched) true
  case decodePersistedData encodedUntouched of
    Right decoded ->
      assertEqualBoolean "untouched session decodes firstStartedAt as Nothing"
        (decoded.firstStartedAt == Nothing) true
    Left _ -> throw "round-trip failed for untouched session"

  assertEqualBoolean "garbage decodes to Left"
    (isLeft (decodePersistedData "not json")) true
  assertEqualBoolean "wrong version decodes to Left"
    (isLeft (decodePersistedData "{\"version\":99,\"totalWords\":0,\"firstStartedAt\":null,\"wordEvents\":[],\"eventLog\":[]}"))
    true
  assertEqualBoolean "missing fields decode to Left"
    (isLeft (decodePersistedData "{\"version\":1}")) true
  -- Backward compatibility: localStorage payloads written by earlier
  -- builds did not include `completedActiveMs` or
  -- `cloudFallbackAttempted`. They must still decode cleanly with
  -- safe defaults so users do not lose their stats on upgrade.
  let
    legacyPayload =
      "{\"version\":1,\"totalWords\":7,\"firstStartedAt\":1000,"
        <> "\"wordEvents\":[],\"eventLog\":[]}"
  case decodePersistedData legacyPayload of
    Right legacy -> do
      assertEqualInt "legacy payload decodes totalWords"
        legacy.totalWords 7
      assertEqualNumber "legacy payload defaults completedActiveMs to 0"
        legacy.completedActiveMs 0.0
      assertEqualBoolean "legacy payload defaults cloudFallbackAttempted to false"
        legacy.cloudFallbackAttempted false
    Left _ -> throw "legacy payload should decode with default new fields"

  let
    env = emptyEnvironment { version = "9.9.9" }
    populated =
      reduce (SetEnvironment env)
        (reduce (Toggle (testInstant 6000.0)) seededStopped)
    resetted = reduce (Reset (testInstant 7000.0)) populated
  assertEqualInt "Reset clears totalWords" resetted.totalWords 0
  assertEqualInt "Reset clears eventLog" (Array.length resetted.eventLog) 0
  assertEqualBoolean "Reset turns listening off" resetted.listening false
  assertEqualBoolean "Reset preserves environment"
    (case resetted.environment of
      Just environment -> environment.version == "9.9.9"
      Nothing -> false)
    true
  assertEqualBoolean "Reset records a diagnostic entry"
    (Array.length resetted.diagnostics > 0) true
  assertEqualString "resetConfirmationPrompt mentions reset"
    resetConfirmationPrompt
    "Reset all word meter stats? This cannot be undone."

  let loaded = reduce (LoadSession projected) initialSession
  assertEqualInt "LoadSession restores totalWords"
    loaded.totalWords projected.totalWords
  assertEqualInt "LoadSession restores eventLog length"
    (Array.length loaded.eventLog) (Array.length projected.eventLog)
  case loaded.firstStartedAt of
    Just startedAt -> assertEqualNumber "LoadSession restores firstStartedAt"
      (instantMs startedAt) 1000.0
    Nothing -> throw "LoadSession should have restored firstStartedAt"
  assertEqualBoolean "LoadSession leaves listening off"
    loaded.listening false
  -- Issue #N (nonsensical post-reload rates): `completedActiveMs`
  -- must round-trip through persistence so `overallRate` does not
  -- divide by ~0 after a page reload.
  assertEqualNumber "toPersistedData preserves completedActiveMs"
    projected.completedActiveMs 4000.0
  assertEqualNumber "LoadSession restores completedActiveMs"
    (unwrap loaded.completedActiveMs) 4000.0
  -- Issue #N (on-device retried every capture): once the cloud path
  -- has been chosen the decision survives page reloads, so the
  -- pre-flight is not re-attempted on the next start.
  let
    projectedAfterFallback =
      toPersistedData (loaded { cloudFallbackAttempted = true })
  assertEqualBoolean "toPersistedData preserves cloudFallbackAttempted"
    projectedAfterFallback.cloudFallbackAttempted true
  let
    reloadedAfterFallback =
      reduce (LoadSession projectedAfterFallback) initialSession
  assertEqualBoolean "LoadSession restores cloudFallbackAttempted"
    reloadedAfterFallback.cloudFallbackAttempted true

  let
    inMemoryOutcome = runInMemoryStorageM Nothing do
      before <- loadPersistedSnapshot
      _ <- persistSnapshot projected
      after <- loadPersistedSnapshot
      _ <- clearPersistedSnapshot
      cleared <- loadPersistedSnapshot
      pure { before, after, cleared }
  assertEqualBoolean "InMemoryStorageM starts empty"
    (case inMemoryOutcome.result.before of
      Right Nothing -> true
      _ -> false)
    true
  case inMemoryOutcome.result.after of
    Right (Just persisted) ->
      assertEqualInt "InMemoryStorageM observes persisted totalWords"
        persisted.totalWords projected.totalWords
    _ -> throw "InMemoryStorageM should have observed a persisted snapshot"
  assertEqualBoolean "InMemoryStorageM clears the snapshot on request"
    (case inMemoryOutcome.result.cleared of
      Right Nothing -> true
      _ -> false)
    true
  assertEqualBoolean "InMemoryStorageM final cell matches cleared state"
    (inMemoryOutcome.finalSnapshot == Nothing) true


runKeepAwakeTests :: Effect Unit
runKeepAwakeTests = do
  assertEqualBoolean "initialSession.keepAwake defaults to true"
    initialSession.keepAwake true
  assertEqualBoolean "initialSession.wakeLockState defaults to WakeLockIdle"
    (initialSession.wakeLockState == WakeLockIdle) true
  assertEqualString "initialSession wake lock status is empty"
    (renderWakeLockStatus initialSession.wakeLockState) ""

  let
    afterDisable = reduce (SetKeepAwake false) initialSession
    afterEnable = reduce (SetKeepAwake true) afterDisable
  assertEqualBoolean "SetKeepAwake false flips the preference"
    afterDisable.keepAwake false
  assertEqualBoolean "SetKeepAwake true flips it back"
    afterEnable.keepAwake true

  let
    withHeld = reduce (SetWakeLockState WakeLockHeld) initialSession
    cleared = reduce (SetKeepAwake false) withHeld
  assertEqualBoolean "SetKeepAwake false clears wakeLockState to WakeLockIdle"
    (cleared.wakeLockState == WakeLockIdle) true

  let
    failedReason = "wake lock unavailable: NotAllowedError"
    advised = reduce (SetWakeLockState (WakeLockFailed failedReason)) initialSession
  assertEqualBoolean "SetWakeLockState WakeLockFailed stores failed state"
    (advised.wakeLockState == WakeLockFailed failedReason) true
  assertEqualBoolean "WakeLockFailed status wraps the reason in parens"
    (containsSubstring "(wake lock unavailable" (renderWakeLockStatus advised.wakeLockState)) true

  let held = reduce (SetWakeLockState WakeLockHeld) initialSession
  assertEqualBoolean "SetWakeLockState WakeLockHeld sets held state"
    (held.wakeLockState == WakeLockHeld) true
  let dropped = reduce (SetWakeLockState WakeLockIdle) held
  assertEqualBoolean "SetWakeLockState WakeLockIdle clears held state"
    (dropped.wakeLockState == WakeLockIdle) true
  assertEqualString "WakeLockHeld status is 'screen will stay on'"
    (renderWakeLockStatus held.wakeLockState) "screen will stay on"

  let
    preferredOff =
      reduce (SetWakeLockState WakeLockHeld)
        (reduce (SetKeepAwake false) initialSession)
    afterReset = reduce (Reset (testInstant 12345.0)) preferredOff
  assertEqualBoolean "Reset preserves keepAwake preference"
    afterReset.keepAwake false
  assertEqualBoolean "Reset clears wakeLockState to WakeLockIdle"
    (afterReset.wakeLockState == WakeLockIdle) true

  let
    wakeLockOutcome = runRecordingWakeLockM do
      requestScreenWakeLock (pure unit) (\_ -> pure unit) (pure unit)
      releaseScreenWakeLock (pure unit) (\_ -> pure unit)
      requestScreenWakeLock (pure unit) (\_ -> pure unit) (pure unit)
  assertEqualInt "RecordingWakeLockM records every event in order"
    (Array.length wakeLockOutcome.events) 3
  assertEqualBoolean "RecordingWakeLockM first event is a request"
    (Array.head wakeLockOutcome.events == Just RequestedWakeLock) true

runRecognitionErrorTests :: Effect Unit
runRecognitionErrorTests = do
  -- Slice 8: typed classification of recognition.onerror codes.
  assertEqualBoolean "classify not-allowed"
    (classifyRecognitionError "not-allowed" == NotAllowed) true
  assertEqualBoolean "classify service-not-allowed"
    (classifyRecognitionError "service-not-allowed" == ServiceNotAllowed) true
  assertEqualBoolean "classify no-speech"
    (classifyRecognitionError "no-speech" == NoSpeech) true
  assertEqualBoolean "classify aborted"
    (classifyRecognitionError "aborted" == Aborted) true
  assertEqualBoolean "classify audio-capture"
    (classifyRecognitionError "audio-capture" == AudioCapture) true
  assertEqualBoolean "classify network"
    (classifyRecognitionError "network" == Network) true
  assertEqualBoolean "classify language-not-supported"
    (classifyRecognitionError "language-not-supported" == LanguageNotSupported)
    true
  assertEqualBoolean "classify empty string"
    (classifyRecognitionError "" == NoRecognitionErrorCode) true
  assertEqualBoolean "classify unknown code carries the raw string"
    (classifyRecognitionError "weird" == OtherRecognitionError "weird") true

  assertEqualBoolean "no-speech is transient"
    (isTransient NoSpeech) true
  assertEqualBoolean "aborted is transient"
    (isTransient Aborted) true
  assertEqualBoolean "audio-capture is transient"
    (isTransient AudioCapture) true
  assertEqualBoolean "not-allowed is NOT transient"
    (isTransient NotAllowed) false
  assertEqualBoolean "network is NOT transient"
    (isTransient Network) false

  assertEqualBoolean "not-allowed is permission-denied"
    (isPermissionDenied NotAllowed) true
  assertEqualBoolean "service-not-allowed is permission-denied"
    (isPermissionDenied ServiceNotAllowed) true
  assertEqualBoolean "no-speech is NOT permission-denied"
    (isPermissionDenied NoSpeech) false
  assertEqualBoolean "network is NOT permission-denied"
    (isPermissionDenied Network) false

  assertEqualString "banner text for NotAllowed"
    (recognitionErrorBannerText NotAllowed) permissionDeniedBanner
  assertEqualString "banner text for Network"
    (recognitionErrorBannerText Network) networkErrorBanner
  assertEqualString "banner text for NoSpeech is empty"
    (recognitionErrorBannerText NoSpeech) ""
  assertEqualString "banner text for NoRecognitionErrorCode"
    (recognitionErrorBannerText NoRecognitionErrorCode)
    noRecognitionErrorBanner
  assertEqualString "banner text for an unknown code interpolates the raw code"
    (recognitionErrorBannerText (OtherRecognitionError "boom"))
    (genericRecognitionErrorBanner "boom")

  assertEqualString "diagnostic detail with empty code renders (none)"
    (renderRecognitionErrorDiagnosticDetail "" "")
    "code=(none) message="
  assertEqualString "diagnostic detail surfaces both fields"
    (renderRecognitionErrorDiagnosticDetail "network" "lost wifi")
    "code=network message=lost wifi"

  -- Reducer: a transient error appends a diagnostic but does not change
  -- the banner or the listening state.
  let
    listening = reduce (Toggle (testInstant 0.0)) initialSession
    afterTransient =
      reduce (HandleRecognitionError (testInstant 5000.0) "no-speech" "ignore me") listening
  assertEqualBoolean "transient error keeps listening true"
    afterTransient.listening true
  assertEqualString "transient error leaves errorBanner empty"
    afterTransient.errorBanner idleErrorBanner
  assertEqualInt "transient error still appends a diagnostic"
    (Array.length afterTransient.diagnostics)
    (Array.length listening.diagnostics + 1)

  -- Permission-denied: banner set, listening flipped off, interval pushed
  -- to event log, two diagnostic entries appended (onerror + session ended).
  let
    listening2 =
      reduce (InjectFinalTranscript "one two three" (testInstant 2000.0))
        (reduce (Toggle (testInstant 0.0)) initialSession)
    afterPermission =
      reduce (HandleRecognitionError (testInstant 10000.0) "not-allowed" "user denied")
        listening2
  assertEqualBoolean "permission-denied stops listening"
    afterPermission.listening false
  assertEqualString "permission-denied sets the banner"
    afterPermission.errorBanner permissionDeniedBanner
  assertEqualInt "permission-denied pushes the open interval into event log"
    (Array.length afterPermission.eventLog) 1
  assertEqualInt "permission-denied appends recognition.onerror AND session ended"
    (Array.length afterPermission.diagnostics)
    (Array.length listening2.diagnostics + 2)

  -- Network error: banner set, but listening stays on (recoverable).
  let
    afterNetwork =
      reduce (HandleRecognitionError (testInstant 11000.0) "network" "")
        afterTransient
  assertEqualBoolean "network error keeps listening true"
    afterNetwork.listening true
  assertEqualString "network error sets the network banner"
    afterNetwork.errorBanner networkErrorBanner

  -- Unknown code: banner set with the generic "Recognition error: <code>".
  let
    afterUnknown =
      reduce (HandleRecognitionError (testInstant 12000.0) "weird" "") afterTransient
  assertEqualString "unknown error renders the generic banner"
    afterUnknown.errorBanner (genericRecognitionErrorBanner "weird")

  -- Empty code: banner reads "Recognition error: unknown".
  let
    afterEmpty =
      reduce (HandleRecognitionError (testInstant 13000.0) "" "") afterTransient
  assertEqualString "empty-code error renders the unknown banner"
    afterEmpty.errorBanner noRecognitionErrorBanner

  -- Starting again after an error clears the banner. `afterNetwork` is
  -- still listening (a network error is recoverable), so we have to stop
  -- and then start to exercise the start branch.
  let
    stopped = reduce (Toggle (testInstant 14000.0)) afterNetwork
    cleared = reduce (Toggle (testInstant 14500.0)) stopped
  assertEqualString "Toggle (start) clears any prior errorBanner"
    cleared.errorBanner idleErrorBanner

  -- Reset clears the banner.
  let
    resetAfterError = reduce (Reset (testInstant 15000.0)) afterUnknown
  assertEqualString "Reset clears any prior errorBanner"
    resetAfterError.errorBanner idleErrorBanner

  -- ClearErrorBanner does what it says, idempotently.
  let
    afterClearOnce = reduce ClearErrorBanner afterUnknown
    afterClearTwice = reduce ClearErrorBanner afterClearOnce
  assertEqualString "ClearErrorBanner empties errorBanner"
    afterClearOnce.errorBanner idleErrorBanner
  assertEqualString "ClearErrorBanner is idempotent"
    afterClearTwice.errorBanner idleErrorBanner

  -- Idle (not listening) permission-denied: banner set, no event log push.
  let
    idlePermission =
      reduce (HandleRecognitionError (testInstant 16000.0) "not-allowed" "from idle")
        initialSession
  assertEqualBoolean "idle permission-denied keeps listening false"
    idlePermission.listening false
  assertEqualString "idle permission-denied still sets the banner"
    idlePermission.errorBanner permissionDeniedBanner
  assertEqualInt "idle permission-denied does NOT push an event log entry"
    (Array.length idlePermission.eventLog) 0

runRecognitionDeltaTests :: Effect Unit
runRecognitionDeltaTests = do
  -- Slice 9a: classifyFinalizedTranscript reproduces the legacy
  -- integrateFinalizedTranscript dedup decision tree.
  assertEqualString "normalizeTranscript lowercases + trims + collapses ws"
    (normalizeTranscript "  Hello   THERE  General\tKenobi  ")
    "hello there general kenobi"

  assertEqualBoolean "isWordBoundaryExtension requires a space at the join"
    (isWordBoundaryExtension "twinkles" "twinkle") false
  assertEqualBoolean "isWordBoundaryExtension matches the extended utterance"
    (isWordBoundaryExtension "twinkle twinkle" "twinkle") true
  assertEqualBoolean "isWordBoundaryExtension rejects empty prefix"
    (isWordBoundaryExtension "anything" "") false
  assertEqualBoolean "isWordBoundaryExtension rejects equality"
    (isWordBoundaryExtension "same" "same") false

  -- empty incoming → IgnoreDuplicate
  assertEqualBoolean "empty incoming is IgnoreDuplicate"
    ( classifyFinalizedTranscript { previous: "anything", incoming: "   " }
        == IgnoreDuplicate
    )
    true

  -- exact normalized duplicate → IgnoreDuplicate
  assertEqualBoolean "exact duplicate (case + whitespace insensitive)"
    ( classifyFinalizedTranscript
        { previous: "Twinkle Twinkle", incoming: "twinkle   twinkle" }
        == IgnoreDuplicate
    )
    true

  -- word boundary extension → ExtendUtterance with wordDelta
  assertEqualBoolean "extension is ExtendUtterance with the right delta"
    ( classifyFinalizedTranscript
        { previous: "twinkle twinkle", incoming: "twinkle twinkle little star" }
        ==
          ExtendUtterance
            { wordDelta: 2
            , caption: "twinkle twinkle little star"
            }
    )
    true

  -- earlier snapshot of the same utterance → IgnoreEarlierSnapshot
  assertEqualBoolean "earlier snapshot is IgnoreEarlierSnapshot"
    ( classifyFinalizedTranscript
        { previous: "twinkle twinkle little star", incoming: "twinkle twinkle" }
        == IgnoreEarlierSnapshot
    )
    true

  -- brand new utterance → StartNewUtterance with wordCount
  assertEqualBoolean "brand new utterance is StartNewUtterance"
    ( classifyFinalizedTranscript
        { previous: "twinkle twinkle little star", incoming: "how I wonder what you are" }
        ==
          StartNewUtterance
            { wordCount: 6
            , caption: "how I wonder what you are"
            }
    )
    true

  -- previous = "" with any incoming → StartNewUtterance
  assertEqualBoolean "fresh recognition (no previous) is StartNewUtterance"
    ( classifyFinalizedTranscript { previous: "", incoming: "hello world" }
        ==
          StartNewUtterance { wordCount: 2, caption: "hello world" }
    )
    true

runRecognitionCapabilityTests :: Effect Unit
runRecognitionCapabilityTests = do
  -- The recording capability records every call site in order, so the
  -- orchestrator's start/stop wiring is observable from unit tests
  -- without a browser.
  let
    outcome = runRecordingRecognitionM do
      available <- recognitionApiAvailable
      startRecognition
        { locale: Locale "en-US"
        , onResult: \_ _ -> pure unit
        , onErrorEvent: \_ _ -> pure unit
        , onEnded: pure unit
        , onStarted: pure unit
        , onStartFailure: \_ -> pure unit
        , onConstructFailure: \_ -> pure unit
        }
      scheduleAutoRestart (pure unit)
      cancelAutoRestart
      stopRecognition (pure unit) (\_ -> pure unit)
      pure available
  assertEqualBoolean "RecordingRecognitionM reports recognition available"
    outcome.result true
  assertEqualInt "RecordingRecognitionM records every call in order"
    (Array.length outcome.events) 4
  assertEqualBoolean "first event is StartedRecognition with locale"
    ( outcome.events ==
        [ StartedRecognition { locale: Locale "en-US" }
        , ScheduledAutoRestart
        , CancelledAutoRestart
        , StoppedRecognition
        ]
    )
    true

runIntegrateFinalizedTranscriptReducerTests :: Effect Unit
runIntegrateFinalizedTranscriptReducerTests = do
  -- The reducer projects each TranscriptIntegration onto a session
  -- update. Verify each branch independently.

  -- Idle: a finalized transcript while not listening is a no-op.
  let
    idleAfter =
      reduce (IntegrateFinalizedTranscript (testInstant 1000.0) "ignored") initialSession
  assertEqualInt "idle: totalWords unchanged"
    idleAfter.totalWords 0
  assertEqualString "idle: lastRawFinalizedTranscript unchanged"
    idleAfter.lastRawFinalizedTranscript ""

  -- StartNewUtterance: a fresh transcript while listening adds words,
  -- pushes a caption, and stamps lastRawFinalizedTranscript.
  let
    listening = reduce (Toggle (testInstant 0.0)) initialSession
    afterFirst =
      reduce (IntegrateFinalizedTranscript (testInstant 1000.0) "hello there") listening
  assertEqualInt "first transcript adds 2 words" afterFirst.totalWords 2
  assertEqualInt "first transcript adds one caption"
    (Array.length afterFirst.captions) 1
  assertEqualString "first transcript stamps lastRawFinalizedTranscript"
    afterFirst.lastRawFinalizedTranscript "hello there"

  -- ExtendUtterance: the same in-flight utterance refined by more
  -- words bumps the count by the delta only and replaces the last
  -- caption (no append).
  let
    afterExtension =
      reduce (IntegrateFinalizedTranscript (testInstant 2000.0) "hello there general kenobi")
        afterFirst
  assertEqualInt "extension bumps totalWords by the delta only"
    afterExtension.totalWords 4
  assertEqualInt "extension does NOT add a new caption"
    (Array.length afterExtension.captions) 1
  case Array.head afterExtension.captions of
    Just caption -> assertEqualString "extension replaces the last caption transcript"
      caption.transcript "hello there general kenobi"
    Nothing -> throw "extension should keep one caption"
  assertEqualString "extension updates lastRawFinalizedTranscript"
    afterExtension.lastRawFinalizedTranscript "hello there general kenobi"

  -- IgnoreDuplicate: an exact-normalized refinement leaves the count
  -- alone but refreshes the caption timestamp.
  let
    afterDuplicate =
      reduce (IntegrateFinalizedTranscript (testInstant 3500.0) "Hello   THERE general kenobi")
        afterExtension
  assertEqualInt "duplicate leaves totalWords alone"
    afterDuplicate.totalWords 4
  case Array.head afterDuplicate.captions of
    Just caption -> assertEqualNumber "duplicate refreshes caption timestamp"
      (instantMs caption.timestamp) 3500.0
    Nothing -> throw "duplicate should keep one caption"

  -- IgnoreEarlierSnapshot: the recognizer re-emitting an earlier
  -- segment of the same utterance is a no-op for counts and captions.
  let
    afterEarlier =
      reduce (IntegrateFinalizedTranscript (testInstant 4000.0) "hello there")
        afterExtension
  assertEqualInt "earlier snapshot leaves totalWords alone"
    afterEarlier.totalWords 4

  -- ResetRecognitionDedupState clears the dedup state so the next
  -- utterance after the auto-restart is treated as a brand new
  -- utterance.
  let
    afterReset = reduce ResetRecognitionDedupState afterExtension
  assertEqualString "ResetRecognitionDedupState clears lastRawFinalizedTranscript"
    afterReset.lastRawFinalizedTranscript ""
  assertEqualInt "ResetRecognitionDedupState does NOT change totalWords"
    afterReset.totalWords 4

  -- After the dedup state is cleared, a transcript that previously
  -- looked like an extension now counts as a fresh utterance.
  let
    listeningAfterReset = reduce ResetRecognitionDedupState afterExtension
    afterRestart =
      reduce
        (IntegrateFinalizedTranscript (testInstant 5000.0) "hello there general kenobi")
        listeningAfterReset
  assertEqualInt "fresh utterance after dedup-state reset counts in full"
    afterRestart.totalWords (4 + 4)

  -- Toggle (start) also clears the dedup state.
  let
    stopped = reduce (Toggle (testInstant 6000.0)) afterExtension
    restarted = reduce (Toggle (testInstant 7000.0)) stopped
  assertEqualString "Toggle (start) clears lastRawFinalizedTranscript"
    restarted.lastRawFinalizedTranscript ""

  -- The reducer also appends a "final transcript" diagnostic when it
  -- credits new words (extension or fresh), and not when it ignores.
  let
    beforeDiagnosticsCount = Array.length listening.diagnostics
    afterDiagnostics = Array.length afterFirst.diagnostics
  assertEqualInt "credited transcript appends one diagnostic entry"
    afterDiagnostics (beforeDiagnosticsCount + 1)
  let
    afterDuplicateDiagnostics = Array.length afterDuplicate.diagnostics
    afterExtensionDiagnostics = Array.length afterExtension.diagnostics
  assertEqualInt "duplicate appends no diagnostic entry"
    afterDuplicateDiagnostics afterExtensionDiagnostics

runOnDevicePreflightTests :: Effect Unit
runOnDevicePreflightTests = do
  -- The typed OnDeviceUnavailable ADT is rendered into a stable
  -- diagnostic detail string. The Main orchestrator passes this into
  -- the recognition diagnostic when it falls back to cloud.
  assertEqualString "renderOnDeviceUnavailable OnDeviceApiAbsent"
    (renderOnDeviceUnavailable OnDeviceApiAbsent) "api-absent"
  assertEqualString "renderOnDeviceUnavailable OnDeviceUnsupportedLanguage"
    (renderOnDeviceUnavailable OnDeviceUnsupportedLanguage)
    "unsupported-language"
  assertEqualString "renderOnDeviceUnavailable OnDeviceInstallFailed"
    (renderOnDeviceUnavailable (OnDeviceInstallFailed "quota exceeded"))
    "install-failed: quota exceeded"
  assertEqualString "renderOnDeviceUnavailable OnDeviceAvailabilityRejected"
    (renderOnDeviceUnavailable (OnDeviceAvailabilityRejected "SecurityError"))
    "availability-rejected: SecurityError"

  -- The recording recognition capability surfaces both the
  -- on-device-pre-flight API check and the prepare/start pair so the
  -- orchestrator's call sequence is observable from a unit test.
  let
    outcome = runRecordingRecognitionM do
      apiAvailable <- onDeviceLanguagePackApiAvailable
      prepareOnDeviceLanguagePack
        { locale: Locale "en-US", onProgress: pure unit }
        case _ of
          Right OnDeviceAvailable ->
            startOnDeviceRecognition
              { locale: Locale "en-US"
              , onResult: \_ _ -> pure unit
              , onErrorEvent: \_ _ -> pure unit
              , onEnded: pure unit
              , onStarted: pure unit
              , onStartFailure: \_ -> pure unit
              , onConstructFailure: \_ -> pure unit
              }
          Left _ ->
            startRecognition
              { locale: Locale "en-US"
              , onResult: \_ _ -> pure unit
              , onErrorEvent: \_ _ -> pure unit
              , onEnded: pure unit
              , onStarted: pure unit
              , onStartFailure: \_ -> pure unit
              , onConstructFailure: \_ -> pure unit
              }
      pure apiAvailable
  assertEqualBoolean
    "RecordingRecognitionM reports on-device language pack API available"
    outcome.result true
  assertEqualBoolean
    "RecordingRecognitionM records prepare then on-device start"
    ( outcome.events ==
        [ PreparedOnDeviceLanguagePack { locale: Locale "en-US" }
        , StartedOnDeviceRecognition { locale: Locale "en-US" }
        ]
    )
    true

runRecognitionStatusReducerTests :: Effect Unit
runRecognitionStatusReducerTests = do
  -- The recognitionStatusOverride field starts empty, accepts arbitrary
  -- override text (set by Main during the on-device install), and is
  -- cleared by any stop transition so a stale "downloading…" cannot
  -- outlive the listening session.
  assertEqualString "initialSession has empty recognitionStatusOverride"
    initialSession.recognitionStatusOverride idleRecognitionStatusOverride

  let
    listening = reduce (Toggle (testInstant 0.0)) initialSession
    downloading =
      reduce (SetRecognitionStatusOverride downloadingOnDeviceStatus) listening
  assertEqualString
    "SetRecognitionStatusOverride installs the download status"
    downloading.recognitionStatusOverride downloadingOnDeviceStatus

  let
    cleared =
      reduce (SetRecognitionStatusOverride idleRecognitionStatusOverride)
        downloading
  assertEqualString
    "SetRecognitionStatusOverride with empty string clears the override"
    cleared.recognitionStatusOverride idleRecognitionStatusOverride

  let
    stopped = reduce (Toggle (testInstant 1000.0)) downloading
  assertEqualString
    "Toggle (stop) clears any lingering recognition status override"
    stopped.recognitionStatusOverride idleRecognitionStatusOverride

  -- The status override survives across non-stop reducer actions while
  -- the install is still in flight.
  let
    downloadingAfterTick = reduce (Tick (testInstant 500.0)) downloading
  assertEqualString
    "Tick preserves an in-flight recognitionStatusOverride"
    downloadingAfterTick.recognitionStatusOverride downloadingOnDeviceStatus

  -- Reset returns the session to the empty override.
  let
    afterReset = reduce (Reset (testInstant 9999.0)) downloading
  assertEqualString
    "Reset clears any lingering recognitionStatusOverride"
    afterReset.recognitionStatusOverride idleRecognitionStatusOverride

runCloudFallbackReducerTests :: Effect Unit
runCloudFallbackReducerTests = do
  -- Slice 9c: the one-shot cloud-fallback guard plus the active
  -- recognition path are exposed on Session so the orchestrator (and
  -- the e2e test hook) can observe them.

  -- Default state: never attempted, no active path.
  assertEqualBoolean "initialSession.cloudFallbackAttempted is false"
    initialSession.cloudFallbackAttempted false
  assertEqualBoolean "initialSession.activeRecognitionPath is Nothing"
    (initialSession.activeRecognitionPath == Nothing) true

  -- The two new reducer actions set their respective fields.
  let
    afterFlag =
      reduce (SetCloudFallbackAttempted true) initialSession
  assertEqualBoolean "SetCloudFallbackAttempted true sets the flag"
    afterFlag.cloudFallbackAttempted true
  let
    afterPath =
      reduce (SetActiveRecognitionPath (Just OnDevicePath)) initialSession
  assertEqualBoolean
    "SetActiveRecognitionPath (Just OnDevicePath) sets the active path"
    (afterPath.activeRecognitionPath == Just OnDevicePath) true

  -- Toggle-to-start clears the active path but preserves the
  -- one-shot cloud-fallback flag. Per the user-visible spec, once we
  -- have decided the on-device path is non-viable on this device the
  -- decision sticks until the next user-driven Reset so we do not
  -- re-attempt the pre-flight on every Start press / auto-restart.
  let
    listeningWithFlag =
      reduce (Toggle (testInstant 0.0))
        ( afterFlag
            { activeRecognitionPath = Just OnDevicePath }
        )
  assertEqualBoolean "Toggle (start) preserves cloudFallbackAttempted"
    listeningWithFlag.cloudFallbackAttempted true
  assertEqualBoolean "Toggle (start) clears activeRecognitionPath"
    (listeningWithFlag.activeRecognitionPath == Nothing) true

  -- Toggle-to-stop clears the active path so a stale "on-device"
  -- label cannot outlive a listening session, but leaves the
  -- fallback flag alone (consumed budget stays consumed until the
  -- next start).
  let
    onCloudWithFlag = listeningWithFlag
      { cloudFallbackAttempted = true
      , activeRecognitionPath = Just CloudPath
      }
    stoppedAfterCloud = reduce (Toggle (testInstant 1000.0)) onCloudWithFlag
  assertEqualBoolean "Toggle (stop) clears activeRecognitionPath"
    (stoppedAfterCloud.activeRecognitionPath == Nothing) true
  assertEqualBoolean
    "Toggle (stop) leaves cloudFallbackAttempted alone"
    stoppedAfterCloud.cloudFallbackAttempted true

  -- Reset returns both fields to their initial state.
  let
    afterResetAll = reduce (Reset (testInstant 9999.0)) onCloudWithFlag
  assertEqualBoolean "Reset clears cloudFallbackAttempted"
    afterResetAll.cloudFallbackAttempted false
  assertEqualBoolean "Reset clears activeRecognitionPath"
    (afterResetAll.activeRecognitionPath == Nothing) true

  -- The permission-denied branch of HandleRecognitionError stops
  -- listening and also clears the active path (recognition is no
  -- longer running). This guards against a stale "on-device" label
  -- surviving an aborted session.
  let
    listeningOnDevice =
      reduce (SetActiveRecognitionPath (Just OnDevicePath))
        (reduce (Toggle (testInstant 0.0)) initialSession)
    afterPermissionDenied =
      reduce (HandleRecognitionError (testInstant 5000.0) "not-allowed" "blocked")
        listeningOnDevice
  assertEqualBoolean "permission-denied stops listening"
    afterPermissionDenied.listening false
  assertEqualBoolean
    "permission-denied clears activeRecognitionPath"
    (afterPermissionDenied.activeRecognitionPath == Nothing) true

runDiagnosticsDrawerReducerTests :: Effect Unit
runDiagnosticsDrawerReducerTests = do
  -- The drawer starts closed in the initial session.
  assertEqualBoolean "initialSession.diagnosticsDrawerOpen is false"
    initialSession.diagnosticsDrawerOpen false

  -- SetDiagnosticsDrawerOpen true opens the drawer.
  let
    opened = reduce (SetDiagnosticsDrawerOpen true) initialSession
  assertEqualBoolean "SetDiagnosticsDrawerOpen true sets the field to true"
    opened.diagnosticsDrawerOpen true

  -- SetDiagnosticsDrawerOpen false closes the drawer.
  let
    closed = reduce (SetDiagnosticsDrawerOpen false) opened
  assertEqualBoolean "SetDiagnosticsDrawerOpen false sets the field to false"
    closed.diagnosticsDrawerOpen false

  -- A state update (Toggle) preserves the drawer open state.
  let
    openedSession = reduce (SetDiagnosticsDrawerOpen true) initialSession
    afterToggle = reduce (Toggle (testInstant 1000.0)) openedSession
  assertEqualBoolean "Toggle preserves diagnosticsDrawerOpen"
    afterToggle.diagnosticsDrawerOpen true

  -- A Tick preserves the drawer open state.
  let
    afterTick = reduce (Tick (testInstant 2000.0)) openedSession
  assertEqualBoolean "Tick preserves diagnosticsDrawerOpen"
    afterTick.diagnosticsDrawerOpen true

  -- Reset returns the drawer to closed.
  let
    afterReset = reduce (Reset (testInstant 9999.0)) openedSession
  assertEqualBoolean "Reset closes the diagnostics drawer"
    afterReset.diagnosticsDrawerOpen false

digits :: Array String
digits = [ "0", "1", "2", "3", "4", "5", "6", "7", "8", "9" ]

containsDigit :: String -> Boolean
containsDigit text = Array.any (\digit -> String.contains (String.Pattern digit) text) digits

runPropertyTests :: Effect Unit
runPropertyTests = sequence_
  [ quickCheck formatRateContainsDigit
  , quickCheck formatDurationContainsDigit
  , quickCheck captionOpacityIsInRange
  , quickCheck captionOpacityAtSameTimestampIsOne
  , quickCheck wordsPerMinuteIsZeroWhenNoWords
  , quickCheck wordsPerMinuteIsNonNegative
  , quickCheck wordsPerMinuteAtOneMinuteEqualsWordCount
  , quickCheck sampleFractionIsBetweenZeroAndOne
  , quickCheck formatPercentEndsInPercentSign
  ]

formatRateContainsDigit :: Number -> Boolean
formatRateContainsDigit rate = containsDigit (formatRate rate)

formatDurationContainsDigit :: Number -> Boolean
formatDurationContainsDigit ms = containsDigit (formatDurationMs (abs ms))

captionOpacityIsInRange :: Number -> Number -> Boolean
captionOpacityIsInRange nowMs captionMs =
  let
    opacity = captionOpacity (testInstant (abs nowMs)) (testInstant (abs captionMs))
  in
    opacity >= minimumCaptionOpacity && opacity <= 1.0

captionOpacityAtSameTimestampIsOne :: Number -> Boolean
captionOpacityAtSameTimestampIsOne timestampMs =
  let ts = testInstant (abs timestampMs)
  in captionOpacity ts ts == 1.0

wordsPerMinuteIsZeroWhenNoWords :: Number -> Boolean
wordsPerMinuteIsZeroWhenNoWords elapsed = wordsPerMinute 0 elapsed == 0.0

wordsPerMinuteIsNonNegative :: Int -> Number -> Boolean
wordsPerMinuteIsNonNegative wordCount elapsedMs =
  wordsPerMinute (abs wordCount) (abs elapsedMs) >= 0.0

wordsPerMinuteAtOneMinuteEqualsWordCount :: Int -> Boolean
wordsPerMinuteAtOneMinuteEqualsWordCount wordCount =
  wordsPerMinute (abs wordCount) 60000.0 == Int.toNumber (abs wordCount)

sampleFractionIsBetweenZeroAndOne :: Number -> Number -> Boolean
sampleFractionIsBetweenZeroAndOne wallMs activeMs =
  let
    session =
      initialSession
        { firstStartedAt = Just (testInstant 0.0)
        , now = testInstant (abs wallMs)
        , completedActiveMs = Milliseconds (abs activeMs)
        }
    fraction = sampleFraction session
  in
    fraction >= 0.0 && fraction <= 1.0

formatPercentEndsInPercentSign :: Number -> Boolean
formatPercentEndsInPercentSign value =
  String.contains (String.Pattern "%") (formatPercent value)

runMultiDayStatsTests :: Effect Unit
runMultiDayStatsTests = do
  assertEqualString "formatPercent 0.5 = \"50%\""
    (formatPercent 0.5) "50%"
  assertEqualString "formatPercent 0.0 = \"0%\""
    (formatPercent 0.0) "0%"
  assertEqualString "formatPercent 1.0 = \"100%\""
    (formatPercent 1.0) "100%"
  assertEqualString "formatPercent clamps negatives to 0%"
    (formatPercent (-0.4)) "0%"
  assertEqualString "formatPercent clamps values above 1 to 100%"
    (formatPercent 1.7) "100%"
  assertEqualString "formatPercent rounds 0.124 to 12%"
    (formatPercent 0.124) "12%"

  assertEqualInt "initialSession.wordsToday defaults to 0"
    initialSession.wordsToday 0
  assertEqualBoolean "initialSession.todayLocalDate defaults to Nothing"
    (initialSession.todayLocalDate == Nothing) true

  let
    started = reduce (Toggle (testInstant 1000.0)) initialSession
    counted = reduce
      (InjectFinalTranscript "alpha beta gamma" (testInstant 2000.0))
      started
  assertEqualInt "InjectFinalTranscript bumps wordsToday"
    counted.wordsToday 3
  assertEqualInt "InjectFinalTranscript still bumps the lifetime totalWords"
    counted.totalWords 3
  assertEqualBoolean "InjectFinalTranscript stamps todayLocalDate"
    (counted.todayLocalDate /= Nothing) true

  -- A `Tick` exactly seven days later lands on a different local day
  -- regardless of the runner's timezone, so `wordsToday` must reset
  -- while `totalWords` survives untouched.
  let
    sevenDaysMs = 7.0 * 86_400_000.0
    afterMidnightTick =
      reduce (Tick (testInstant (2000.0 + sevenDaysMs))) counted
  assertEqualInt "Tick across the local midnight zeroes wordsToday"
    afterMidnightTick.wordsToday 0
  assertEqualInt "Tick across the local midnight preserves totalWords"
    afterMidnightTick.totalWords 3
  assertEqualBoolean "todayLocalDate advances when the day rolls over"
    (afterMidnightTick.todayLocalDate /= counted.todayLocalDate) true

  -- A subsequent transcript on the new day starts a fresh today
  -- counter while continuing to accumulate the lifetime total.
  let
    stopped =
      reduce (Toggle (testInstant (2000.0 + sevenDaysMs + 500.0)))
        afterMidnightTick
    restarted =
      reduce (Toggle (testInstant (2000.0 + sevenDaysMs + 1000.0)))
        stopped
    countedNextDay =
      reduce
        ( InjectFinalTranscript "delta epsilon"
            (testInstant (2000.0 + sevenDaysMs + 2000.0))
        )
        restarted
  assertEqualInt "next-day transcript counts toward fresh wordsToday"
    countedNextDay.wordsToday 2
  assertEqualInt "next-day transcript accumulates into totalWords"
    countedNextDay.totalWords 5

  -- A `Reset` clears `wordsToday` along with everything else.
  let
    afterReset = reduce (Reset (testInstant 3000.0)) counted
  assertEqualInt "Reset clears wordsToday"
    afterReset.wordsToday 0
  assertEqualBoolean "Reset clears todayLocalDate"
    (afterReset.todayLocalDate == Nothing) true

  -- `wordsPerDay` and `sampleFraction` math.
  let
    sampleSession = initialSession
      { firstStartedAt = Just (testInstant 0.0)
      , now = testInstant 40_000.0
      , completedActiveMs = Milliseconds 20_000.0
      , totalWords = 8
      }
  assertEqualNumber "sampleFraction 20s active / 40s wall = 0.5"
    (sampleFraction sampleSession) 0.5
  assertEqualNumber "sampleFraction returns 0 before the first start"
    (sampleFraction initialSession) 0.0
  assertEqualNumber "wordsPerDay clamps the denominator to one day minimum"
    (wordsPerDay sampleSession) 8.0
  let
    tenDaySession = sampleSession
      { now = testInstant (10.0 * 86_400_000.0)
      }
  assertEqualNumber "wordsPerDay 8 words / 10 days = 0.8"
    (wordsPerDay tenDaySession) 0.8

  -- Persistence round-trip preserves the new fields.
  let
    persisted = toPersistedData counted
    encoded = encodePersistedData persisted
  assertEqualInt "toPersistedData preserves wordsToday"
    persisted.wordsToday 3
  assertEqualBoolean "toPersistedData preserves todayLocalDate"
    (persisted.todayLocalDate /= Nothing) true
  case decodePersistedData encoded of
    Right decoded -> do
      assertEqualInt "decoded payload preserves wordsToday"
        decoded.wordsToday 3
      assertEqualBoolean "decoded payload preserves todayLocalDate"
        (decoded.todayLocalDate == persisted.todayLocalDate) true
    Left _ -> throw "round-trip of multi-day fields failed"

  -- Legacy payloads without the new fields decode with safe defaults.
  let
    legacyPayload =
      "{\"version\":1,\"totalWords\":5,\"firstStartedAt\":1000,"
        <> "\"wordEvents\":[],\"eventLog\":[]}"
  case decodePersistedData legacyPayload of
    Right legacy -> do
      assertEqualInt "legacy payload defaults wordsToday to 0"
        legacy.wordsToday 0
      assertEqualBoolean "legacy payload defaults todayLocalDate to Nothing"
        (legacy.todayLocalDate == Nothing) true
    Left _ -> throw "legacy payload should decode with default new fields"

  -- A pre-stats event-log entry (no most-frequent / longest fields)
  -- still decodes — the new fields default to Nothing.
  let
    preStatsEventLogPayload =
      "{\"version\":1,\"totalWords\":5,\"firstStartedAt\":1000,"
        <> "\"wordEvents\":[],"
        <> "\"eventLog\":[{\"startedAt\":0,\"endedAt\":1000,\"wordCount\":3}]}"
  case decodePersistedData preStatsEventLogPayload of
    Right legacy -> case legacy.eventLog of
      [ entry ] -> do
        assertEqualInt "pre-stats event-log entry preserves word count"
          entry.wordCount 3
        assertEqualBoolean "pre-stats event-log entry has no most-frequent word"
          (entry.mostFrequentWord == Nothing) true
        assertEqualBoolean "pre-stats event-log entry has no longest word"
          (entry.longestWord == Nothing) true
      _ -> throw "pre-stats payload should decode to one interval"
    Left _ -> throw "pre-stats event-log payload should decode with defaults"

runWordStatsTests :: Effect Unit
runWordStatsTests = do
  -- Empty stats expose nothing.
  assertEqualBoolean "empty stats have no most-frequent word"
    (mostFrequentWord emptyWordStats == Nothing) true
  assertEqualBoolean "empty stats have no longest word"
    (longestWord emptyWordStats == Nothing) true
  assertEqualBoolean "emptyWordStats reports isEmpty true"
    (isEmptyWordStats emptyWordStats) true

  -- Frequency is case-insensitive and ignores surrounding punctuation.
  let
    statsA = addTranscript "Hello world, hello!" emptyWordStats
  case mostFrequentWord statsA of
    Just top -> do
      assertEqualString "case-insensitive top word" top.word "hello"
      assertEqualInt "case-insensitive top count" top.count 2
    Nothing -> throw "expected a most-frequent word"

  -- Longest word preserves casing; punctuation is stripped from ends.
  let
    statsB = addTranscript "Antidisestablishmentarianism, please." emptyWordStats
  case longestWord statsB of
    Just longest ->
      assertEqualString "longest word preserves casing"
        longest "Antidisestablishmentarianism"
    Nothing -> throw "expected a longest word"

  -- Subsequent transcripts accumulate frequencies across the period.
  let
    statsC = addTranscript "the the cat" (addTranscript "the dog" emptyWordStats)
  case mostFrequentWord statsC of
    Just top -> do
      assertEqualString "accumulated top word" top.word "the"
      assertEqualInt "accumulated top count" top.count 3
    Nothing -> throw "expected an accumulated most-frequent word"

  -- Ties on count break alphabetically on the normalized key so the
  -- choice is deterministic across reloads.
  let
    statsTied = addTranscript "bravo alpha" emptyWordStats
  case mostFrequentWord statsTied of
    Just top -> assertEqualString "ties break alphabetically" top.word "alpha"
    Nothing -> throw "expected a top word for a tied period"

  -- Earliest casing wins on length ties.
  let
    statsTiedLength = addTranscript "alpha bravo" emptyWordStats
  case longestWord statsTiedLength of
    Just word -> assertEqualString "length ties keep first-seen casing"
      word "alpha"
    Nothing -> throw "expected a longest word for a tied period"

  -- An all-punctuation transcript yields empty stats.
  let
    statsPunct = addTranscript ",.;!?" emptyWordStats
  assertEqualBoolean "all-punctuation transcript yields empty stats"
    (isEmptyWordStats statsPunct) true

  -- The reducer pipeline freezes per-interval stats into the event
  -- log at stop time.
  let
    s0 = initialSession
    s1 = reduce (Toggle (testInstant 0.0)) s0
    s2 = reduce (InjectFinalTranscript "hello world hello" (testInstant 1000.0)) s1
    s3 = reduce (InjectFinalTranscript "Antidisestablishmentarianism!" (testInstant 2000.0)) s2
    s4 = reduce (Toggle (testInstant 5000.0)) s3
  case s4.eventLog of
    [ entry ] -> do
      case entry.mostFrequentWord of
        Just top -> do
          assertEqualString "stopped interval most-frequent word" top.word "hello"
          assertEqualInt "stopped interval most-frequent count" top.count 2
        Nothing -> throw "stopped interval should have a most-frequent word"
      case entry.longestWord of
        Just longest -> assertEqualString "stopped interval longest word"
          longest "Antidisestablishmentarianism"
        Nothing -> throw "stopped interval should have a longest word"
    _ -> throw "expected exactly one entry in the event log"

  -- Starting a new interval resets the live stats so the next period
  -- starts from a clean slate.
  let
    s5 = reduce (Toggle (testInstant 10000.0)) s4
  assertEqualBoolean "new interval resets currentIntervalWordStats"
    (isEmptyWordStats s5.currentIntervalWordStats) true

  -- The IntegrateFinalizedTranscript extend branch (cumulative
  -- refinement of a single utterance) must only add the trailing
  -- *new* tokens to the frequency tracker — feeding it the entire
  -- refined caption would double-count the words already absorbed
  -- from the prior snapshot.
  let
    e0 = initialSession
    e1 = reduce (Toggle (testInstant 0.0)) e0
    e2 = reduce (IntegrateFinalizedTranscript (testInstant 1000.0) "hello there") e1
    e3 = reduce
      (IntegrateFinalizedTranscript (testInstant 2000.0) "hello there general kenobi")
      e2
  case mostFrequentWord e3.currentIntervalWordStats of
    Just top -> do
      assertEqualInt
        "extend branch adds only new tokens (hello stays at count 1)"
        top.count 1
    Nothing -> throw "extended interval should have a most-frequent word"
  case longestWord e3.currentIntervalWordStats of
    Just longest ->
      assertEqualString
        "extend branch tracks the longest new token"
        longest "general"
    Nothing -> throw "extended interval should have a longest word"

  -- topWords returns empty for empty stats.
  assertEqualInt "topWords empty stats yields empty array"
    (Array.length (topWords emptyWordStats)) 0

  -- topWords returns entries sorted by descending count.
  let
    tw = topWords (addTranscript "the the cat" (addTranscript "the dog" emptyWordStats))
  assertEqualInt "topWords returns all unique words" (Array.length tw) 3
  case Array.head tw of
    Just first -> do
      assertEqualString "topWords first entry is highest-frequency word" first.word "the"
      assertEqualInt "topWords first entry count" first.count 3
    Nothing -> throw "topWords should return at least one entry"
