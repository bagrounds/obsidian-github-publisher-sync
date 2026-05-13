module WordMeter.Main where

import Prelude

import Effect (Effect)
import Effect.Class (class MonadEffect, liftEffect)
import Effect.Ref as Ref
import Data.Maybe (Maybe(..))
import WordMeter.AppM (ApplicationEnvironment, runAppM)
import WordMeter.Capability.Clipboard (class Clipboard, writeClipboardText)
import WordMeter.Capability.Clock (class Clock, currentTimeMillis)
import WordMeter.Capability.DomMount (class DomMount, mountToHost)
import WordMeter.Capability.Environment (class Environment, captureEnvironmentSnapshot)
import WordMeter.Capability.SessionState
  ( class SessionState
  , readCurrentSession
  , updateSession
  )
import WordMeter.Capability.Storage (class Storage, clearPersistedData, loadPersistedData, savePersistedData)
import WordMeter.FFI.Confirm as Confirm
import WordMeter.Recording
  ( Action(..)
  , Session
  , diagnosticsText
  , initialSession
  , resetConfirmationPrompt
  , toPersistedData
  , view
  )
import WordMeter.TestHook as TestHook
import WordMeter.Version (version)

hostElementId :: String
hostElementId = "word-meter"

type ClickHandlers =
  { requestToggle :: Effect Unit
  , requestCopyDiagnostics :: Effect Unit
  , requestReset :: Effect Unit
  }

main :: Effect Unit
main = do
  sessionRef <- Ref.new initialSession
  clickHandlersRef <- Ref.new
    { requestToggle: pure unit :: Effect Unit
    , requestCopyDiagnostics: pure unit :: Effect Unit
    , requestReset: pure unit :: Effect Unit
    }
  let
    applicationEnvironment :: ApplicationEnvironment
    applicationEnvironment = { sessionRef }

    readClickHandlers :: Effect ClickHandlers
    readClickHandlers = Ref.read clickHandlersRef

    handlers :: ClickHandlers
    handlers =
      { requestToggle: readClickHandlers >>= \resolved ->
          runAppM applicationEnvironment (handleToggle resolved)
      , requestCopyDiagnostics: readClickHandlers >>= \resolved ->
          runAppM applicationEnvironment (handleCopyDiagnostics resolved)
      , requestReset: readClickHandlers >>= \resolved ->
          runAppM applicationEnvironment (handleReset resolved)
      }
  Ref.write handlers clickHandlersRef
  runAppM applicationEnvironment (startApplication handlers)
  TestHook.install
    { dispatch: \action ->
        runAppM applicationEnvironment (dispatch handlers action)
    , readSession: Ref.read sessionRef
    , clock: runAppM applicationEnvironment currentTimeMillis
    , version
    , requestCopyDiagnostics: handlers.requestCopyDiagnostics
    , reset: runAppM applicationEnvironment do
        updateSession Reset
        clearPersistedData
        rerender handlers
    , persistNow: do
        session <- Ref.read sessionRef
        runAppM applicationEnvironment (savePersistedData (toPersistedData session))
    }

startApplication
  :: forall m
   . Clock m
  => Environment m
  => DomMount m
  => SessionState m
  => Storage m
  => ClickHandlers
  -> m Unit
startApplication handlers = do
  maybePersistedData <- loadPersistedData
  case maybePersistedData of
    Just persisted -> updateSession (LoadSession persisted)
    Nothing -> pure unit
  snapshot <- captureEnvironmentSnapshot version
  updateSession (SetEnvironment snapshot)
  initTimestamp <- currentTimeMillis
  updateSession
    (RecordDiagnostic initTimestamp "init" ("version=" <> version))
  rerender handlers

dispatch
  :: forall m
   . DomMount m
  => SessionState m
  => Storage m
  => ClickHandlers
  -> Action
  -> m Unit
dispatch handlers action = do
  updateSession action
  session <- readCurrentSession
  persistAfterAction action session
  rerender handlers

persistAfterAction
  :: forall m
   . Storage m
  => Action
  -> Session
  -> m Unit
persistAfterAction Reset _ = clearPersistedData
persistAfterAction (Tick _) _ = pure unit
persistAfterAction (RecordDiagnostic _ _ _) _ = pure unit
persistAfterAction (SetEnvironment _) _ = pure unit
persistAfterAction (SetCopyStatus _) _ = pure unit
persistAfterAction (LoadSession _) _ = pure unit
persistAfterAction _ session = savePersistedData (toPersistedData session)

rerender
  :: forall m
   . DomMount m
  => SessionState m
  => ClickHandlers
  -> m Unit
rerender handlers = do
  session <- readCurrentSession
  mountToHost hostElementId (view handlers session)

handleToggle
  :: forall m
   . Clock m
  => DomMount m
  => SessionState m
  => Storage m
  => ClickHandlers
  -> m Unit
handleToggle handlers = do
  timestamp <- currentTimeMillis
  dispatch handlers (Toggle timestamp)

handleCopyDiagnostics
  :: forall m
   . Clipboard m
  => DomMount m
  => SessionState m
  => Storage m
  => ClickHandlers
  -> m Unit
handleCopyDiagnostics handlers = do
  session <- readCurrentSession
  writeClipboardText
    (diagnosticsText session)
    (dispatch handlers (SetCopyStatus "Copied!"))
    ( \reason ->
        dispatch handlers (SetCopyStatus ("Copy failed: " <> reason))
    )

handleReset
  :: forall m
   . MonadEffect m
  => DomMount m
  => SessionState m
  => Storage m
  => ClickHandlers
  -> m Unit
handleReset handlers = do
  confirmed <- liftEffect (Confirm.requestConfirmation resetConfirmationPrompt)
  if confirmed then do
    updateSession Reset
    clearPersistedData
    rerender handlers
  else pure unit
