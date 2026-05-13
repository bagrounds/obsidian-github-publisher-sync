-- | Thin FFI over `window.localStorage` so the slice-6 persistence
-- | layer can survive private mode, sandboxed iframes, and quota
-- | failures without crashing the meter. Every operation returns
-- | gracefully: reads hand back `Nothing` on missing key or any error,
-- | writes and removes swallow failures silently. Consumers layer
-- | their own JSON encode / decode on top.
module WordMeter.FFI.Storage
  ( storageKey
  , storageVersion
  , readPersistedString
  , writePersistedString
  , clearPersistedString
  , decodePersistedPayload
  ) where

import Prelude

import Data.Maybe (Maybe(..))
import Effect (Effect)
import WordMeter.Recording (PersistedData)

-- | Namespaced + versioned so the PureScript port never collides with
-- | the legacy JS bundle's `word-meter:state:v1` key and so future
-- | schema bumps can ignore old payloads.
storageKey :: String
storageKey = "word-meter-ps:state:v1"

-- | Schema sentinel embedded in the persisted JSON payload.
storageVersion :: Int
storageVersion = 1

foreign import readPersistedStringImpl
  :: forall a. Maybe a -> (a -> Maybe a) -> String -> Effect (Maybe String)

readPersistedString :: String -> Effect (Maybe String)
readPersistedString = readPersistedStringImpl Nothing Just

foreign import writePersistedString :: String -> String -> Effect Unit

foreign import clearPersistedString :: String -> Effect Unit

foreign import decodePersistedPayloadImpl
  :: forall a
   . Maybe a
  -> (a -> Maybe a)
  -> Int
  -> String
  -> Maybe PersistedData

-- | Pure JSON-decode + structural sanitization. Hands back `Nothing`
-- | for anything that does not match the slice-6 schema: missing
-- | version sentinel, wrong types, malformed arrays, etc.
decodePersistedPayload :: String -> Maybe PersistedData
decodePersistedPayload =
  decodePersistedPayloadImpl Nothing Just storageVersion
