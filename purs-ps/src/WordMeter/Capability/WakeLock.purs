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

import Control.Monad.Reader.Trans (runReaderT)
import Control.Monad.State.Trans (StateT, modify_, runStateT)
import Data.Identity (Identity(..))
import Data.Tuple (Tuple(..))
import Effect.Class (liftEffect)
import Control.Monad.Reader.Class (ask)
import WordMeter.AppM (AppM(..))
import WordMeter.FFI.WakeLock (WakeLockError)
import WordMeter.FFI.WakeLock as FFI

-- | Continuation-passing capability so production code never blocks on
-- | the underlying browser promise. The three branches are mutually
-- | exclusive on the acquisition path (acquired XOR error), with
-- | `onAutoReleased` triggering later if and only if acquisition
-- | succeeded. This is the same shape as `Capability.Clipboard` and
-- | makes the production wiring trivial: each branch is a `dispatch`
-- | of an `Action`.
class Monad m <= WakeLock m where
  requestScreenWakeLock
    :: m Unit
    -> (WakeLockError -> m Unit)
    -> m Unit
    -> m Unit
  releaseScreenWakeLock :: m Unit

instance wakeLockAppM :: WakeLock AppM where
  requestScreenWakeLock (AppM onAcquired) onError (AppM onAutoReleased) =
    AppM do
      applicationEnvironment <- ask
      liftEffect
        ( FFI.requestScreenWakeLock
            (runReaderT onAcquired applicationEnvironment)
            ( \reason -> case onError reason of
                AppM continuation ->
                  runReaderT continuation applicationEnvironment
            )
            (runReaderT onAutoReleased applicationEnvironment)
        )
  releaseScreenWakeLock = AppM (liftEffect FFI.releaseScreenWakeLock)

-- | One entry recorded by `RecordingWakeLockM`: either a request (the
-- | success branch is taken synchronously, so the recording captures
-- | the fact that a request happened) or a release. The error and
-- | auto-release branches are exercised explicitly by the production
-- | flow rather than as part of the recording newtype's contract.
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
  releaseScreenWakeLock =
    RecordingWakeLockM (modify_ (\events -> events <> [ ReleasedWakeLock ]))

runRecordingWakeLockM
  :: forall a
   . RecordingWakeLockM a
  -> { result :: a, events :: WakeLockRecording }
runRecordingWakeLockM (RecordingWakeLockM stateful) =
  case runStateT stateful [] of
    Identity (Tuple result events) -> { result, events }
