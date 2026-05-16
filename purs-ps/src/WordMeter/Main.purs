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
import WordMeter.Capability.Recognition
  ( class Recognition
  , RecognitionHandlers
  , cancelAutoRestart
  , recognitionApiAvailable
  , scheduleAutoRestart
  , startRecognition
  , stopRecognition
  )
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
import WordMeter.FFI.Recognition
  ( RecognitionConstructError
  , RecognitionStartError
  , RecognitionStopError
  , renderRecognitionConstructError
  , renderRecognitionStartError
  , renderRecognitionStopError
  )
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
  recognitionInstanceRef <- Ref.new Nothing
  restartTimerRef <- Ref.new Nothing
  clickHandlersRef <- Ref.new
    { requestToggle: pure unit :: Effect Unit
    , requestCopyDiagnostics: pure unit :: Effect Unit
    , requestReset: pure unit :: Effect Unit
    , requestSetKeepAwake: \_ -> pure unit :: Effect Unit
    }
  let
    applicationEnvironment :: ApplicationEnvironment
    applicationEnvironment =
      { sessionRef
      , wakeLockSentinelRef
      , recognitionInstanceRef
      , restartTimerRef
      }

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
    , simulateRecognitionError: \code message ->
        runAppM applicationEnvironment
          (handleRecognitionError handlers code message)
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
persistAfterAction (IntegrateFinalizedTranscript _ _) = persistCurrentSession
persistAfterAction ResetRecognitionDedupState = pure unit
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
persistAfterAction (HandleRecognitionError _ _ _) = pure unit
persistAfterAction ClearErrorBanner = pure unit

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
  => Recognition m
  => ClickHandlers
  -> m Unit
handleToggle handlers = do
  wasListening <- _.listening <$> readCurrentSession
  timestamp <- currentTimeMillis
  dispatch handlers (Toggle timestamp)
  session <- readCurrentSession
  if session.listening then do
    maybeAcquireWakeLock handlers
    if wasListening then pure unit
    else startRecognitionForSession handlers
  else do
    releaseHeldWakeLock handlers
    if not wasListening then pure unit
    else stopRecognitionForSession handlers

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
  => Recognition m
  => ClickHandlers
  -> m Unit
handleReset handlers = do
  outcome <- liftEffect (askForConfirmation resetConfirmationPrompt)
  case outcome of
    Right true -> do
      stopRecognitionForSession handlers
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

handleRecognitionError
  :: forall m
   . Clock m
  => DomMount m
  => SessionState m
  => Storage m
  => WakeLock m
  => Recognition m
  => ClickHandlers
  -> String
  -> String
  -> m Unit
handleRecognitionError handlers code message = do
  wasListening <- _.listening <$> readCurrentSession
  timestamp <- currentTimeMillis
  dispatch handlers (HandleRecognitionError timestamp code message)
  -- If the error caused us to stop listening (today: the permission-denied
  -- branch), tear down recognition and let go of any wake lock so the UI
  -- does not look like it is still holding the screen.
  stillListening <- _.listening <$> readCurrentSession
  if wasListening && not stillListening then do
    stopRecognitionForSession handlers
    releaseHeldWakeLock handlers
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

-- ───────── Recognition orchestration (slice 9a) ─────────

defaultLocale :: String
defaultLocale = "en-US"

sessionLocale :: forall m. SessionState m => m String
sessionLocale = do
  session <- readCurrentSession
  case session.environment of
    Just snapshot
      | snapshot.navigatorLanguage /= ""
        && snapshot.navigatorLanguage /= "(unknown)" ->
          pure snapshot.navigatorLanguage
    _ -> pure defaultLocale

startRecognitionForSession
  :: forall m
   . Clock m
  => DomMount m
  => SessionState m
  => Storage m
  => WakeLock m
  => Recognition m
  => ClickHandlers
  -> m Unit
startRecognitionForSession handlers = do
  available <- recognitionApiAvailable
  if not available then do
    recordRecognitionEvent "recognition unavailable"
      "no SpeechRecognition constructor"
  else do
    locale <- sessionLocale
    startRecognition (recognitionHandlersFor handlers locale)

stopRecognitionForSession
  :: forall m
   . Clock m
  => SessionState m
  => Recognition m
  => ClickHandlers
  -> m Unit
stopRecognitionForSession _handlers = do
  cancelAutoRestart
  stopRecognition
    (recordRecognitionEvent "recognition stopped" "")
    onRecognitionStopFailure

recognitionHandlersFor
  :: forall m
   . Clock m
  => DomMount m
  => SessionState m
  => Storage m
  => WakeLock m
  => Recognition m
  => ClickHandlers
  -> String
  -> RecognitionHandlers m
recognitionHandlersFor handlers locale =
  { locale
  , onResult: \transcript timestamp ->
      dispatch handlers (IntegrateFinalizedTranscript timestamp transcript)
  , onErrorEvent: handleRecognitionError handlers
  , onEnded: handleRecognitionEnded handlers
  , onStarted: recordRecognitionEvent "recognition started"
      ("locale=" <> locale)
  , onStartFailure: onRecognitionStartFailure
  , onConstructFailure: onRecognitionConstructFailure
  }

handleRecognitionEnded
  :: forall m
   . Clock m
  => DomMount m
  => SessionState m
  => Storage m
  => WakeLock m
  => Recognition m
  => ClickHandlers
  -> m Unit
handleRecognitionEnded handlers = do
  -- After every onend, reset the per-recognition-run dedup state so the
  -- user's next utterance after silence is treated as a brand new
  -- utterance rather than a refinement of whatever was last said.
  dispatch handlers ResetRecognitionDedupState
  session <- readCurrentSession
  if not session.listening then
    -- We explicitly stopped (or the reducer flipped listening off);
    -- nothing more to do.
    pure unit
  else do
    recordRecognitionEvent "recognition restart scheduled"
      ("delay=" <> show 250 <> "ms")
    scheduleAutoRestart (fireScheduledRestart handlers)

fireScheduledRestart
  :: forall m
   . Clock m
  => DomMount m
  => SessionState m
  => Storage m
  => WakeLock m
  => Recognition m
  => ClickHandlers
  -> m Unit
fireScheduledRestart handlers = do
  session <- readCurrentSession
  if not session.listening then
    -- The user stopped listening before the timer fired; do not
    -- resurrect the recognizer.
    pure unit
  else do
    recordRecognitionEvent "recognition restart fired" ""
    startRecognitionForSession handlers

onRecognitionStartFailure
  :: forall m
   . Clock m
  => SessionState m
  => RecognitionStartError
  -> m Unit
onRecognitionStartFailure failure =
  recordRecognitionEvent "recognition start failure"
    (renderRecognitionStartError failure)

onRecognitionStopFailure
  :: forall m
   . Clock m
  => SessionState m
  => RecognitionStopError
  -> m Unit
onRecognitionStopFailure failure =
  recordRecognitionEvent "recognition stop failure"
    (renderRecognitionStopError failure)

onRecognitionConstructFailure
  :: forall m
   . Clock m
  => SessionState m
  => RecognitionConstructError
  -> m Unit
onRecognitionConstructFailure failure =
  recordRecognitionEvent "recognition construct failure"
    (renderRecognitionConstructError failure)

recordRecognitionEvent
  :: forall m. Clock m => SessionState m => String -> String -> m Unit
recordRecognitionEvent label detail = do
  timestamp <- currentTimeMillis
  updateSession (RecordDiagnostic timestamp label detail)
