module WordMeter.Capability.Environment
  ( class Environment
  , captureEnvironmentSnapshot
  , StubEnvironmentM(..)
  , runStubEnvironmentM
  ) where

import Prelude

import Control.Monad.Reader.Trans (ReaderT, ask, runReaderT)
import Data.Identity (Identity(..))
import Effect.Class (liftEffect)
import WordMeter.AppM (AppM(..))
import WordMeter.Diagnostics (EnvironmentSnapshot)
import WordMeter.FFI.Environment as FFI

class Monad m <= Environment m where
  captureEnvironmentSnapshot :: String -> m EnvironmentSnapshot

instance environmentAppM :: Environment AppM where
  captureEnvironmentSnapshot bundleVersion =
    AppM (liftEffect (FFI.captureEnvironmentSnapshot bundleVersion))

-- | Test newtype that hands back a canned snapshot, ignoring the
-- | version argument. Useful when a test wants to drive the program
-- | through the startup path without depending on the real
-- | `navigator.*` globals.
newtype StubEnvironmentM a =
  StubEnvironmentM (ReaderT EnvironmentSnapshot Identity a)

derive newtype instance functorStubEnvironmentM :: Functor StubEnvironmentM
derive newtype instance applyStubEnvironmentM :: Apply StubEnvironmentM
derive newtype instance applicativeStubEnvironmentM :: Applicative StubEnvironmentM
derive newtype instance bindStubEnvironmentM :: Bind StubEnvironmentM
derive newtype instance monadStubEnvironmentM :: Monad StubEnvironmentM

instance environmentStubEnvironmentM :: Environment StubEnvironmentM where
  captureEnvironmentSnapshot _bundleVersion = StubEnvironmentM ask

runStubEnvironmentM
  :: forall a
   . EnvironmentSnapshot
  -> StubEnvironmentM a
  -> a
runStubEnvironmentM stubbedSnapshot (StubEnvironmentM reader) =
  case runReaderT reader stubbedSnapshot of
    Identity value -> value
