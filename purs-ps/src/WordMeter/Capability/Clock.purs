module WordMeter.Capability.Clock
  ( class Clock
  , currentTimeMillis
  , FixedClockM(..)
  , runFixedClockM
  ) where

import Prelude

import Control.Monad.Reader.Trans (ReaderT, ask, runReaderT)
import Data.DateTime.Instant (Instant, instant)
import Data.Identity (Identity(..))
import Data.Maybe (fromMaybe)
import Data.Time.Duration (Milliseconds(..))
import Effect.Class (liftEffect)
import WordMeter.AppM (AppM(..))
import WordMeter.FFI.Clock as FFI

class Monad m <= Clock m where
  currentTimeMillis :: m Instant

instance clockAppM :: Clock AppM where
  currentTimeMillis = AppM do
    ms <- liftEffect FFI.currentTimeMillis
    pure (fromMaybe bottom (instant (Milliseconds ms)))

newtype FixedClockM a = FixedClockM (ReaderT Instant Identity a)

derive newtype instance functorFixedClockM :: Functor FixedClockM
derive newtype instance applyFixedClockM :: Apply FixedClockM
derive newtype instance applicativeFixedClockM :: Applicative FixedClockM
derive newtype instance bindFixedClockM :: Bind FixedClockM
derive newtype instance monadFixedClockM :: Monad FixedClockM

instance clockFixedClockM :: Clock FixedClockM where
  currentTimeMillis = FixedClockM ask

runFixedClockM :: forall a. Instant -> FixedClockM a -> a
runFixedClockM fixedTime (FixedClockM reader) =
  case runReaderT reader fixedTime of
    Identity value -> value
