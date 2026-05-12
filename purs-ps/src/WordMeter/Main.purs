module WordMeter.Main where

import Prelude

import Effect (Effect)
import WordMeter.Clipboard as Clipboard
import WordMeter.Clock (nowMs)
import WordMeter.Environment (captureEnvironmentSnapshot)
import WordMeter.Recording
  ( Action(..)
  , Dispatch
  , diagnosticsText
  , initialSession
  , reduce
  , view
  )
import WordMeter.State as State
import WordMeter.TestHook as TestHook
import WordMeter.Vdom (mount)
import WordMeter.Version (version)

hostElementId :: String
hostElementId = "word-meter"

main :: Effect Unit
main = do
  sessionCell <- State.new initialSession
  environment <- captureEnvironmentSnapshot version
  let
    rerender :: Effect Unit
    rerender = do
      session <- State.read sessionCell
      mount hostElementId (view { requestToggle, requestCopyDiagnostics } session)

    dispatch :: Dispatch
    dispatch action = do
      State.modify (reduce action) sessionCell
      rerender

    requestToggle :: Effect Unit
    requestToggle = do
      timestamp <- nowMs
      dispatch (Toggle timestamp)

    requestCopyDiagnostics :: Effect Unit
    requestCopyDiagnostics = do
      session <- State.read sessionCell
      let payload = diagnosticsText session
      Clipboard.writeText payload
        (dispatch (SetCopyStatus "Copied!"))
        (\reason -> dispatch (SetCopyStatus ("Copy failed: " <> reason)))

  dispatch (SetEnvironment environment)
  initTimestamp <- nowMs
  dispatch (RecordDiagnostic initTimestamp "init" ("version=" <> version))
  TestHook.install
    { dispatch
    , readSession: State.read sessionCell
    , clock: nowMs
    , version
    , requestCopyDiagnostics
    }
