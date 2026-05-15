module WordMeter.Recognition.Delta
  ( TranscriptIntegration(..)
  , classifyFinalizedTranscript
  ) where

import Prelude

import Data.String (Pattern(..), Replacement(..), replace, toLower, trim, take, length)
import WordMeter.Words (countWords)

data TranscriptIntegration
  = IgnoreDuplicate
  | ExtendUtterance { wordDelta :: Int, caption :: String }
  | StartNewUtterance { wordCount :: Int, caption :: String }
  | IgnoreEarlierSnapshot

normalizeTranscript :: String -> String
normalizeTranscript transcript =
  transcript
    # \s -> (s :: String)
    # trim
    # toLower
    # replace (Pattern " ") (Replacement " ")

isWordBoundaryExtension :: String -> String -> Boolean
isWordBoundaryExtension candidate prefix =
  if prefix == "" then false
  else if candidate == prefix then false
  else
    let
      expectedPrefix = prefix <> " "
      prefixLength = length expectedPrefix
      candidatePrefix = take prefixLength candidate
    in
      candidatePrefix == expectedPrefix

classifyFinalizedTranscript
  :: { previous :: String, incoming :: String }
  -> TranscriptIntegration
classifyFinalizedTranscript { previous, incoming } =
  let
    newNormalized = normalizeTranscript incoming
    lastNormalized = normalizeTranscript previous
  in
    if newNormalized == "" then IgnoreDuplicate
    else if lastNormalized /= "" && newNormalized == lastNormalized then IgnoreDuplicate
    else if isWordBoundaryExtension newNormalized lastNormalized then
      let
        previousWordCount = countWords previous
        newWordCount = countWords incoming
        delta = newWordCount - previousWordCount
      in
        ExtendUtterance { wordDelta: delta, caption: incoming }
    else if isWordBoundaryExtension lastNormalized newNormalized then
      IgnoreEarlierSnapshot
    else
      StartNewUtterance { wordCount: countWords incoming, caption: incoming }
