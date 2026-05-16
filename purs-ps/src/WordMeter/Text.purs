-- | Shared text utilities for the Word Meter PureScript port.
-- |
-- | This module is intentionally pure — no `Effect`, no FFI — so every
-- | caller can use these functions in unit tests without touching the
-- | browser.
module WordMeter.Text (collapseWhitespaceToSpace) where

import Prelude

import Data.String (Pattern(..), Replacement(..), replaceAll)

-- | Replace every tab, newline, and carriage-return character with a
-- | single ASCII space. Runs of consecutive whitespace are left
-- | intact; callers that need to collapse them further (e.g. into a
-- | single space) should apply `split` and `joinWith` afterwards.
-- | Used by both `WordMeter.Words.countWords` and
-- | `WordMeter.Recognition.Delta.normalizeTranscript`.
collapseWhitespaceToSpace :: String -> String
collapseWhitespaceToSpace =
  replaceAll (Pattern "\t") (Replacement " ")
    >>> replaceAll (Pattern "\n") (Replacement " ")
    >>> replaceAll (Pattern "\r") (Replacement " ")
