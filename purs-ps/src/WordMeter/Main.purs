module WordMeter.Main where

import Prelude

import Effect (Effect)
import WordMeter.Recording (Action, initialSession, reduce, view)
import WordMeter.State as State
import WordMeter.TestHook as TestHook
import WordMeter.Vdom (mount)
import WordMeter.Version (version)

hostElementId :: String
hostElementId = "word-meter"

main :: Effect Unit
main = do
  sessionCell <- State.new initialSession
  let
    rerender :: Effect Unit
    rerender = do
      session <- State.read sessionCell
      mount hostElementId (view send session)

    send :: Action -> Effect Unit
    send action = do
      State.modify (reduce action) sessionCell
      rerender
  rerender
  TestHook.install
    { send
    , readSession: State.read sessionCell
    , version
    }
