module WordMeter.FFI.StorageError
  ( StorageError(..)
  , renderStorageError
  ) where

import Prelude

data StorageError
  = StorageUnavailable
  | StorageException String
  | MissingKey String

derive instance eqStorageError :: Eq StorageError

instance showStorageError :: Show StorageError where
  show StorageUnavailable = "StorageUnavailable"
  show (StorageException detail) = "StorageException " <> show detail
  show (MissingKey key) = "MissingKey " <> show key

renderStorageError :: StorageError -> String
renderStorageError = case _ of
  StorageUnavailable -> "localStorage is unavailable in this environment"
  StorageException detail -> "localStorage error: " <> detail
  MissingKey key -> "no entry stored under key " <> key
