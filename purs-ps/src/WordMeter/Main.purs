module WordMeter.Main where

import Prelude

import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Effect (Effect)
import Effect.Class (class MonadEffect, liftEffect)
import Effect.Ref as Ref
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
import WordMeter.Capability.Storage
  ( class Storage
  , LoadError
  , clearPersistedSnapshot
  , loadPersistedSnapshot
  , persistSnapshot
  , renderLoadError
  )
import WordMeter.FFI.Confirm (ConfirmError, askForConfirmation, renderConfirmError)
import WordMeter.FFI.StorageError (StorageError, renderStorageError)
import WordMeter.Recording
  ( Action(..)
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
    , requestReset: handlers.requestReset
    , persistNow: runAppM applicationEnvironment persistCurrentSession
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
  snapshot <- captureEnvironmentSnapshot version
  updateSession (SetEnvironment snapshot)
  restored <- loadPersistedSnapshot
  case restored of
    Right Nothing -> pure unit
    Right (Just persisted) -> updateSession (LoadSession persisted)
    Left loadFailure -> recordLoadFailure loadFailure
  initTimestamp <- currentTimeMillis
  updateSession
    (RecordDiagnostic initTimestamp "init" ("version=" <> version))
  rerender handlers

dispatch
  :: forall m
   . Clock m
  => DomMount m
  => SessionState m
  => Storage m
  => ClickHandlers
  -> Action
  -> m Unit
dispatch handlers action = do
  updateSession action
  persistAfterAction action
  rerender handlers

persistAfterAction
  :: forall m
   . Clock m
  => SessionState m
  => Storage m
  => Action
  -> m Unit
persistAfterAction (Toggle _) = persistCurrentSession
persistAfterAction (InjectFinalTranscript _ _) = persistCurrentSession
persistAfterAction (Reset _) = do
  outcome <- clearPersistedSnapshot
  case outcome of
    Right _ -> pure unit
    Left storageFailure -> recordStorageFailure "persist clear" storageFailure
persistAfterAction (LoadSession _) = pure unit
persistAfterAction (Tick _) = pure unit
persistAfterAction (RecordDiagnostic _ _ _) = pure unit
persistAfterAction (SetEnvironment _) = pure unit
persistAfterAction (SetCopyStatus _) = pure unit

persistCurrentSession
  :: forall m
   . Clock m
  => SessionState m
  => Storage m
  => m Unit
persistCurrentSession = do
  session <- readCurrentSession
  outcome <- persistSnapshot (toPersistedData session)
  case outcome of
    Right _ -> pure unit
    Left storageFailure -> recordStorageFailure "persist save" storageFailure

recordLoadFailure
  :: forall m. Clock m => SessionState m => LoadError -> m Unit
recordLoadFailure failure = do
  timestamp <- currentTimeMillis
  updateSession
    (RecordDiagnostic timestamp "persist load failure" (renderLoadError failure))

recordStorageFailure
  :: forall m. Clock m => SessionState m => String -> StorageError -> m Unit
recordStorageFailure label failure = do
  timestamp <- currentTimeMillis
  updateSession
    (RecordDiagnostic timestamp (label <> " failure") (renderStorageError failure))

recordConfirmFailure
  :: forall m. Clock m => SessionState m => ConfirmError -> m Unit
recordConfirmFailure failure = do
  timestamp <- currentTimeMillis
  updateSession
    ( RecordDiagnostic timestamp "reset confirm failure"
        (renderConfirmError failure)
    )

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
   . Clock m
  => Clipboard m
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
  => Clock m
  => DomMount m
  => SessionState m
  => Storage m
  => ClickHandlers
  -> m Unit
handleReset handlers = do
  outcome <- liftEffect (askForConfirmation resetConfirmationPrompt)
  case outcome of
    Right true -> do
      timestamp <- currentTimeMillis
      dispatch handlers (Reset timestamp)
    Right false -> pure unit
    Left confirmFailure -> recordConfirmFailure confirmFailure
