module WordMeter.Capability.Storage
  ( class Storage
  , loadPersistedSnapshot
  , persistSnapshot
  , clearPersistedSnapshot
  , InMemoryStorageM(..)
  , runInMemoryStorageM
  ) where

import Prelude

import Control.Monad.Reader.Class (ask)
import Control.Monad.State.Trans (StateT, get, put, runStateT)
import Data.Identity (Identity(..))
import Data.Maybe (Maybe(..))
import Data.Tuple (Tuple(..))
import Effect.Class (liftEffect)
import WordMeter.AppM (AppM(..))
import WordMeter.FFI.Storage as FFIStorage
import WordMeter.Recording
  ( PersistedData
  , encodePersistedData
  )

-- | Persistence capability: round-trips the slice-6 `PersistedData`
-- | through whatever backing store the runtime provides. The production
-- | instance writes to `localStorage`; tests use a `StateT`-backed
-- | in-memory cell so they can introspect every persist / clear /
-- | load call without touching a real browser.
class Monad m <= Storage m where
  loadPersistedSnapshot :: m (Maybe PersistedData)
  persistSnapshot :: PersistedData -> m Unit
  clearPersistedSnapshot :: m Unit

instance storageAppM :: Storage AppM where
  loadPersistedSnapshot = AppM do
    _ <- ask
    liftEffect do
      raw <- FFIStorage.readPersistedString FFIStorage.storageKey
      pure case raw of
        Nothing -> Nothing
        Just payload -> FFIStorage.decodePersistedPayload payload
  persistSnapshot persisted = AppM do
    _ <- ask
    liftEffect
      ( FFIStorage.writePersistedString
          FFIStorage.storageKey
          (encodePersistedData FFIStorage.storageVersion persisted)
      )
  clearPersistedSnapshot = AppM do
    _ <- ask
    liftEffect (FFIStorage.clearPersistedString FFIStorage.storageKey)

-- | Test newtype that keeps the current persisted snapshot in a single
-- | `StateT` cell. `runInMemoryStorageM` returns both the action result
-- | and the final cell contents so a test can assert "after this flow
-- | localStorage holds X".
newtype InMemoryStorageM a =
  InMemoryStorageM (StateT (Maybe PersistedData) Identity a)

derive newtype instance functorInMemoryStorageM :: Functor InMemoryStorageM
derive newtype instance applyInMemoryStorageM :: Apply InMemoryStorageM
derive newtype instance applicativeInMemoryStorageM :: Applicative InMemoryStorageM
derive newtype instance bindInMemoryStorageM :: Bind InMemoryStorageM
derive newtype instance monadInMemoryStorageM :: Monad InMemoryStorageM

instance storageInMemoryStorageM :: Storage InMemoryStorageM where
  loadPersistedSnapshot = InMemoryStorageM get
  persistSnapshot persisted = InMemoryStorageM (put (Just persisted))
  clearPersistedSnapshot = InMemoryStorageM (put Nothing)

runInMemoryStorageM
  :: forall a
   . Maybe PersistedData
  -> InMemoryStorageM a
  -> { result :: a, finalSnapshot :: Maybe PersistedData }
runInMemoryStorageM starting (InMemoryStorageM stateful) =
  case runStateT stateful starting of
    Identity (Tuple result finalSnapshot) -> { result, finalSnapshot }
