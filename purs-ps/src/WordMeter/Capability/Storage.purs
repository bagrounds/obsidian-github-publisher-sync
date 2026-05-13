module WordMeter.Capability.Storage
  ( class Storage
  , loadPersistedData
  , savePersistedData
  , clearPersistedData
  , InMemoryStorageM(..)
  , StorageContents
  , runInMemoryStorageM
  ) where

import Prelude

import Control.Monad.State.Trans (StateT, get, modify_, runStateT)
import Data.Identity (Identity(..))
import Data.Maybe (Maybe(..))
import Data.Tuple (Tuple(..))
import Effect.Class (liftEffect)
import WordMeter.AppM (AppM(..))
import WordMeter.FFI.Storage (PersistedData)
import WordMeter.FFI.Storage as FFI

-- | Capability for reading and writing the session's persistent snapshot.
class Monad m <= Storage m where
  loadPersistedData :: m (Maybe PersistedData)
  savePersistedData :: PersistedData -> m Unit
  clearPersistedData :: m Unit

instance storageAppM :: Storage AppM where
  loadPersistedData = AppM (liftEffect (FFI.loadData Nothing Just))
  savePersistedData persisted = AppM (liftEffect (FFI.saveData persisted))
  clearPersistedData = AppM (liftEffect FFI.clearData)

-- | Test newtype backed by `StateT (Maybe PersistedData) Identity`.
-- | Starts with `Nothing` (empty storage). Callers can prime it by
-- | constructing the `InMemoryStorageM` from a `put (Just data)` step
-- | or by passing `Just data` as the initial state to `runInMemoryStorageM`.
type StorageContents = Maybe PersistedData

newtype InMemoryStorageM a =
  InMemoryStorageM (StateT StorageContents Identity a)

derive newtype instance functorInMemoryStorageM :: Functor InMemoryStorageM
derive newtype instance applyInMemoryStorageM :: Apply InMemoryStorageM
derive newtype instance applicativeInMemoryStorageM :: Applicative InMemoryStorageM
derive newtype instance bindInMemoryStorageM :: Bind InMemoryStorageM
derive newtype instance monadInMemoryStorageM :: Monad InMemoryStorageM

instance storageInMemoryStorageM :: Storage InMemoryStorageM where
  loadPersistedData = InMemoryStorageM get
  savePersistedData persisted =
    InMemoryStorageM (modify_ (const (Just persisted)))
  clearPersistedData =
    InMemoryStorageM (modify_ (const Nothing))

runInMemoryStorageM
  :: forall a
   . StorageContents
  -> InMemoryStorageM a
  -> { result :: a, storageContents :: StorageContents }
runInMemoryStorageM initialContents (InMemoryStorageM stateful) =
  case runStateT stateful initialContents of
    Identity (Tuple result storageContents) -> { result, storageContents }
