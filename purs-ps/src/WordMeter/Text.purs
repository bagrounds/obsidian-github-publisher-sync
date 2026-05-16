-- | Shared text utilities for the Word Meter PureScript port.
-- |
-- | This module is intentionally pure — no `Effect`, no FFI — so every
-- | caller can use these functions in unit tests without touching the
-- | browser.
module WordMeter.Text (collapseWhitespaceToSpace) where

import Prelude

import Data.String (Pattern(..), Replacement(..), replaceAll)

-- | Replace every tab, newline, and carriage-return character with a
-- | single ASCII space. Consecutive whitespace characters of different
-- | kinds (e.g. a tab followed by a newline) become consecutive spaces
-- | rather than being collapsed into one; callers that need to reduce
-- | runs of spaces to a single space should follow up with `split` and
-- | `joinWith`. Used by both `WordMeter.Words.countWords` and
-- | `WordMeter.Recognition.Delta.normalizeTranscript`.
collapseWhitespaceToSpace :: String -> String
collapseWhitespaceToSpace =
  replaceAll (Pattern "\t") (Replacement " ")
    >>> replaceAll (Pattern "\n") (Replacement " ")
    >>> replaceAll (Pattern "\r") (Replacement " ")
