-- | Pure transcript-integration decision for the real recognition
-- | wiring. Reproduces the dedup logic that the original JavaScript
-- | build worked out for issue #6897: on Android Chrome with
-- | `continuous = true` and `interimResults = true` the recognizer
-- | re-emits the same utterance as a sequence of finalized results,
-- | each carrying the full cumulative transcript.
-- |
-- | This module is intentionally pure — no `Effect`, no FFI — so the
-- | reducer + unit tests can exercise every branch without touching the
-- | browser.
module WordMeter.Recognition.Delta
  ( TranscriptIntegration(..)
  , classifyFinalizedTranscript
  , normalizeTranscript
  , isWordBoundaryExtension
  ) where

import Prelude

import Data.Array (filter)
import Data.Maybe (isJust)
import Data.String
  ( Pattern(..)
  , split
  , stripPrefix
  , trim
  )
import Data.String.Common (joinWith, toLower)
import WordMeter.Text (collapseWhitespaceToSpace)
import WordMeter.Words (countWords)

-- | The four possible outcomes when a finalized transcript arrives,
-- | given the most recent raw finalized transcript the reducer already
-- | recorded. The reducer projects each constructor onto a session
-- | update: append a brand-new utterance, extend the last utterance by
-- | the additional words, refresh the caption timestamp, or do
-- | nothing.
data TranscriptIntegration
  = IgnoreDuplicate
  | ExtendUtterance { wordDelta :: Int, caption :: String }
  | StartNewUtterance { wordCount :: Int, caption :: String }
  | IgnoreEarlierSnapshot

derive instance eqTranscriptIntegration :: Eq TranscriptIntegration

instance showTranscriptIntegration :: Show TranscriptIntegration where
  show IgnoreDuplicate = "IgnoreDuplicate"
  show (ExtendUtterance fields) =
    "ExtendUtterance " <> show fields.wordDelta <> " " <> show fields.caption
  show (StartNewUtterance fields) =
    "StartNewUtterance " <> show fields.wordCount <> " " <> show fields.caption
  show IgnoreEarlierSnapshot = "IgnoreEarlierSnapshot"

-- | Decide what to do with `incoming`, given the most recent raw
-- | finalized transcript (`previous`, empty if none).
classifyFinalizedTranscript
  :: { previous :: String, incoming :: String } -> TranscriptIntegration
classifyFinalizedTranscript { previous, incoming } =
  let
    incomingNormalized = normalizeTranscript incoming
    previousNormalized = normalizeTranscript previous
  in
    if incomingNormalized == "" then
      IgnoreDuplicate
    else if previousNormalized /= "" && incomingNormalized == previousNormalized then
      IgnoreDuplicate
    else if isWordBoundaryExtension incomingNormalized previousNormalized then
      ExtendUtterance
        { wordDelta: countWords incoming - countWords previous
        , caption: incoming
        }
    else if isWordBoundaryExtension previousNormalized incomingNormalized then
      IgnoreEarlierSnapshot
    else
      StartNewUtterance
        { wordCount: countWords incoming
        , caption: incoming
        }

-- | Lowercase, trim, and collapse runs of whitespace to single spaces —
-- | the same shape as the legacy `normalizeTranscript` so refinements
-- | that only differ in case or whitespace are treated as duplicates.
normalizeTranscript :: String -> String
normalizeTranscript =
  trim
    >>> toLower
    >>> collapseWhitespaceToSpace
    >>> split (Pattern " ")
    >>> filter (_ /= "")
    >>> joinWith " "

-- | True iff `candidate` is `prefix` extended by at least one
-- | additional word. The word boundary requirement (a space at the
-- | join) is what keeps `"twinkle"` → `"twinkles"` from being read as
-- | a refinement of the same utterance.
isWordBoundaryExtension :: String -> String -> Boolean
isWordBoundaryExtension candidate prefix
  | prefix == "" = false
  | candidate == prefix = false
  | otherwise = isJust (stripPrefix (Pattern (prefix <> " ")) candidate)
