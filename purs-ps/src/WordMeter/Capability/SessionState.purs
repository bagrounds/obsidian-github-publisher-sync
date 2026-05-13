module WordMeter.Capability.SessionState
  ( class SessionState
  , readCurrentSession
  , updateSession
  , StatefulSessionM(..)
  , runStatefulSessionM
  ) where

import Prelude

import Control.Monad.Reader.Class (ask)
import Control.Monad.State.Trans (StateT, get, modify_, runStateT)
import Data.Identity (Identity(..))
import Data.Tuple (Tuple(..))
import Effect.Class (liftEffect)
import Effect.Ref as Ref
import WordMeter.AppM (AppM(..))
import WordMeter.Recording (Action, Session, reduce)

class Monad m <= SessionState m where
  readCurrentSession :: m Session
  updateSession :: Action -> m Unit

instance sessionStateAppM :: SessionState AppM where
  readCurrentSession = AppM do
    applicationEnvironment <- ask
    liftEffect (Ref.read applicationEnvironment.sessionRef)
  updateSession action = AppM do
    applicationEnvironment <- ask
    liftEffect (Ref.modify_ (reduce action) applicationEnvironment.sessionRef)

-- | Test newtype backed by `StateT Session Identity` so reducer-driven
-- | flows can be exercised without an `Effect.Ref`.
newtype StatefulSessionM a =
  StatefulSessionM (StateT Session Identity a)

derive newtype instance functorStatefulSessionM :: Functor StatefulSessionM
derive newtype instance applyStatefulSessionM :: Apply StatefulSessionM
derive newtype instance applicativeStatefulSessionM :: Applicative StatefulSessionM
derive newtype instance bindStatefulSessionM :: Bind StatefulSessionM
derive newtype instance monadStatefulSessionM :: Monad StatefulSessionM

instance sessionStateStatefulSessionM :: SessionState StatefulSessionM where
  readCurrentSession = StatefulSessionM get
  updateSession action = StatefulSessionM (modify_ (reduce action))

runStatefulSessionM
  :: forall a
   . Session
  -> StatefulSessionM a
  -> { result :: a, finalSession :: Session }
runStatefulSessionM startingSession (StatefulSessionM stateful) =
  case runStateT stateful startingSession of
    Identity (Tuple result finalSession) -> { result, finalSession }
