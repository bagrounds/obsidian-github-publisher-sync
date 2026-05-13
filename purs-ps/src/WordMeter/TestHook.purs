module WordMeter.TestHook (install) where

import Prelude

import Data.Array (length) as Array
import Data.Maybe (fromMaybe)
import Effect (Effect)
import WordMeter.Diagnostics (diagnosticsLimit)
import WordMeter.Recording
  ( Action(..)
  , Dispatch
  , Session
  , activeListeningMs
  , diagnosticsText
  , eventLogLimit
  , longRate
  , overallRate
  , shortRate
  )

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
     }
  -> Effect Unit

install
  :: { dispatch :: Dispatch
     , readSession :: Effect Session
     , clock :: Effect Number
     , version :: String
     , requestCopyDiagnostics :: Effect Unit
     , requestReset :: Effect Unit
     , persistNow :: Effect Unit
     }
  -> Effect Unit
install
  { dispatch
  , readSession
  , clock
  , version
  , requestCopyDiagnostics
  , requestReset
  , persistNow
  } =
  installTestHook
    { simulateFinalTranscript: \transcript -> do
        timestamp <- clock
        dispatch (InjectFinalTranscript transcript timestamp)
    , simulateFinalTranscriptAt: \transcript timestamp ->
        dispatch (InjectFinalTranscript transcript timestamp)
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
    , startAt: \timestamp -> do
        session <- readSession
        if session.listening then pure unit
        else dispatch (Toggle timestamp)
    , stopAt: \timestamp -> do
        session <- readSession
        if session.listening then dispatch (Toggle timestamp)
        else pure unit
    , tick: \timestamp -> dispatch (Tick timestamp)
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
    , resetAt: \timestamp -> dispatch (Reset timestamp)
    , persistNow
    }

firstStartedOrNaN :: Session -> Number
firstStartedOrNaN session = fromMaybe (0.0 / 0.0) session.firstStartedAt
