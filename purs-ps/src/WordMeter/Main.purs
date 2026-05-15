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
import WordMeter.Capability.WakeLock
  ( class WakeLock
  , releaseScreenWakeLock
  , requestScreenWakeLock
  )
import WordMeter.FFI.Confirm (ConfirmError, askForConfirmation, renderConfirmError)
import WordMeter.FFI.StorageError (StorageError, renderStorageError)
import WordMeter.FFI.Visibility (onPageBecameVisible)
import WordMeter.FFI.WakeLock (WakeLockError, renderWakeLockError)
import WordMeter.Recording
  ( Action(..)
  , diagnosticsText
  , idleKeepAwakeStatus
  , initialSession
  , renderKeepAwakeUnavailable
  , resetConfirmationPrompt
  , toPersistedData
  , view
  , wakeLockAcquiredStatus
  )
import WordMeter.TestHook as TestHook
import WordMeter.Version (version)

hostElementId :: String
hostElementId = "word-meter"

type ClickHandlers =
  { requestToggle :: Effect Unit
  , requestCopyDiagnostics :: Effect Unit
  , requestReset :: Effect Unit
  , requestSetKeepAwake :: Boolean -> Effect Unit
  }

main :: Effect Unit
main = do
  sessionRef <- Ref.new initialSession
  wakeLockSentinelRef <- Ref.new Nothing
  clickHandlersRef <- Ref.new
    { requestToggle: pure unit :: Effect Unit
    , requestCopyDiagnostics: pure unit :: Effect Unit
    , requestReset: pure unit :: Effect Unit
    , requestSetKeepAwake: \_ -> pure unit :: Effect Unit
    }
  let
    applicationEnvironment :: ApplicationEnvironment
    applicationEnvironment = { sessionRef, wakeLockSentinelRef }

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
      , requestSetKeepAwake: \enabled ->
          readClickHandlers >>= \resolved ->
            runAppM applicationEnvironment (handleSetKeepAwake resolved enabled)
      }
  Ref.write handlers clickHandlersRef
  runAppM applicationEnvironment (startApplication handlers)
  onPageBecameVisible
    (runAppM applicationEnvironment (handleVisibilityVisible handlers))
  TestHook.install
    { dispatch: \action ->
        runAppM applicationEnvironment (dispatch handlers action)
    , readSession: Ref.read sessionRef
    , clock: runAppM applicationEnvironment currentTimeMillis
    , version
    , requestCopyDiagnostics: handlers.requestCopyDiagnostics
    , requestReset: handlers.requestReset
    , requestSetKeepAwake: handlers.requestSetKeepAwake
    , persistNow: runAppM applicationEnvironment persistCurrentSession
    , simulateVisibilityVisible:
        runAppM applicationEnvironment (handleVisibilityVisible handlers)
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
persistAfterAction (SetKeepAwake _) = pure unit
persistAfterAction (SetKeepAwakeStatus _) = pure unit
persistAfterAction (SetWakeLockHeld _) = pure unit

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

recordWakeLockEvent
  :: forall m. Clock m => SessionState m => String -> String -> m Unit
recordWakeLockEvent label detail = do
  timestamp <- currentTimeMillis
  updateSession (RecordDiagnostic timestamp label detail)

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
  => WakeLock m
  => ClickHandlers
  -> m Unit
handleToggle handlers = do
  timestamp <- currentTimeMillis
  dispatch handlers (Toggle timestamp)
  session <- readCurrentSession
  if session.listening then maybeAcquireWakeLock handlers
  else releaseHeldWakeLock handlers

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
  => WakeLock m
  => ClickHandlers
  -> m Unit
handleReset handlers = do
  outcome <- liftEffect (askForConfirmation resetConfirmationPrompt)
  case outcome of
    Right true -> do
      releaseHeldWakeLock handlers
      timestamp <- currentTimeMillis
      dispatch handlers (Reset timestamp)
    Right false -> pure unit
    Left confirmFailure -> recordConfirmFailure confirmFailure

handleSetKeepAwake
  :: forall m
   . Clock m
  => DomMount m
  => SessionState m
  => Storage m
  => WakeLock m
  => ClickHandlers
  -> Boolean
  -> m Unit
handleSetKeepAwake handlers enabled = do
  dispatch handlers (SetKeepAwake enabled)
  session <- readCurrentSession
  case enabled, session.listening of
    true, true -> maybeAcquireWakeLock handlers
    false, _ -> releaseHeldWakeLock handlers
    true, false -> pure unit

handleVisibilityVisible
  :: forall m
   . Clock m
  => DomMount m
  => SessionState m
  => Storage m
  => WakeLock m
  => ClickHandlers
  -> m Unit
handleVisibilityVisible handlers = do
  session <- readCurrentSession
  if session.listening && session.keepAwake && not session.wakeLockHeld
  then maybeAcquireWakeLock handlers
  else pure unit

maybeAcquireWakeLock
  :: forall m
   . Clock m
  => DomMount m
  => SessionState m
  => Storage m
  => WakeLock m
  => ClickHandlers
  -> m Unit
maybeAcquireWakeLock handlers = do
  session <- readCurrentSession
  if not session.keepAwake then pure unit
  else
    requestScreenWakeLock
      (onWakeLockAcquired handlers)
      (onWakeLockError handlers)
      (onWakeLockAutoReleased handlers)

releaseHeldWakeLock
  :: forall m
   . Clock m
  => DomMount m
  => SessionState m
  => Storage m
  => WakeLock m
  => ClickHandlers
  -> m Unit
releaseHeldWakeLock handlers = do
  session <- readCurrentSession
  if not session.wakeLockHeld then
    -- Nothing held: still reset any lingering UI status so a stale
    -- "screen will stay on" string does not outlive the listening
    -- session.
    dispatch handlers (SetKeepAwakeStatus idleKeepAwakeStatus)
  else
    releaseScreenWakeLock
      (onWakeLockReleased handlers)
      (onWakeLockReleaseError handlers)

onWakeLockReleased
  :: forall m
   . Clock m
  => DomMount m
  => SessionState m
  => Storage m
  => ClickHandlers
  -> m Unit
onWakeLockReleased handlers = do
  recordWakeLockEvent "wake lock release" "released"
  dispatch handlers (SetWakeLockHeld false)
  dispatch handlers (SetKeepAwakeStatus idleKeepAwakeStatus)

onWakeLockReleaseError
  :: forall m
   . Clock m
  => DomMount m
  => SessionState m
  => Storage m
  => ClickHandlers
  -> WakeLockError
  -> m Unit
onWakeLockReleaseError handlers failure = do
  let rendered = renderWakeLockError failure
  recordWakeLockEvent "wake lock release failure" rendered
  -- The browser's view of the lock is now indeterminate; reflect that
  -- in the UI by clearing both flags so the next listening edge will
  -- attempt a fresh acquisition.
  dispatch handlers (SetWakeLockHeld false)
  dispatch handlers (SetKeepAwakeStatus (renderKeepAwakeUnavailable rendered))

onWakeLockAcquired
  :: forall m
   . Clock m
  => DomMount m
  => SessionState m
  => Storage m
  => ClickHandlers
  -> m Unit
onWakeLockAcquired handlers = do
  recordWakeLockEvent "wake lock acquired" "screen held"
  dispatch handlers (SetWakeLockHeld true)
  dispatch handlers (SetKeepAwakeStatus wakeLockAcquiredStatus)

onWakeLockError
  :: forall m
   . Clock m
  => DomMount m
  => SessionState m
  => Storage m
  => ClickHandlers
  -> WakeLockError
  -> m Unit
onWakeLockError handlers failure = do
  let rendered = renderWakeLockError failure
  recordWakeLockEvent "wake lock failure" rendered
  dispatch handlers (SetWakeLockHeld false)
  dispatch handlers (SetKeepAwakeStatus (renderKeepAwakeUnavailable rendered))

onWakeLockAutoReleased
  :: forall m
   . Clock m
  => DomMount m
  => SessionState m
  => Storage m
  => ClickHandlers
  -> m Unit
onWakeLockAutoReleased handlers = do
  recordWakeLockEvent "wake lock auto-released" "page hidden"
  dispatch handlers (SetWakeLockHeld false)
