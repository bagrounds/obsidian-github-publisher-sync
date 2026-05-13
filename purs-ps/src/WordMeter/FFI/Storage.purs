module WordMeter.FFI.Storage
  ( PersistedData
  , loadData
  , saveData
  , clearData
  ) where

import Prelude

import Effect (Effect)

-- | Subset of session state that survives page reloads. `firstStartedAt`
-- | is `NaN` when the session has never been started; the PureScript caller
-- | converts to `Maybe Number` via `Data.Number.isFinite`.
type PersistedData =
  { totalWords :: Int
  , firstStartedAt :: Number
  , wordEvents :: Array { timestamp :: Number, wordCount :: Int }
  , eventLog :: Array { startedAt :: Number, endedAt :: Number, wordCount :: Int }
  }

-- | Load validated persisted session data from localStorage.
-- | Returns `nothing` if storage is unavailable, empty, or holds an
-- | unrecognised schema version.
foreign import loadData
  :: forall a
   . a
  -> (PersistedData -> a)
  -> Effect a

-- | Serialise and store the given session snapshot.
foreign import saveData :: PersistedData -> Effect Unit

-- | Remove the stored snapshot (called on reset).
foreign import clearData :: Effect Unit
