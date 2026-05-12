module WordMeter.TestHook (install) where

import Prelude

import Effect (Effect)
import WordMeter.Recording (Action(..), Send, Session)

foreign import installTestHookImpl
  :: { simulateFinalTranscript :: String -> Effect Unit
     , start :: Effect Unit
     , stop :: Effect Unit
     , getTotalWords :: Effect Int
     , getListening :: Effect Boolean
     , getVersion :: Effect String
     }
  -> Effect Unit

install :: { send :: Send, readSession :: Effect Session, version :: String } -> Effect Unit
install { send, readSession, version } =
  installTestHookImpl
    { simulateFinalTranscript: \transcript -> send (InjectFinalTranscript transcript)
    , start: do
        session <- readSession
        if session.listening then pure unit else send Toggle
    , stop: do
        session <- readSession
        if session.listening then send Toggle else pure unit
    , getTotalWords: do
        session <- readSession
        pure session.totalWords
    , getListening: do
        session <- readSession
        pure session.listening
    , getVersion: pure version
    }
