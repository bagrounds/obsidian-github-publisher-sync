module WordMeter.TestHook (install) where

import Prelude

import Data.Array (length) as Array
import Data.DateTime.Instant (Instant, instant, unInstant)
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Newtype (unwrap)
import Data.Time.Duration (Milliseconds(..))
import Effect (Effect)
import WordMeter.Diagnostics (diagnosticsLimit)
import WordMeter.Recognition.Path (RecognitionPath(..))
import WordMeter.Recording.Math
  ( activeListeningMs
  , longRate
  , overallRate
  , shortRate
  )
import WordMeter.Recording.Reducer (Action(..), Dispatch)
import WordMeter.Recording.Session
  ( Session
  , WakeLockState(..)
  , epochInstant
  , eventLogLimit
  , renderWakeLockStatus
  )
import WordMeter.Recording.View (diagnosticsText)

foreign import installTestHook
  :: { simulateFinalTranscript :: String -> Effect Unit
     , simulateFinalTranscriptAt :: String -> Number -> Effect Unit
     , start :: Effect Unit
     , stop :: Effect Unit
     , startAt :: Number -> Effect Unit
     , stopAt :: Number -> Effect Unit
     , tick :: Number -> Effect Unit
     , getTotalWords :: Effect Int
     , getListening :: Effect Boolean
     , getVersion :: Effect String
     , getRateShort :: Effect Number
     , getRateLong :: Effect Number
     , getRateOverall :: Effect Number
     , getDurationMs :: Effect Number
     , getFirstStartedAt :: Effect Number
     , getEventLogLength :: Effect Int
     , getEventLogLimit :: Effect Int
     , getDiagnosticsText :: Effect String
     , getDiagnosticsLength :: Effect Int
     , getDiagnosticsLimit :: Effect Int
     , getCopyStatus :: Effect String
     , requestCopyDiagnostics :: Effect Unit
     , reset :: Effect Unit
     , resetAt :: Number -> Effect Unit
     , persistNow :: Effect Unit
     , getKeepAwake :: Effect Boolean
     , setKeepAwake :: Boolean -> Effect Unit
     , getKeepAwakeStatus :: Effect String
     , getWakeLockHeld :: Effect Boolean
     , simulateVisibilityVisible :: Effect Unit
     , simulateRecognitionError :: String -> String -> Effect Unit
     , getErrorBanner :: Effect String
     , getRecognitionStatusOverride :: Effect String
     , getCloudFallbackAttempted :: Effect Boolean
     , getActiveRecognitionPath :: Effect String
     , setActiveRecognitionPath :: String -> Effect Unit
     , getDiagnosticsDrawerOpen :: Effect Boolean
     , toggleDiagnosticsDrawer :: Effect Unit
     }
  -> Effect Unit

install
  :: { dispatch :: Dispatch
     , readSession :: Effect Session
     , clock :: Effect Instant
     , version :: String
     , requestCopyDiagnostics :: Effect Unit
     , requestReset :: Effect Unit
     , requestSetKeepAwake :: Boolean -> Effect Unit
     , persistNow :: Effect Unit
     , simulateVisibilityVisible :: Effect Unit
     , simulateRecognitionError :: String -> String -> Effect Unit
     , requestToggleDiagnosticsDrawer :: Effect Unit
     }
  -> Effect Unit
install
  { dispatch
  , readSession
  , clock
  , version
  , requestCopyDiagnostics
  , requestReset
  , requestSetKeepAwake
  , persistNow
  , simulateVisibilityVisible
  , simulateRecognitionError
  , requestToggleDiagnosticsDrawer
  } =
  installTestHook
    { simulateFinalTranscript: \transcript -> do
        timestamp <- clock
        dispatch (InjectFinalTranscript transcript timestamp)
    , simulateFinalTranscriptAt: \transcript timestampMs ->
        dispatch (InjectFinalTranscript transcript (millisToInstant timestampMs))
    , start: do
        session <- readSession
        if session.listening then pure unit
        else do
          timestamp <- clock
          dispatch (Toggle timestamp)
    , stop: do
        session <- readSession
        if session.listening then do
          timestamp <- clock
          dispatch (Toggle timestamp)
        else pure unit
    , startAt: \timestampMs -> do
        session <- readSession
        if session.listening then pure unit
        else dispatch (Toggle (millisToInstant timestampMs))
    , stopAt: \timestampMs -> do
        session <- readSession
        if session.listening then dispatch (Toggle (millisToInstant timestampMs))
        else pure unit
    , tick: \timestampMs -> dispatch (Tick (millisToInstant timestampMs))
    , getTotalWords: _.totalWords <$> readSession
    , getListening: _.listening <$> readSession
    , getVersion: pure version
    , getRateShort: shortRate <$> readSession
    , getRateLong: longRate <$> readSession
    , getRateOverall: overallRate <$> readSession
    , getDurationMs: activeListeningMs <$> readSession
    , getFirstStartedAt: firstStartedOrNaN <$> readSession
    , getEventLogLength: (\s -> Array.length s.eventLog) <$> readSession
    , getEventLogLimit: pure eventLogLimit
    , getDiagnosticsText: diagnosticsText <$> readSession
    , getDiagnosticsLength: (\s -> Array.length s.diagnostics) <$> readSession
    , getDiagnosticsLimit: pure diagnosticsLimit
    , getCopyStatus: _.copyStatus <$> readSession
    , requestCopyDiagnostics
    , reset: requestReset
    , resetAt: \timestampMs -> dispatch (Reset (millisToInstant timestampMs))
    , persistNow
    , getKeepAwake: _.keepAwake <$> readSession
    , setKeepAwake: requestSetKeepAwake
    , getKeepAwakeStatus: (\s -> renderWakeLockStatus s.wakeLockState) <$> readSession
    , getWakeLockHeld: (\s -> s.wakeLockState == WakeLockHeld) <$> readSession
    , simulateVisibilityVisible
    , simulateRecognitionError
    , getErrorBanner: _.errorBanner <$> readSession
    , getRecognitionStatusOverride: _.recognitionStatusOverride <$> readSession
    , getCloudFallbackAttempted: _.cloudFallbackAttempted <$> readSession
    , getActiveRecognitionPath: renderActivePath <$> readSession
    , setActiveRecognitionPath: \label ->
        dispatch (SetActiveRecognitionPath (parseActivePath label))
    , getDiagnosticsDrawerOpen: _.diagnosticsDrawerOpen <$> readSession
    , toggleDiagnosticsDrawer: requestToggleDiagnosticsDrawer
    }

-- | Convert a raw millisecond value from the JavaScript test helpers
-- | to an `Instant`, falling back to the epoch for any value outside
-- | the valid `Instant` range (astronomically impossible for test inputs).
millisToInstant :: Number -> Instant
millisToInstant ms = fromMaybe epochInstant (instant (Milliseconds ms))

parseActivePath :: String -> Maybe RecognitionPath
parseActivePath = case _ of
  "on-device" -> Just OnDevicePath
  "cloud" -> Just CloudPath
  _ -> Nothing

renderActivePath :: Session -> String
renderActivePath session = case session.activeRecognitionPath of
  Nothing -> ""
  Just OnDevicePath -> "on-device"
  Just CloudPath -> "cloud"

firstStartedOrNaN :: Session -> Number
firstStartedOrNaN session = case session.firstStartedAt of
  Nothing -> 0.0 / 0.0
  Just inst -> unwrap (unInstant inst)
