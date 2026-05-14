module WordMeter.Capability.Storage
  ( class Storage
  , LoadError(..)
  , renderLoadError
  , loadPersistedSnapshot
  , persistSnapshot
  , clearPersistedSnapshot
  , InMemoryStorageM(..)
  , runInMemoryStorageM
  ) where

import Prelude

import Control.Monad.Reader.Class (ask)
import Control.Monad.State.Trans (StateT, get, put, runStateT)
import Data.Either (Either(..))
import Data.Identity (Identity(..))
import Data.Maybe (Maybe(..))
import Data.Tuple (Tuple(..))
import Effect.Class (liftEffect)
import WordMeter.AppM (AppM(..))
import WordMeter.FFI.Storage as FFIStorage
import WordMeter.FFI.StorageError (StorageError(..), renderStorageError)
import WordMeter.Persistence
  ( PersistenceError
  , decodePersistedData
  , encodePersistedData
  , renderPersistenceError
  , storageKey
  )
import WordMeter.Recording (PersistedData)

data LoadError
  = LoadStorageError StorageError
  | LoadDecodeError PersistenceError

renderLoadError :: LoadError -> String
renderLoadError = case _ of
  LoadStorageError detail -> renderStorageError detail
  LoadDecodeError detail -> renderPersistenceError detail

class Monad m <= Storage m where
  loadPersistedSnapshot :: m (Either LoadError (Maybe PersistedData))
  persistSnapshot :: PersistedData -> m (Either StorageError Unit)
  clearPersistedSnapshot :: m (Either StorageError Unit)

instance storageAppM :: Storage AppM where
  loadPersistedSnapshot = AppM do
    _ <- ask
    raw <- liftEffect (FFIStorage.readPersistedString storageKey)
    pure case raw of
      Left (MissingKey _) -> Right Nothing
      Left other -> Left (LoadStorageError other)
      Right payload -> case decodePersistedData payload of
        Left decodeFailure -> Left (LoadDecodeError decodeFailure)
        Right decoded -> Right (Just decoded)
  persistSnapshot persisted = AppM do
    _ <- ask
    liftEffect
      ( FFIStorage.writePersistedString
          storageKey
          (encodePersistedData persisted)
      )
  clearPersistedSnapshot = AppM do
    _ <- ask
    liftEffect (FFIStorage.clearPersistedString storageKey)

newtype InMemoryStorageM a =
  InMemoryStorageM (StateT (Maybe PersistedData) Identity a)

derive newtype instance functorInMemoryStorageM :: Functor InMemoryStorageM
derive newtype instance applyInMemoryStorageM :: Apply InMemoryStorageM
derive newtype instance applicativeInMemoryStorageM :: Applicative InMemoryStorageM
derive newtype instance bindInMemoryStorageM :: Bind InMemoryStorageM
derive newtype instance monadInMemoryStorageM :: Monad InMemoryStorageM

instance storageInMemoryStorageM :: Storage InMemoryStorageM where
  loadPersistedSnapshot = InMemoryStorageM (Right <$> get)
  persistSnapshot persisted = InMemoryStorageM do
    put (Just persisted)
    pure (Right unit)
  clearPersistedSnapshot = InMemoryStorageM do
    put Nothing
    pure (Right unit)

runInMemoryStorageM
  :: forall a
   . Maybe PersistedData
  -> InMemoryStorageM a
  -> { result :: a, finalSnapshot :: Maybe PersistedData }
runInMemoryStorageM starting (InMemoryStorageM stateful) =
  case runStateT stateful starting of
    Identity (Tuple result finalSnapshot) -> { result, finalSnapshot }
