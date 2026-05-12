module WordMeter.Main where

import Prelude

import Effect (Effect)
import WordMeter.Clock (nowMs)
import WordMeter.Recording (Action(..), Dispatch, initialSession, reduce, view)
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
      mount hostElementId (view { requestToggle } session)

    dispatch :: Dispatch
    dispatch action = do
      State.modify (reduce action) sessionCell
      rerender

    requestToggle :: Effect Unit
    requestToggle = do
      timestamp <- nowMs
      dispatch (Toggle timestamp)
  rerender
  TestHook.install
    { dispatch
    , readSession: State.read sessionCell
    , clock: nowMs
    , version
    }
