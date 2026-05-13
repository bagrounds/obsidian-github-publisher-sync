module WordMeter.Capability.DomMount
  ( class DomMount
  , mountToHost
  , RecordingDomMountM(..)
  , DomMountRecording
  , runRecordingDomMountM
  ) where

import Prelude

import Control.Monad.State.Trans (StateT, modify_, runStateT)
import Data.Identity (Identity(..))
import Data.Tuple (Tuple(..))
import Effect.Class (liftEffect)
import WordMeter.AppM (AppM(..))
import WordMeter.Vdom (Node)
import WordMeter.Vdom as Vdom

class Monad m <= DomMount m where
  mountToHost :: String -> Node -> m Unit

instance domMountAppM :: DomMount AppM where
  mountToHost hostElementId node =
    AppM (liftEffect (Vdom.mount hostElementId node))

-- | Test newtype that records each mount request as a `{ hostElementId, node }`
-- | tuple so a test can assert how many times the program rerendered
-- | without ever touching the DOM.
type DomMountRecording = Array { hostElementId :: String, node :: Node }

newtype RecordingDomMountM a =
  RecordingDomMountM (StateT DomMountRecording Identity a)

derive newtype instance functorRecordingDomMountM :: Functor RecordingDomMountM
derive newtype instance applyRecordingDomMountM :: Apply RecordingDomMountM
derive newtype instance applicativeRecordingDomMountM :: Applicative RecordingDomMountM
derive newtype instance bindRecordingDomMountM :: Bind RecordingDomMountM
derive newtype instance monadRecordingDomMountM :: Monad RecordingDomMountM

instance domMountRecordingDomMountM :: DomMount RecordingDomMountM where
  mountToHost hostElementId node = RecordingDomMountM
    (modify_ (\mounts -> mounts <> [ { hostElementId, node } ]))

runRecordingDomMountM
  :: forall a
   . RecordingDomMountM a
  -> { result :: a, mounts :: DomMountRecording }
runRecordingDomMountM (RecordingDomMountM stateful) =
  case runStateT stateful [] of
    Identity (Tuple result mounts) -> { result, mounts }
