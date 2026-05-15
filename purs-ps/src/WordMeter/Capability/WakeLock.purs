module WordMeter.Capability.WakeLock
  ( class WakeLock
  , requestScreenWakeLock
  , releaseScreenWakeLock
  , WakeLockEvent(..)
  , RecordingWakeLockM(..)
  , WakeLockRecording
  , runRecordingWakeLockM
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
import WordMeter.FFI.WakeLock (WakeLockError(..), WakeLockSentinel)
import WordMeter.FFI.WakeLock as FFI

-- | Continuation-passing capability so production code never blocks on
-- | the underlying browser promises. Both methods surface every
-- | failure mode through a typed `WakeLockError` continuation: the
-- | "never silently swallow errors" rule applies to release just as
-- | it applies to acquisition.
class Monad m <= WakeLock m where
  requestScreenWakeLock
    :: m Unit                            -- onAcquired
    -> (WakeLockError -> m Unit)         -- onError
    -> m Unit                            -- onAutoReleased
    -> m Unit
  releaseScreenWakeLock
    :: m Unit                            -- onReleased
    -> (WakeLockError -> m Unit)         -- onError
    -> m Unit

instance wakeLockAppM :: WakeLock AppM where
  requestScreenWakeLock onAcquired onError onAutoReleased =
    AppM do
      environment <- ask
      liftEffect (requestSentinel environment onAcquired onError onAutoReleased)
  releaseScreenWakeLock onReleased onError =
    AppM do
      environment <- ask
      liftEffect (releaseHeldSentinel environment onReleased onError)

-- | Acquire a sentinel and install the browser's release listener. If
-- | the browser-initiated release fires while we still consider the
-- | sentinel held, surface it as `onAutoReleased`; if the program has
-- | already cleared the ref through `releaseHeldSentinel`, the same
-- | event is a no-op because we accounted for the release on the
-- | explicit path.
requestSentinel
  :: ApplicationEnvironment
  -> AppM Unit
  -> (WakeLockError -> AppM Unit)
  -> AppM Unit
  -> Effect Unit
requestSentinel environment onAcquired onError onAutoReleased = do
  let runHere :: forall a. AppM a -> Effect a
      runHere act = runAppM environment act
  available <- FFI.wakeLockApiAvailable
  if not available then runHere (onError WakeLockUnsupported)
  else FFI.requestScreenWakeLock
    ( \sentinel -> do
        Ref.write (Just sentinel) environment.wakeLockSentinelRef
        FFI.attachSentinelReleaseListener sentinel
          (handleSentinelRelease environment sentinel onAutoReleased)
        runHere onAcquired
    )
    (\reason -> runHere (onError (WakeLockUnavailable reason)))

handleSentinelRelease
  :: ApplicationEnvironment
  -> WakeLockSentinel
  -> AppM Unit
  -> Effect Unit
handleSentinelRelease environment sentinel onAutoReleased = do
  currentlyHeld <- Ref.read environment.wakeLockSentinelRef
  case currentlyHeld of
    Just held | FFI.sentinelsEqual held sentinel -> do
      Ref.write Nothing environment.wakeLockSentinelRef
      runAppM environment onAutoReleased
    _ -> pure unit

-- | Release whatever sentinel the program currently holds. With nothing
-- | held the call is a successful no-op (so callers can release
-- | unconditionally on stop / reset without first checking). With a
-- | sentinel held, the ref is cleared first so the browser's release
-- | event — which fires for both explicit and auto release — is
-- | correctly identified as our explicit release and ignored.
releaseHeldSentinel
  :: ApplicationEnvironment
  -> AppM Unit
  -> (WakeLockError -> AppM Unit)
  -> Effect Unit
releaseHeldSentinel environment onReleased onError = do
  let runHere :: forall a. AppM a -> Effect a
      runHere act = runAppM environment act
  heldSentinel <- Ref.read environment.wakeLockSentinelRef
  case heldSentinel of
    Nothing -> runHere onReleased
    Just sentinel -> do
      Ref.write Nothing environment.wakeLockSentinelRef
      FFI.releaseSentinel sentinel
        (runHere onReleased)
        (\reason -> runHere (onError (WakeLockUnavailable reason)))

-- | One entry recorded by `RecordingWakeLockM`: every request and
-- | release call is logged in order so tests can assert that the
-- | reducer wiring asked for / let go of the lock at the right times.
data WakeLockEvent
  = RequestedWakeLock
  | ReleasedWakeLock

derive instance eqWakeLockEvent :: Eq WakeLockEvent

instance showWakeLockEvent :: Show WakeLockEvent where
  show RequestedWakeLock = "RequestedWakeLock"
  show ReleasedWakeLock = "ReleasedWakeLock"

type WakeLockRecording = Array WakeLockEvent

newtype RecordingWakeLockM a =
  RecordingWakeLockM (StateT WakeLockRecording Identity a)

derive newtype instance functorRecordingWakeLockM :: Functor RecordingWakeLockM
derive newtype instance applyRecordingWakeLockM :: Apply RecordingWakeLockM
derive newtype instance applicativeRecordingWakeLockM :: Applicative RecordingWakeLockM
derive newtype instance bindRecordingWakeLockM :: Bind RecordingWakeLockM
derive newtype instance monadRecordingWakeLockM :: Monad RecordingWakeLockM

instance wakeLockRecordingWakeLockM :: WakeLock RecordingWakeLockM where
  requestScreenWakeLock onAcquired _onError _onAutoReleased = do
    RecordingWakeLockM (modify_ (\events -> events <> [ RequestedWakeLock ]))
    onAcquired
  releaseScreenWakeLock onReleased _onError = do
    RecordingWakeLockM (modify_ (\events -> events <> [ ReleasedWakeLock ]))
    onReleased

runRecordingWakeLockM
  :: forall a
   . RecordingWakeLockM a
  -> { result :: a, events :: WakeLockRecording }
runRecordingWakeLockM (RecordingWakeLockM stateful) =
  case runStateT stateful [] of
    Identity (Tuple result events) -> { result, events }
