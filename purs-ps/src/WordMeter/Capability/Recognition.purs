-- | Capability for the slice-9a real recognition wiring. Production
-- | code in `WordMeter.Main` uses the typeclass; the `AppM` instance
-- | owns the active `RecognitionInstance` and the auto-restart timer
-- | handle through refs in `ApplicationEnvironment`. The
-- | `RecordingRecognitionM` test newtype records every call so the
-- | reducer wiring is unit-testable without touching the browser.
module WordMeter.Capability.Recognition
  ( class Recognition
  , recognitionApiAvailable
  , startRecognition
  , stopRecognition
  , cancelAutoRestart
  , scheduleAutoRestart
  , RecognitionHandlers
  , RecognitionEvent(..)
  , RecordingRecognitionM(..)
  , RecognitionRecording
  , runRecordingRecognitionM
  , restartDelayMilliseconds
  ) where

import Prelude

import Control.Monad.Reader.Class (ask)
import Control.Monad.State.Trans (StateT, modify_, runStateT)
import Data.Identity (Identity(..))
import Data.Maybe (Maybe(..))
import Data.Tuple (Tuple(..))
import Effect (Effect)
import Effect.Class (liftEffect)
import Effect.Ref as Ref
import WordMeter.AppM (AppM(..), ApplicationEnvironment, runAppM)
import WordMeter.FFI.Recognition
  ( RecognitionConstructError(..)
  , RecognitionStartError(..)
  , RecognitionStopError(..)
  )
import WordMeter.FFI.Recognition as FFI
import WordMeter.FFI.Timer as Timer

-- | Legacy `RESTART_DELAY_MILLISECONDS`: how long the program waits
-- | after `onend` before re-issuing `recognition.start()` to keep the
-- | ambient capture going.
restartDelayMilliseconds :: Int
restartDelayMilliseconds = 250

-- | Callbacks the orchestrator hands the capability when it starts a
-- | recognition. Every fallible boundary is wired up: synchronous
-- | construct / start failures, asynchronous `recognition.onerror`
-- | events, and a clean `onEnded` for the auto-restart logic.
type RecognitionHandlers m =
  { locale :: String
  , onResult :: String -> Number -> m Unit
  , onErrorEvent :: String -> String -> m Unit
  , onEnded :: m Unit
  , onStarted :: m Unit
  , onStartFailure :: RecognitionStartError -> m Unit
  , onConstructFailure :: RecognitionConstructError -> m Unit
  }

class Monad m <= Recognition m where
  recognitionApiAvailable :: m Boolean
  startRecognition :: RecognitionHandlers m -> m Unit
  stopRecognition :: m Unit -> (RecognitionStopError -> m Unit) -> m Unit
  scheduleAutoRestart :: m Unit -> m Unit
  cancelAutoRestart :: m Unit

instance recognitionAppM :: Recognition AppM where
  recognitionApiAvailable =
    AppM (liftEffect FFI.recognitionApiAvailable)
  startRecognition handlers =
    AppM do
      environment <- ask
      liftEffect (startRecognitionInEnvironment environment handlers)
  stopRecognition onStopped onError =
    AppM do
      environment <- ask
      liftEffect (stopRecognitionInEnvironment environment onStopped onError)
  scheduleAutoRestart action =
    AppM do
      environment <- ask
      liftEffect (scheduleAutoRestartInEnvironment environment action)
  cancelAutoRestart =
    AppM do
      environment <- ask
      liftEffect (cancelAutoRestartInEnvironment environment)

-- | Construct an instance, install the three handlers, stash it in
-- | the env ref, and call `start()`. Every failure mode surfaces
-- | through its dedicated continuation: synchronous construct
-- | failure, synchronous start failure, and asynchronous
-- | `recognition.onerror` events.
startRecognitionInEnvironment
  :: ApplicationEnvironment
  -> RecognitionHandlers AppM
  -> Effect Unit
startRecognitionInEnvironment environment handlers =
  let
    runHere :: forall a. AppM a -> Effect a
    runHere act = runAppM environment act
  in
    FFI.constructRecognitionInstance handlers.locale
      ( \instance_ -> do
          FFI.attachOnResult instance_
            (\transcript timestamp ->
              runHere (handlers.onResult transcript timestamp))
          FFI.attachOnError instance_
            (\code message ->
              runHere (handlers.onErrorEvent code message))
          FFI.attachOnEnd instance_ (runHere handlers.onEnded)
          Ref.write (Just instance_) environment.recognitionInstanceRef
          FFI.startRecognitionInstance instance_
            (runHere handlers.onStarted)
            ( \detail ->
                runHere
                  (handlers.onStartFailure (RecognitionStartError detail))
            )
      )
      ( \detail ->
          runHere
            (handlers.onConstructFailure (RecognitionConstructError detail))
      )

