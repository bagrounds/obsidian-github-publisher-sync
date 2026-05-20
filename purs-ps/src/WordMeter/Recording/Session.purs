module WordMeter.Recording.Session
  ( Session
  , Caption
  , WordEvent
  , LoggedInterval
  , PersistedData
  , PersistedWordEvent
  , PersistedLoggedInterval
  , WakeLockState(..)
  , epochInstant
  , initialSession
  , renderWakeLockStatus
  , captionWindowMs
  , minimumCaptionOpacity
  , eventLogLimit
  , shortWindowMs
  , longWindowMs
  , idleCopyStatus
  , downloadingOnDeviceStatus
  , idleRecognitionStatusOverride
  , idleErrorBanner
  , resetConfirmationPrompt
  ) where

import Prelude

import Data.DateTime.Instant (Instant, instant)
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Time.Duration (Milliseconds(..))
import WordMeter.Diagnostics (DiagnosticEntry, EnvironmentSnapshot)
import WordMeter.LocalDate (LocalDate)
import WordMeter.Recognition.Path (RecognitionPath)
import WordMeter.WordStats (WordStats, emptyWordStats)

type Session =
  { listening :: Boolean
  , totalWords :: Int
  , wordsToday :: Int
  , todayLocalDate :: Maybe LocalDate
  , captions :: Array Caption
  , wordEvents :: Array WordEvent
  , eventLog :: Array LoggedInterval
  , currentIntervalWords :: Int
  , firstStartedAt :: Maybe Instant
  , currentIntervalStart :: Maybe Instant
  , completedActiveMs :: Milliseconds
  , now :: Instant
  , diagnostics :: Array DiagnosticEntry
  , environment :: Maybe EnvironmentSnapshot
  , copyStatus :: String
  , keepAwake :: Boolean
  , wakeLockState :: WakeLockState
  , errorBanner :: String
  , lastRawFinalizedTranscript :: String
  , recognitionStatusOverride :: String
  , cloudFallbackAttempted :: Boolean
  , activeRecognitionPath :: Maybe RecognitionPath
  , diagnosticsDrawerOpen :: Boolean
  , currentIntervalWordStats :: WordStats
  , pipOpen :: Boolean
  , pipStatus :: String
  }

type Caption =
  { transcript :: String
  , wordCount :: Int
  , timestamp :: Instant
  }

type WordEvent =
  { timestamp :: Instant
  , wordCount :: Int
  }

type LoggedInterval =
  { startedAt :: Instant
  , endedAt :: Instant
  , wordCount :: Int
  , mostFrequentWord :: Maybe { word :: String, count :: Int }
  , longestWord :: Maybe String
  }

-- | Persisted versions of `WordEvent` and `LoggedInterval` use raw
-- | `Number` millisecond timestamps so that JSON encoding round-trips
-- | cleanly without requiring Argonaut codec instances for `Instant`.
type PersistedWordEvent =
  { timestamp :: Number
  , wordCount :: Int
  }

type PersistedLoggedInterval =
  { startedAt :: Number
  , endedAt :: Number
  , wordCount :: Int
  , mostFrequentWord :: Maybe String
  , mostFrequentWordCount :: Maybe Int
  , longestWord :: Maybe String
  }

type PersistedData =
  { totalWords :: Int
  , wordsToday :: Int
  , todayLocalDate :: Maybe String
  , firstStartedAt :: Maybe Number
  , completedActiveMs :: Number
  , cloudFallbackAttempted :: Boolean
  , wordEvents :: Array PersistedWordEvent
  , eventLog :: Array PersistedLoggedInterval
  }

-- | The three states a wake lock can be in. Replaces the pair of
-- | `wakeLockHeld :: Boolean` + `keepAwakeStatus :: String` fields,
-- | making impossible combinations (e.g. `held = false` while status
-- | reads "screen will stay on") unrepresentable.
data WakeLockState
  = WakeLockIdle
  | WakeLockHeld
  | WakeLockFailed String

derive instance eqWakeLockState :: Eq WakeLockState

-- | Render the user-visible status string for a `WakeLockState`.
-- | Returns empty string for `WakeLockIdle` (no visible status),
-- | "screen will stay on" for `WakeLockHeld`, and the failure reason
-- | wrapped in parentheses for `WakeLockFailed`.
renderWakeLockStatus :: WakeLockState -> String
renderWakeLockStatus WakeLockIdle = ""
renderWakeLockStatus WakeLockHeld = "screen will stay on"
renderWakeLockStatus (WakeLockFailed reason) = "(" <> reason <> ")"

captionWindowMs :: Number
captionWindowMs = 30000.0

minimumCaptionOpacity :: Number
minimumCaptionOpacity = 0.15

eventLogLimit :: Int
eventLogLimit = 200

shortWindowMs :: Number
shortWindowMs = 60000.0

longWindowMs :: Number
longWindowMs = 600000.0

idleCopyStatus :: String
idleCopyStatus = ""

-- | Status text shown while the static `SpeechRecognition.install()`
-- | call is in flight downloading the on-device language pack.
downloadingOnDeviceStatus :: String
downloadingOnDeviceStatus = "downloading on-device language pack…"

idleRecognitionStatusOverride :: String
idleRecognitionStatusOverride = ""

idleErrorBanner :: String
idleErrorBanner = ""

resetConfirmationPrompt :: String
resetConfirmationPrompt =
  "Reset all word meter stats? This cannot be undone."

-- | The Unix epoch as an `Instant` (0 milliseconds offset). Used as
-- | the initial `now` value in `initialSession` and as a fallback when
-- | converting raw millisecond numbers that are known to be in range.
epochInstant :: Instant
epochInstant = fromMaybe bottom (instant (Milliseconds 0.0))

initialSession :: Session
initialSession =
  { listening: false
  , totalWords: 0
  , wordsToday: 0
  , todayLocalDate: Nothing
  , captions: []
  , wordEvents: []
  , eventLog: []
  , currentIntervalWords: 0
  , firstStartedAt: Nothing
  , currentIntervalStart: Nothing
  , completedActiveMs: Milliseconds 0.0
  , now: epochInstant
  , diagnostics: []
  , environment: Nothing
  , copyStatus: idleCopyStatus
  , keepAwake: true
  , wakeLockState: WakeLockIdle
  , errorBanner: idleErrorBanner
  , lastRawFinalizedTranscript: ""
  , recognitionStatusOverride: idleRecognitionStatusOverride
  , cloudFallbackAttempted: false
  , activeRecognitionPath: Nothing
  , diagnosticsDrawerOpen: false
  , currentIntervalWordStats: emptyWordStats
  , pipOpen: false
  , pipStatus: ""
  }
