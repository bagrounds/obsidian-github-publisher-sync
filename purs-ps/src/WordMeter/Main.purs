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
import WordMeter.Capability.DocumentPip
  ( class DocumentPip
  , closePipWindow
  , requestPipWindow
  , syncPipContent
  )
import WordMeter.Capability.Recognition
  ( class Recognition
  , RecognitionHandlers
  , cancelAutoRestart
  , onDeviceLanguagePackApiAvailable
  , prepareOnDeviceLanguagePack
  , recognitionApiAvailable
  , scheduleAutoRestart
  , startOnDeviceRecognition
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
import WordMeter.Capability.Ticker
  ( class Ticker
  , startTickerInterval
  , stopTickerInterval
  )
import WordMeter.Capability.WakeLock
  ( class WakeLock
  , releaseScreenWakeLock
  , requestScreenWakeLock
  )
import WordMeter.FFI.Confirm (ConfirmError, askForConfirmation, renderConfirmError)
import WordMeter.FFI.DocumentPip (DocumentPipError, renderDocumentPipError)
import WordMeter.FFI.Recognition
  ( OnDeviceAvailable
  , OnDeviceUnavailable
  , RecognitionConstructError
  , RecognitionStartError
  , RecognitionStopError
  , renderOnDeviceUnavailable
  , renderRecognitionConstructError
  , renderRecognitionStartError
  , renderRecognitionStopError
  )
import WordMeter.FFI.StorageError (StorageError, renderStorageError)
import WordMeter.FFI.Visibility (onPageBecameVisible)
import WordMeter.FFI.WakeLock (WakeLockError, renderWakeLockError)
import WordMeter.Locale (Locale(..), renderLocale)
import WordMeter.Recording.Reducer
  ( Action(..)
  , Handlers
  , toPersistedData
  )
import WordMeter.Recording.Session
  ( WakeLockState(..)
  , downloadingOnDeviceStatus
  , idleRecognitionStatusOverride
  , initialSession
  , resetConfirmationPrompt
  )
import WordMeter.Recording.View (diagnosticsText, renderStatus, view)
import WordMeter.RecognitionError
  ( RecognitionErrorCode(..)
  , classifyRecognitionError
  , renderRecognitionErrorDiagnosticDetail
  )
import WordMeter.Recognition.Path (RecognitionPath(..))
import WordMeter.TestHook as TestHook
import WordMeter.Vdom (ensureStylesheetLinked)
import WordMeter.Version (version)

hostElementId :: String
hostElementId = "word-meter"

stylesheetHref :: String
stylesheetHref = "/static/word-meter.css"

main :: Effect Unit
main = do
  ensureStylesheetLinked stylesheetHref
  sessionRef <- Ref.new initialSession
  wakeLockSentinelRef <- Ref.new Nothing
  recognitionInstanceRef <- Ref.new Nothing
  restartTimerRef <- Ref.new Nothing
  tickIntervalHandleRef <- Ref.new Nothing
  pipWindowRef <- Ref.new Nothing
  clickHandlersRef <- Ref.new
    { requestToggle: pure unit :: Effect Unit
    , requestCopyDiagnostics: pure unit :: Effect Unit
    , requestReset: pure unit :: Effect Unit
    , requestSetKeepAwake: \_ -> pure unit :: Effect Unit
    , requestToggleDiagnosticsDrawer: pure unit :: Effect Unit
    , requestTogglePip: pure unit :: Effect Unit
    }
  let
    applicationEnvironment :: ApplicationEnvironment
    applicationEnvironment =
      { sessionRef
      , wakeLockSentinelRef
      , recognitionInstanceRef
      , restartTimerRef
      , tickIntervalHandleRef
      , pipWindowRef
      }

    readHandlers :: Effect Handlers
    readHandlers = Ref.read clickHandlersRef

    handlers :: Handlers
    handlers =
      { requestToggle: readHandlers >>= \resolved ->
          runAppM applicationEnvironment (handleToggle resolved)
      , requestCopyDiagnostics: readHandlers >>= \resolved ->
          runAppM applicationEnvironment (handleCopyDiagnostics resolved)
      , requestReset: readHandlers >>= \resolved ->
          runAppM applicationEnvironment (handleReset resolved)
      , requestSetKeepAwake: \enabled ->
          readHandlers >>= \resolved ->
            runAppM applicationEnvironment (handleSetKeepAwake resolved enabled)
      , requestToggleDiagnosticsDrawer: readHandlers >>= \resolved ->
          runAppM applicationEnvironment (handleToggleDiagnosticsDrawer resolved)
      , requestTogglePip: readHandlers >>= \resolved ->
          runAppM applicationEnvironment (handleTogglePip resolved)
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
    , requestToggleDiagnosticsDrawer: handlers.requestToggleDiagnosticsDrawer
    , requestTogglePip: handlers.requestTogglePip
    }

startApplication
  :: forall m
   . Clock m
  => Environment m
  => DocumentPip m
  => DomMount m
  => SessionState m
  => Storage m
  => Handlers
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
  -- After restoring persisted state, immediately advance `now` to the
  -- real wall-clock timestamp. Without this, `now` stays at the epoch
  -- and `wallSpanMs`/`activeListeningMs` would clamp to ~0 ms,
  -- producing astronomically inflated rates until the next user-driven
  -- dispatch or live tick.
  updateSession (Tick initTimestamp)
  updateSession
    (RecordDiagnostic initTimestamp "init" ("version=" <> version))
  rerender handlers

dispatch
  :: forall m
   . Clock m
  => DocumentPip m
  => DomMount m
  => SessionState m
  => Storage m
  => Handlers
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
persistAfterAction action
  | shouldPersistSession action = persistCurrentSession
  | otherwise = case action of
      Reset _ -> do
        outcome <- clearPersistedSnapshot
        case outcome of
          Right _ -> pure unit
          Left storageFailure -> recordStorageFailure "persist clear" storageFailure
      _ -> pure unit

-- | Exhaustive predicate — every `Action` constructor must explicitly
-- | answer whether it should trigger a persistence write. The compiler
-- | enforces this: adding a new constructor without a case here is a
-- | type error. This must never use a wildcard catch-all.
shouldPersistSession :: Action -> Boolean
shouldPersistSession (Toggle _) = true
shouldPersistSession (InjectFinalTranscript _ _) = true
shouldPersistSession (IntegrateFinalizedTranscript _ _) = true
shouldPersistSession ResetRecognitionDedupState = false
shouldPersistSession (Reset _) = false
shouldPersistSession (Tick _) = false
shouldPersistSession (RecordDiagnostic _ _ _) = false
shouldPersistSession (SetEnvironment _) = false
shouldPersistSession (SetCopyStatus _) = false
shouldPersistSession (SetKeepAwake _) = false
shouldPersistSession (SetWakeLockState _) = false
shouldPersistSession (HandleRecognitionError _ _ _) = false
shouldPersistSession ClearErrorBanner = false
shouldPersistSession (SetRecognitionStatusOverride _) = false
shouldPersistSession (SetCloudFallbackAttempted _) = true
shouldPersistSession (SetActiveRecognitionPath _) = false
shouldPersistSession (SetDiagnosticsDrawerOpen _) = false
shouldPersistSession (SetPipOpen _) = false
shouldPersistSession (SetPipStatus _) = false
shouldPersistSession (LoadSession _) = false

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
   . DocumentPip m
  => DocumentPip m
  => DomMount m
  => SessionState m
  => Handlers
  -> m Unit
rerender handlers = do
  session <- readCurrentSession
  mountToHost hostElementId (view handlers session)
  -- Mirror the latest count + status into the PiP window whenever
  -- one is open. The capability layer no-ops when the window has
  -- already closed, so this is safe to call unconditionally.
  if session.pipOpen
  then syncPipContent
    { wordsToday: session.wordsToday
    , status: renderStatus session
    }
  else pure unit

handleToggle
  :: forall m
   . Clock m
  => DocumentPip m
  => DomMount m
  => SessionState m
  => Storage m
  => WakeLock m
  => Recognition m
  => Ticker m
  => Handlers
  -> m Unit
handleToggle handlers = do
  wasListening <- _.listening <$> readCurrentSession
  timestamp <- currentTimeMillis
  dispatch handlers (Toggle timestamp)
  session <- readCurrentSession
  if session.listening then do
    maybeAcquireWakeLock handlers
    startTickerInterval (handleTick handlers)
    if wasListening then pure unit
    else startRecognitionForSession handlers
  else do
    stopTickerInterval
    releaseHeldWakeLock handlers
    if not wasListening then pure unit
    else stopRecognitionForSession handlers

-- | Single tick of the live driver: re-dispatch a `Tick` action with
-- | the wall-clock now so rates/captions/trailing windows reflect
-- | reality, and re-render the host. Mirrors the legacy
-- | `handleTick` callback that `word-meter.js` runs every 200 ms while
-- | listening.
handleTick
  :: forall m
   . Clock m
  => DocumentPip m
  => DomMount m
  => SessionState m
  => Storage m
  => Handlers
  -> m Unit
handleTick handlers = do
  timestamp <- currentTimeMillis
  dispatch handlers (Tick timestamp)

handleCopyDiagnostics
  :: forall m
   . Clock m
  => Clipboard m
  => DocumentPip m
  => DomMount m
  => SessionState m
  => Storage m
  => Handlers
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
  => DocumentPip m
  => DomMount m
  => SessionState m
  => Storage m
  => WakeLock m
  => Recognition m
  => Ticker m
  => Handlers
  -> m Unit
handleReset handlers = do
  outcome <- liftEffect (askForConfirmation resetConfirmationPrompt)
  case outcome of
    Right true -> do
      stopTickerInterval
      stopRecognitionForSession handlers
      releaseHeldWakeLock handlers
      closePipWindow (onPipClosed handlers)
      timestamp <- currentTimeMillis
      dispatch handlers (Reset timestamp)
    Right false -> pure unit
    Left confirmFailure -> recordConfirmFailure confirmFailure

handleSetKeepAwake
  :: forall m
   . Clock m
  => DocumentPip m
  => DomMount m
  => SessionState m
  => Storage m
  => WakeLock m
  => Handlers
  -> Boolean
  -> m Unit
handleSetKeepAwake handlers enabled = do
  dispatch handlers (SetKeepAwake enabled)
  session <- readCurrentSession
  case enabled, session.listening of
    true, true -> maybeAcquireWakeLock handlers
    false, _ -> releaseHeldWakeLock handlers
    true, false -> pure unit

handleToggleDiagnosticsDrawer
  :: forall m
   . Clock m
  => DocumentPip m
  => DomMount m
  => SessionState m
  => Storage m
  => Handlers
  -> m Unit
handleToggleDiagnosticsDrawer handlers = do
  session <- readCurrentSession
  dispatch handlers (SetDiagnosticsDrawerOpen (not session.diagnosticsDrawerOpen))

handleTogglePip
  :: forall m
   . Clock m
  => DocumentPip m
  => DomMount m
  => SessionState m
  => Storage m
  => Handlers
  -> m Unit
handleTogglePip handlers = do
  session <- readCurrentSession
  if session.pipOpen
  then closePipWindow (onPipClosed handlers)
  else do
    dispatch handlers (SetPipStatus "")
    requestPipWindow
      (onPipOpened handlers)
      (onPipError handlers)
      (onPipClosedByUser handlers)

onPipOpened
  :: forall m
   . Clock m
  => DocumentPip m
  => DomMount m
  => SessionState m
  => Storage m
  => Handlers
  -> m Unit
onPipOpened handlers = do
  recordPipEvent "pop-out opened" ""
  dispatch handlers (SetPipOpen true)

onPipClosed
  :: forall m
   . Clock m
  => DocumentPip m
  => DomMount m
  => SessionState m
  => Storage m
  => Handlers
  -> m Unit
onPipClosed handlers = do
  recordPipEvent "pop-out closed" "via button"
  dispatch handlers (SetPipOpen false)

onPipClosedByUser
  :: forall m
   . Clock m
  => DocumentPip m
  => DomMount m
  => SessionState m
  => Storage m
  => Handlers
  -> m Unit
onPipClosedByUser handlers = do
  recordPipEvent "pop-out closed" "via window chrome"
  dispatch handlers (SetPipOpen false)

onPipError
  :: forall m
   . Clock m
  => DocumentPip m
  => DomMount m
  => SessionState m
  => Storage m
  => Handlers
  -> DocumentPipError
  -> m Unit
onPipError handlers failure = do
  let rendered = renderDocumentPipError failure
  recordPipEvent "pop-out failure" rendered
  dispatch handlers (SetPipStatus rendered)

recordPipEvent
  :: forall m. Clock m => SessionState m => String -> String -> m Unit
recordPipEvent label detail = do
  timestamp <- currentTimeMillis
  updateSession (RecordDiagnostic timestamp label detail)

handleVisibilityVisible
  :: forall m
   . Clock m
  => DocumentPip m
  => DomMount m
  => SessionState m
  => Storage m
  => WakeLock m
  => Handlers
  -> m Unit
handleVisibilityVisible handlers = do
  session <- readCurrentSession
  if session.listening && session.keepAwake && session.wakeLockState /= WakeLockHeld
  then maybeAcquireWakeLock handlers
  else pure unit

handleRecognitionError
  :: forall m
   . Clock m
  => DocumentPip m
  => DomMount m
  => SessionState m
  => Storage m
  => WakeLock m
  => Recognition m
  => Ticker m
  => Handlers
  -> String
  -> String
  -> m Unit
handleRecognitionError handlers code message = do
  beforeSession <- readCurrentSession
  let
    wasListening = beforeSession.listening
    priorPath = beforeSession.activeRecognitionPath
    priorFallbackAttempted = beforeSession.cloudFallbackAttempted
    classified = classifyRecognitionError code
    shouldRetryOnCloud =
      classified == LanguageNotSupported
        && wasListening
        && priorPath == Just OnDevicePath
        && not priorFallbackAttempted
  if shouldRetryOnCloud then
    swapOnDeviceForCloud handlers code message
  else do
    timestamp <- currentTimeMillis
    dispatch handlers (HandleRecognitionError timestamp code message)
    -- If the error caused us to stop listening (today: the permission-denied
    -- branch), tear down recognition and let go of any wake lock so the UI
    -- does not look like it is still holding the screen. Also cancel the
    -- live tick driver so we stop re-rendering once we are idle.
    stillListening <- _.listening <$> readCurrentSession
    if wasListening && not stillListening then do
      stopTickerInterval
      stopRecognitionForSession handlers
      releaseHeldWakeLock handlers
    else pure unit

-- | A runtime `language-not-supported` against the on-device path is
-- | one of the few error codes that can leak past the on-device
-- | pre-flight on some Chromium builds. Rather than surface the
-- | language-unavailable banner, the orchestrator swallows the error,
-- | tears down the on-device recognizer, and starts a fresh cloud-path
-- | recognition. The retry is one-shot per session: `cloudFallbackAttempted`
-- | guards a second attempt so a misbehaving browser cannot loop. The
-- | flag is cleared on every Toggle-to-start.
swapOnDeviceForCloud
  :: forall m
   . Clock m
  => DocumentPip m
  => DomMount m
  => SessionState m
  => Storage m
  => WakeLock m
  => Recognition m
  => Ticker m
  => Handlers
  -> String
  -> String
  -> m Unit
swapOnDeviceForCloud handlers code message = do
  -- Record the same `recognition.onerror` diagnostic the reducer would
  -- have appended, so bug reports across both builds stay byte-comparable.
  errorTimestamp <- currentTimeMillis
  updateSession
    ( RecordDiagnostic errorTimestamp "recognition.onerror"
        (renderRecognitionErrorDiagnosticDetail code message)
    )
  locale <- sessionLocale
  fallbackTimestamp <- currentTimeMillis
  updateSession
    ( RecordDiagnostic fallbackTimestamp
        "language-not-supported at runtime — falling back to cloud"
        ("locale=" <> renderLocale locale)
    )
  dispatch handlers (SetCloudFallbackAttempted true)
  stopRecognitionForSession handlers
  dispatch handlers (SetActiveRecognitionPath (Just CloudPath))
  startRecognition (recognitionHandlersFor handlers locale)

maybeAcquireWakeLock
  :: forall m
   . Clock m
  => DocumentPip m
  => DomMount m
  => SessionState m
  => Storage m
  => WakeLock m
  => Handlers
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
  => DocumentPip m
  => DomMount m
  => SessionState m
  => Storage m
  => WakeLock m
  => Handlers
  -> m Unit
releaseHeldWakeLock handlers = do
  session <- readCurrentSession
  case session.wakeLockState of
    WakeLockHeld ->
      releaseScreenWakeLock
        (onWakeLockReleased handlers)
        (onWakeLockReleaseError handlers)
    _ ->
      -- Nothing held: reset any lingering state so a stale status
      -- string does not outlive the listening session.
      dispatch handlers (SetWakeLockState WakeLockIdle)

onWakeLockReleased
  :: forall m
   . Clock m
  => DocumentPip m
  => DomMount m
  => SessionState m
  => Storage m
  => Handlers
  -> m Unit
onWakeLockReleased handlers = do
  recordWakeLockEvent "wake lock release" "released"
  dispatch handlers (SetWakeLockState WakeLockIdle)

onWakeLockReleaseError
  :: forall m
   . Clock m
  => DocumentPip m
  => DomMount m
  => SessionState m
  => Storage m
  => Handlers
  -> WakeLockError
  -> m Unit
onWakeLockReleaseError handlers failure = do
  let rendered = renderWakeLockError failure
  recordWakeLockEvent "wake lock release failure" rendered
  -- The browser's view of the lock is now indeterminate; reflect that
  -- in the UI so the next listening edge will attempt a fresh acquisition.
  dispatch handlers (SetWakeLockState (WakeLockFailed rendered))

onWakeLockAcquired
  :: forall m
   . Clock m
  => DocumentPip m
  => DomMount m
  => SessionState m
  => Storage m
  => Handlers
  -> m Unit
onWakeLockAcquired handlers = do
  recordWakeLockEvent "wake lock acquired" "screen held"
  dispatch handlers (SetWakeLockState WakeLockHeld)

onWakeLockError
  :: forall m
   . Clock m
  => DocumentPip m
  => DomMount m
  => SessionState m
  => Storage m
  => Handlers
  -> WakeLockError
  -> m Unit
onWakeLockError handlers failure = do
  let rendered = renderWakeLockError failure
  recordWakeLockEvent "wake lock failure" rendered
  dispatch handlers (SetWakeLockState (WakeLockFailed rendered))

onWakeLockAutoReleased
  :: forall m
   . Clock m
  => DocumentPip m
  => DomMount m
  => SessionState m
  => Storage m
  => Handlers
  -> m Unit
onWakeLockAutoReleased handlers = do
  recordWakeLockEvent "wake lock auto-released" "page hidden"
  dispatch handlers (SetWakeLockState WakeLockIdle)


defaultLocale :: Locale
defaultLocale = Locale "en-US"

sessionLocale :: forall m. SessionState m => m Locale
sessionLocale = do
  session <- readCurrentSession
  case session.environment of
    Just snapshot
      | snapshot.navigatorLanguage /= ""
        && snapshot.navigatorLanguage /= "(unknown)" ->
          pure (Locale snapshot.navigatorLanguage)
    _ -> pure defaultLocale

startRecognitionForSession
  :: forall m
   . Clock m
  => DocumentPip m
  => DomMount m
  => SessionState m
  => Storage m
  => WakeLock m
  => Recognition m
  => Ticker m
  => Handlers
  -> m Unit
startRecognitionForSession handlers = do
  available <- recognitionApiAvailable
  if not available then do
    recordRecognitionEvent "recognition unavailable"
      "no SpeechRecognition constructor"
  else do
    locale <- sessionLocale
    -- Issue #N: only attempt the on-device pre-flight once per
    -- "session" (i.e. until the next user-driven Reset). Once we have
    -- settled on the cloud path — whether because the static API is
    -- absent, the pre-flight returned `Left`, or a runtime
    -- LanguageNotSupported swap fired — every subsequent
    -- start/auto-restart skips the pre-flight and goes straight to the
    -- cloud recognizer. Without this gate the on-device path is
    -- retried on every onend auto-restart even though we already know
    -- it is not viable on this device.
    session <- readCurrentSession
    if session.cloudFallbackAttempted then do
      recordRecognitionEvent
        "skipping on-device pre-flight — cloud already selected"
        ("locale=" <> renderLocale locale)
      dispatch handlers (SetActiveRecognitionPath (Just CloudPath))
      startRecognition (recognitionHandlersFor handlers locale)
    else do
      onDeviceApi <- onDeviceLanguagePackApiAvailable
      if not onDeviceApi then do
        recordRecognitionEvent
          "on-device API absent — falling back to cloud"
          ("locale=" <> renderLocale locale)
        dispatch handlers (SetCloudFallbackAttempted true)
        dispatch handlers (SetActiveRecognitionPath (Just CloudPath))
        startRecognition (recognitionHandlersFor handlers locale)
      else
        prepareOnDeviceLanguagePack
          { locale
          , onProgress: onOnDeviceInstallStarted handlers locale
          }
          (onOnDevicePreflightResolved handlers locale)

onOnDeviceInstallStarted
  :: forall m
   . Clock m
  => DocumentPip m
  => DomMount m
  => SessionState m
  => Storage m
  => Handlers
  -> Locale
  -> m Unit
onOnDeviceInstallStarted handlers locale = do
  recordRecognitionEvent
    "on-device language pack download started"
    ("locale=" <> renderLocale locale)
  -- Only show the download status while we are still listening — if
  -- the user has hit Stop between the `available()` resolution and
  -- the `install()` call, the override would otherwise stick around
  -- on an idle session.
  session <- readCurrentSession
  if session.listening
  then dispatch handlers (SetRecognitionStatusOverride downloadingOnDeviceStatus)
  else pure unit

onOnDevicePreflightResolved
  :: forall m
   . Clock m
  => DocumentPip m
  => DomMount m
  => SessionState m
  => Storage m
  => WakeLock m
  => Recognition m
  => Ticker m
  => Handlers
  -> Locale
  -> Either OnDeviceUnavailable OnDeviceAvailable
  -> m Unit
onOnDevicePreflightResolved handlers locale outcome = do
  -- The user may have hit Stop while the static API was resolving;
  -- in that case the session is no longer listening and we must not
  -- start a fresh recognizer. The dedicated status override is also
  -- cleared so a stale "downloading…" string cannot outlive the
  -- listening session.
  dispatch handlers
    (SetRecognitionStatusOverride idleRecognitionStatusOverride)
  session <- readCurrentSession
  if not session.listening then pure unit
  else case outcome of
    Right _onDeviceAvailable -> do
      recordRecognitionEvent
        "on-device pre-flight viable — starting on-device"
        ("locale=" <> renderLocale locale)
      dispatch handlers (SetActiveRecognitionPath (Just OnDevicePath))
      startOnDeviceRecognition (recognitionHandlersFor handlers locale)
    Left reason -> do
      recordRecognitionEvent
        "on-device pre-flight non-viable — falling back to cloud"
        (renderOnDeviceUnavailable reason)
      dispatch handlers (SetCloudFallbackAttempted true)
      dispatch handlers (SetActiveRecognitionPath (Just CloudPath))
      startRecognition (recognitionHandlersFor handlers locale)

stopRecognitionForSession
  :: forall m
   . Clock m
  => DocumentPip m
  => DomMount m
  => SessionState m
  => Storage m
  => Recognition m
  => Handlers
  -> m Unit
stopRecognitionForSession handlers = do
  cancelAutoRestart
  dispatch handlers (SetActiveRecognitionPath Nothing)
  stopRecognition
    (recordRecognitionEvent "recognition stopped" "")
    onRecognitionStopFailure

recognitionHandlersFor
  :: forall m
   . Clock m
  => DocumentPip m
  => DomMount m
  => SessionState m
  => Storage m
  => WakeLock m
  => Recognition m
  => Ticker m
  => Handlers
  -> Locale
  -> RecognitionHandlers m
recognitionHandlersFor handlers locale =
  { locale
  , onResult: \transcript timestamp ->
      dispatch handlers (IntegrateFinalizedTranscript timestamp transcript)
  , onErrorEvent: handleRecognitionError handlers
  , onEnded: handleRecognitionEnded handlers
  , onStarted: recordRecognitionEvent "recognition started"
      ("locale=" <> renderLocale locale)
  , onStartFailure: onRecognitionStartFailure
  , onConstructFailure: onRecognitionConstructFailure
  }

handleRecognitionEnded
  :: forall m
   . Clock m
  => DocumentPip m
  => DomMount m
  => SessionState m
  => Storage m
  => WakeLock m
  => Recognition m
  => Ticker m
  => Handlers
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
  => DocumentPip m
  => DomMount m
  => SessionState m
  => Storage m
  => WakeLock m
  => Recognition m
  => Ticker m
  => Handlers
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