-- | Detach handlers, call `stop()`, and clear the ref. Invokes
-- | exactly one of the two continuations: the success callback when
-- | `stop()` returns (or when no instance is held), the error
-- | callback when the browser throws. With nothing held the call is
-- | a successful no-op so the orchestrator can stop unconditionally.
stopRecognitionInEnvironment
  :: ApplicationEnvironment
  -> AppM Unit
  -> (RecognitionStopError -> AppM Unit)
  -> Effect Unit
stopRecognitionInEnvironment environment onStopped onError =
  let
    runHere :: forall a. AppM a -> Effect a
    runHere act = runAppM environment act
  in
    do
      heldInstance <- Ref.read environment.recognitionInstanceRef
      case heldInstance of
        Nothing -> runHere onStopped
        Just instance_ -> do
          FFI.detachHandlers instance_
          Ref.write Nothing environment.recognitionInstanceRef
          FFI.stopRecognitionInstance instance_
            (runHere onStopped)
            ( \detail ->
                runHere (onError (RecognitionStopError detail))
            )

scheduleAutoRestartInEnvironment
  :: ApplicationEnvironment -> AppM Unit -> Effect Unit
scheduleAutoRestartInEnvironment environment action = do
  -- Cancel any pending fire first so back-to-back `onend` events
  -- cannot stack restart timers on top of each other.
  cancelHeldTimer environment
  handle <- Timer.scheduleAfter restartDelayMilliseconds do
    Ref.write Nothing environment.restartTimerRef
    runAppM environment action
  Ref.write (Just handle) environment.restartTimerRef

cancelAutoRestartInEnvironment :: ApplicationEnvironment -> Effect Unit
cancelAutoRestartInEnvironment = cancelHeldTimer

cancelHeldTimer :: ApplicationEnvironment -> Effect Unit
cancelHeldTimer environment = do
  heldTimer <- Ref.read environment.restartTimerRef
  case heldTimer of
    Nothing -> pure unit
    Just handle -> do
      Ref.write Nothing environment.restartTimerRef
      Timer.cancelScheduled handle

-- | One entry recorded by `RecordingRecognitionM`. Mirrors the call
-- | surface of the capability so unit tests can assert that the
-- | orchestrator asked for / let go of recognition at the right
-- | times.
data RecognitionEvent
  = StartedRecognition { locale :: String }
  | StoppedRecognition
  | ScheduledAutoRestart
  | CancelledAutoRestart

derive instance eqRecognitionEvent :: Eq RecognitionEvent

instance showRecognitionEvent :: Show RecognitionEvent where
  show (StartedRecognition fields) =
    "StartedRecognition " <> show fields.locale
  show StoppedRecognition = "StoppedRecognition"
  show ScheduledAutoRestart = "ScheduledAutoRestart"
  show CancelledAutoRestart = "CancelledAutoRestart"

type RecognitionRecording = Array RecognitionEvent

newtype RecordingRecognitionM a =
  RecordingRecognitionM (StateT RecognitionRecording Identity a)

derive newtype instance functorRecordingRecognitionM ::
  Functor RecordingRecognitionM
derive newtype instance applyRecordingRecognitionM ::
  Apply RecordingRecognitionM
derive newtype instance applicativeRecordingRecognitionM ::
  Applicative RecordingRecognitionM
derive newtype instance bindRecordingRecognitionM ::
  Bind RecordingRecognitionM
derive newtype instance monadRecordingRecognitionM ::
  Monad RecordingRecognitionM

instance recognitionRecordingRecognitionM :: Recognition RecordingRecognitionM where
  recognitionApiAvailable = pure true
  startRecognition handlers = do
    RecordingRecognitionM
      (modify_ (\events -> events <> [ StartedRecognition { locale: handlers.locale } ]))
    handlers.onStarted
  stopRecognition onStopped _onError = do
    RecordingRecognitionM
      (modify_ (\events -> events <> [ StoppedRecognition ]))
    onStopped
  scheduleAutoRestart _action =
    RecordingRecognitionM
      (modify_ (\events -> events <> [ ScheduledAutoRestart ]))
  cancelAutoRestart =
    RecordingRecognitionM
      (modify_ (\events -> events <> [ CancelledAutoRestart ]))

runRecordingRecognitionM
  :: forall a
   . RecordingRecognitionM a
  -> { result :: a, events :: RecognitionRecording }
runRecordingRecognitionM (RecordingRecognitionM stateful) =
  case runStateT stateful [] of
    Identity (Tuple result events) -> { result, events }
