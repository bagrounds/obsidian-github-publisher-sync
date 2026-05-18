module WordMeter.Persistence
  ( PersistenceError(..)
  , storageKey
  , storageVersion
  , encodePersistedData
  , decodePersistedData
  , renderPersistenceError
  ) where

import Prelude

import Data.Argonaut.Core (Json, jsonEmptyObject, stringify)
import Data.Argonaut.Decode (JsonDecodeError, decodeJson, parseJson, printJsonDecodeError, (.:), (.:?))
import Data.Argonaut.Encode (encodeJson, (:=), (~>))
import Data.Either (Either(..))
import Data.Maybe (fromMaybe)
import Data.Traversable (traverse)
import WordMeter.Recording.Session (PersistedData, PersistedLoggedInterval)

storageKey :: String
storageKey = "word-meter:state:v1"

storageVersion :: Int
storageVersion = 1

data PersistenceError
  = InvalidJson String
  | SchemaMismatch JsonDecodeError
  | UnsupportedVersion Int

renderPersistenceError :: PersistenceError -> String
renderPersistenceError (InvalidJson detail) = "invalid json: " <> detail
renderPersistenceError (SchemaMismatch detail) =
  "schema mismatch: " <> printJsonDecodeError detail
renderPersistenceError (UnsupportedVersion actual) =
  "unsupported schema version: expected "
    <> show storageVersion
    <> " but got "
    <> show actual

encodePersistedData :: PersistedData -> String
encodePersistedData persisted = stringify (encodeJson envelope)
  where
  envelope :: Json
  envelope =
    "version" := storageVersion
      ~> "totalWords" := persisted.totalWords
      ~> "wordsToday" := persisted.wordsToday
      ~> "todayLocalDate" := persisted.todayLocalDate
      ~> "firstStartedAt" := persisted.firstStartedAt
      ~> "completedActiveMs" := persisted.completedActiveMs
      ~> "cloudFallbackAttempted" := persisted.cloudFallbackAttempted
      ~> "wordEvents" := persisted.wordEvents
      ~> "eventLog" := persisted.eventLog
      ~> jsonEmptyObject

decodePersistedData :: String -> Either PersistenceError PersistedData
decodePersistedData payload = do
  json <- mapInvalidJson (parseJson payload)
  envelope <- mapSchema (decodeJson json)
  actualVersion <- mapSchema (envelope .: "version")
  when (actualVersion /= storageVersion)
    (Left (UnsupportedVersion actualVersion))
  totalWords <- mapSchema (envelope .: "totalWords")
  firstStartedAt <- mapSchema (envelope .: "firstStartedAt")
  -- `completedActiveMs`, `cloudFallbackAttempted`, `wordsToday`, and
  -- `todayLocalDate` were added after v1 shipped; decode them as
  -- optional so existing localStorage payloads keep loading. New
  -- writes always include them.
  completedActiveMs <- mapSchema (envelope .:? "completedActiveMs")
  cloudFallbackAttempted <- mapSchema (envelope .:? "cloudFallbackAttempted")
  wordsToday <- mapSchema (envelope .:? "wordsToday")
  todayLocalDate <- mapSchema (envelope .:? "todayLocalDate")
  wordEvents <- mapSchema (envelope .: "wordEvents")
  rawEventLog <- mapSchema (envelope .: "eventLog" :: Either JsonDecodeError (Array Json))
  eventLog <- mapSchema (traverse decodePersistedLoggedInterval rawEventLog)
  pure
    { totalWords
    , wordsToday: fromMaybe 0 wordsToday
    , todayLocalDate: join todayLocalDate
    , firstStartedAt
    , completedActiveMs: fromMaybe 0.0 completedActiveMs
    , cloudFallbackAttempted: fromMaybe false cloudFallbackAttempted
    , wordEvents
    , eventLog
    }
  where
  mapInvalidJson :: forall a. Either JsonDecodeError a -> Either PersistenceError a
  mapInvalidJson = case _ of
    Left detail -> Left (InvalidJson (printJsonDecodeError detail))
    Right value -> Right value

  mapSchema :: forall a. Either JsonDecodeError a -> Either PersistenceError a
  mapSchema = case _ of
    Left detail -> Left (SchemaMismatch detail)
    Right value -> Right value

-- | Decode one event-log entry. The three word-stats fields
-- | (`mostFrequentWord`, `mostFrequentWordCount`, `longestWord`) were
-- | added after v1 shipped, so decode them as optional and default
-- | them to `Nothing`. New writes always include them.
decodePersistedLoggedInterval
  :: Json -> Either JsonDecodeError PersistedLoggedInterval
decodePersistedLoggedInterval json = do
  entry <- decodeJson json
  startedAt <- entry .: "startedAt"
  endedAt <- entry .: "endedAt"
  wordCount <- entry .: "wordCount"
  mostFrequentWord <- entry .:? "mostFrequentWord"
  mostFrequentWordCount <- entry .:? "mostFrequentWordCount"
  longestWord <- entry .:? "longestWord"
  pure
    { startedAt
    , endedAt
    , wordCount
    , mostFrequentWord: join mostFrequentWord
    , mostFrequentWordCount: join mostFrequentWordCount
    , longestWord: join longestWord
    }
