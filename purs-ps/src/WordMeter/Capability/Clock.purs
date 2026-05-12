module WordMeter.Capability.Clock
  ( class Clock
  , currentTimeMillis
  , FixedClockM(..)
  , runFixedClockM
  ) where

import Prelude

import Control.Monad.Reader.Trans (ReaderT, ask, runReaderT)
import Data.Identity (Identity(..))
import Effect.Class (liftEffect)
import WordMeter.AppM (AppM(..))
import WordMeter.FFI.Clock as FFI

class Monad m <= Clock m where
  currentTimeMillis :: m Number

instance clockAppM :: Clock AppM where
  currentTimeMillis = AppM (liftEffect FFI.currentTimeMillis)

newtype FixedClockM a = FixedClockM (ReaderT Number Identity a)

derive newtype instance functorFixedClockM :: Functor FixedClockM
derive newtype instance applyFixedClockM :: Apply FixedClockM
derive newtype instance applicativeFixedClockM :: Applicative FixedClockM
derive newtype instance bindFixedClockM :: Bind FixedClockM
derive newtype instance monadFixedClockM :: Monad FixedClockM

instance clockFixedClockM :: Clock FixedClockM where
  currentTimeMillis = FixedClockM ask

runFixedClockM :: forall a. Number -> FixedClockM a -> a
runFixedClockM fixedTime (FixedClockM reader) =
  case runReaderT reader fixedTime of
    Identity value -> value
