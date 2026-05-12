module WordMeter.TestHook (install) where

import Prelude

import Data.Maybe (fromMaybe)
import Effect (Effect)
import WordMeter.Recording
  ( Action(..)
  , Dispatch
  , Session
  , activeListeningMs
  , longRate
  , overallRate
  , shortRate
  )

foreign import installTestHookImpl
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
     }
  -> Effect Unit

-- | Wire up the `window.__wordMeter` bridge. `dispatch` drops fully
-- | timestamped actions straight into the reducer so tests can drive a
-- | deterministic clock; `clock` is the real wall-clock used by the
-- | non-timestamped convenience entry points.
install
  :: { dispatch :: Dispatch
     , readSession :: Effect Session
     , clock :: Effect Number
     , version :: String
     }
  -> Effect Unit
install { dispatch, readSession, clock, version } =
  installTestHookImpl
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
    }

-- | Surface `firstStartedAt` as a Number across the FFI boundary. Returning
-- | NaN for the "never started" case keeps the JS-facing signature uniform
-- | (always a Number) — callers check for NaN to detect "not yet started".
firstStartedOrNaN :: Session -> Number
firstStartedOrNaN session = fromMaybe nanLiteral session.firstStartedAt
  where
  -- A single NaN sentinel; pulled out so the case branch stays tidy.
  nanLiteral = 0.0 / 0.0
