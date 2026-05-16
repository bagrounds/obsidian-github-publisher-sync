module WordMeter.Recording.Session
  ( Session
  , Caption
  , WordEvent
  , LoggedInterval
  , PersistedData
  , WakeLockState(..)
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

import Data.Maybe (Maybe(..))
import WordMeter.Diagnostics (DiagnosticEntry, EnvironmentSnapshot)
import WordMeter.Recognition.Path (RecognitionPath)

type Session =
  { listening :: Boolean
  , totalWords :: Int
  , captions :: Array Caption
  , wordEvents :: Array WordEvent
  , eventLog :: Array LoggedInterval
  , currentIntervalWords :: Int
  , firstStartedAt :: Maybe Number
  , currentIntervalStart :: Maybe Number
  , completedActiveMs :: Number
  , now :: Number
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
  }

type Caption =
  { transcript :: String
  , wordCount :: Int
  , timestamp :: Number
  }

type WordEvent =
  { timestamp :: Number
  , wordCount :: Int
  }

type LoggedInterval =
  { startedAt :: Number
  , endedAt :: Number
  , wordCount :: Int
  }

type PersistedData =
  { totalWords :: Int
  , firstStartedAt :: Maybe Number
  , wordEvents :: Array WordEvent
  , eventLog :: Array LoggedInterval
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

-- | Slice-9b status text shown while the static
-- | `SpeechRecognition.install()` call is in flight downloading the
-- | on-device language pack.
downloadingOnDeviceStatus :: String
downloadingOnDeviceStatus = "downloading on-device language pack…"

idleRecognitionStatusOverride :: String
idleRecognitionStatusOverride = ""

idleErrorBanner :: String
idleErrorBanner = ""

resetConfirmationPrompt :: String
resetConfirmationPrompt =
  "Reset all word meter stats? This cannot be undone."

initialSession :: Session
initialSession =
  { listening: false
  , totalWords: 0
  , captions: []
  , wordEvents: []
  , eventLog: []
  , currentIntervalWords: 0
  , firstStartedAt: Nothing
  , currentIntervalStart: Nothing
  , completedActiveMs: 0.0
  , now: 0.0
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
  }
