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

foreign import readJsRawString
  :: String -> Effect (StorageOutcome String)

foreign import writeJsRawString
  :: String -> String -> Effect (StorageOutcome Unit)

foreign import clearJsRawKey
  :: String -> Effect (StorageOutcome Unit)

readPersistedString :: String -> Effect (Either StorageError String)
readPersistedString key = interpretRead key <$> readJsRawString key

writePersistedString :: String -> String -> Effect (Either StorageError Unit)
writePersistedString key payload =
  interpretMutation <$> writeJsRawString key payload

clearPersistedString :: String -> Effect (Either StorageError Unit)
clearPersistedString key =
  interpretMutation <$> clearJsRawKey key

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
