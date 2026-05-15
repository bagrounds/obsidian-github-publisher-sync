module WordMeter.AppM
  ( ApplicationEnvironment
  , AppM(..)
  , runAppM
  ) where

import Prelude

import Control.Monad.Reader.Class (class MonadAsk)
import Control.Monad.Reader.Trans (ReaderT, runReaderT)
import Data.Maybe (Maybe)
import Effect (Effect)
import Effect.Class (class MonadEffect)
import Effect.Ref (Ref)
import WordMeter.FFI.WakeLock (WakeLockSentinel)
import WordMeter.Recording (Session)

type ApplicationEnvironment =
  { sessionRef :: Ref Session
  , wakeLockSentinelRef :: Ref (Maybe WakeLockSentinel)
  }

newtype AppM a = AppM (ReaderT ApplicationEnvironment Effect a)

runAppM :: forall a. ApplicationEnvironment -> AppM a -> Effect a
runAppM applicationEnvironment (AppM reader) =
  runReaderT reader applicationEnvironment

derive newtype instance functorAppM :: Functor AppM
derive newtype instance applyAppM :: Apply AppM
derive newtype instance applicativeAppM :: Applicative AppM
derive newtype instance bindAppM :: Bind AppM
derive newtype instance monadAppM :: Monad AppM
derive newtype instance monadEffectAppM :: MonadEffect AppM
derive newtype instance monadAskAppM :: MonadAsk ApplicationEnvironment AppM
