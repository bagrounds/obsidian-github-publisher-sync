module WordMeter.FFI.Storage
  ( readPersistedString
  , writePersistedString
  , clearPersistedString
  ) where

import Prelude

import Data.Either (Either(..))
import Effect (Effect)
import WordMeter.FFI.StorageError (StorageError(..))

type StorageOutcome a =
  { tag :: String
  , detail :: String
  , value :: a
  }

foreign import readPersistedStringImpl
  :: String -> Effect (StorageOutcome String)

foreign import writePersistedStringImpl
  :: String -> String -> Effect (StorageOutcome Unit)

foreign import clearPersistedStringImpl
  :: String -> Effect (StorageOutcome Unit)

readPersistedString :: String -> Effect (Either StorageError String)
readPersistedString key = interpretRead key <$> readPersistedStringImpl key

writePersistedString :: String -> String -> Effect (Either StorageError Unit)
writePersistedString key payload =
  interpretMutation <$> writePersistedStringImpl key payload

clearPersistedString :: String -> Effect (Either StorageError Unit)
clearPersistedString key =
  interpretMutation <$> clearPersistedStringImpl key

interpretRead :: String -> StorageOutcome String -> Either StorageError String
interpretRead key outcome = case outcome.tag of
  "ok" -> Right outcome.value
  "missing" -> Left (MissingKey key)
  "unavailable" -> Left StorageUnavailable
  _ -> Left (StorageException outcome.detail)

interpretMutation :: forall a. StorageOutcome a -> Either StorageError a
interpretMutation outcome = case outcome.tag of
  "ok" -> Right outcome.value
  "unavailable" -> Left StorageUnavailable
  _ -> Left (StorageException outcome.detail)
