-- | Pure logic for the slice-5 diagnostics drawer: the timestamped
-- | event log, the captured environment snapshot, and the rendered
-- | text that the copy-to-clipboard button hands back to the user.
module WordMeter.Diagnostics
  ( DiagnosticEntry
  , EnvironmentSnapshot
  , diagnosticsLimit
  , recordEntry
  , formatEntries
  , formatSnapshot
  , formatDiagnostics
  , emptyEnvironment
  ) where

import Prelude

import Data.Array (length, takeEnd) as Array
import Data.DateTime.Instant (Instant)
import Data.Maybe (Maybe(..))
import Data.String.Common (joinWith)
import WordMeter.Clock (formatClockTime)

-- | One line in the diagnostics log: a wall-clock timestamp, a short
-- | label describing the event, and an optional detail string.
type DiagnosticEntry =
  { timestamp :: Instant
  , label :: String
  , detail :: String
  }

-- | A snapshot of the host environment captured once at startup so the
-- | diagnostics text can answer "what does this browser support?" for
-- | bug reports without having to re-query each render.
type EnvironmentSnapshot =
  { version :: String
  , userAgent :: String
  , navigatorLanguage :: String
  }

-- | Matches the legacy bundle's `DIAGNOSTICS_MAX_ENTRIES`; the log
-- | rolls oldest-out once full so it never grows unbounded.
diagnosticsLimit :: Int
diagnosticsLimit = 60

emptyEnvironment :: EnvironmentSnapshot
emptyEnvironment =
  { version: ""
  , userAgent: "(unknown)"
  , navigatorLanguage: "(unknown)"
  }

-- | Append `entry` to `entries`, capping at `diagnosticsLimit` by
-- | dropping oldest entries.
recordEntry
  :: DiagnosticEntry
  -> Array DiagnosticEntry
  -> Array DiagnosticEntry
recordEntry entry entries =
  Array.takeEnd diagnosticsLimit (entries <> [ entry ])

formatSnapshot :: EnvironmentSnapshot -> String
formatSnapshot snapshot =
  joinWith "\n"
    [ "version           : " <> snapshot.version
    , "userAgent         : " <> snapshot.userAgent
    , "navigator.language: " <> snapshot.navigatorLanguage
    ]

formatEntries :: Array DiagnosticEntry -> String
formatEntries entries
  | Array.length entries == 0 =
      "(no events yet — press Start counting to populate the log)"
  | otherwise = joinWith "\n" (map formatEntry entries)

formatEntry :: DiagnosticEntry -> String
formatEntry entry =
  formatClockTime entry.timestamp <> "  " <> entry.label
    <> (if entry.detail == "" then "" else " — " <> entry.detail)

formatDiagnostics
  :: Maybe EnvironmentSnapshot
  -> Array DiagnosticEntry
  -> String
formatDiagnostics maybeSnapshot entries =
  case maybeSnapshot of
    Just snapshot -> formatSnapshot snapshot <> "\n\n" <> formatEntries entries
    Nothing -> formatEntries entries
