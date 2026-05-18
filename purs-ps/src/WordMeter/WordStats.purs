-- | Per-counting-period word statistics: a case-insensitive frequency
-- | table plus the longest word seen (preserving the casing of its
-- | first occurrence). Pure data + pure updaters — no `Effect`, no
-- | FFI — so the reducer and the unit tests share the same code.
module WordMeter.WordStats
  ( WordStats
  , WordFrequency
  , emptyWordStats
  , addTranscript
  , extractWords
  , normalizeForFrequency
  , mostFrequentWord
  , longestWord
  , isEmptyWordStats
  ) where

import Prelude

import Data.Array (dropWhile, filter, foldl, reverse, sortWith)
import Data.Array as Array
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (Maybe(..))
import Data.String (Pattern(..), null, split, trim)
import Data.String (length, toLower) as String
import Data.String.CodePoints (CodePoint, codePointFromChar, fromCodePointArray, toCodePointArray)
import Data.Tuple (Tuple(..))
import WordMeter.Text (collapseWhitespaceToSpace)

-- | Frequency-table entry surfaced to callers as a plain record so
-- | view code can render `{word, count}` without unwrapping a Tuple.
type WordFrequency = { word :: String, count :: Int }

-- | A counting period's accumulated word stats. The frequency map is
-- | keyed by the lowercased, punctuation-stripped form of each word
-- | so "Hello," and "hello" collapse into one bucket, while `longest`
-- | preserves the first-seen casing for display.
newtype WordStats = WordStats
  { frequencies :: Map String Int
  , longest :: Maybe String
  }

derive newtype instance eqWordStats :: Eq WordStats

emptyWordStats :: WordStats
emptyWordStats = WordStats { frequencies: Map.empty, longest: Nothing }

isEmptyWordStats :: WordStats -> Boolean
isEmptyWordStats (WordStats stats) = Map.isEmpty stats.frequencies

-- | Fold an incoming finalized transcript into the running stats:
-- | tokenize, strip surrounding punctuation, drop empty tokens, then
-- | bump the frequency for each word and update the longest-word
-- | tracker.
addTranscript :: String -> WordStats -> WordStats
addTranscript transcript stats =
  foldl (flip addWord) stats (extractWords transcript)

addWord :: String -> WordStats -> WordStats
addWord rawWord (WordStats stats) =
  let
    normalized = normalizeForFrequency rawWord
  in
    if null normalized then WordStats stats
    else
      WordStats
        { frequencies: Map.alter incrementCount normalized stats.frequencies
        , longest: updateLongest rawWord stats.longest
        }

incrementCount :: Maybe Int -> Maybe Int
incrementCount Nothing = Just 1
incrementCount (Just count) = Just (count + 1)

-- | Earliest casing wins on ties, so a string that comes in later
-- | with the same length does not displace the first occurrence.
updateLongest :: String -> Maybe String -> Maybe String
updateLongest candidate Nothing = Just candidate
updateLongest candidate (Just current)
  | String.length candidate > String.length current = Just candidate
  | otherwise = Just current

-- | Split a transcript on whitespace, strip surrounding punctuation
-- | from each token, and discard any empty residue. Exposed so
-- | consumers and tests share the same tokenizer.
extractWords :: String -> Array String
extractWords transcript =
  filter (not <<< null)
    $ map stripWordPunctuation
    $ filter (not <<< null)
    $ split (Pattern " ")
    $ collapseWhitespaceToSpace
    $ trim transcript

-- | Drop a small set of ASCII punctuation code points from both ends
-- | of a token. Intra-word punctuation (e.g. the apostrophe in
-- | "don't") is left alone so the displayed form remains natural.
stripWordPunctuation :: String -> String
stripWordPunctuation word =
  fromCodePointArray
    $ reverse
    $ dropWhile isStrippablePunctuation
    $ reverse
    $ dropWhile isStrippablePunctuation
    $ toCodePointArray word

isStrippablePunctuation :: CodePoint -> Boolean
isStrippablePunctuation cp =
  cp == codePointFromChar '.'
    || cp == codePointFromChar ','
    || cp == codePointFromChar ';'
    || cp == codePointFromChar ':'
    || cp == codePointFromChar '!'
    || cp == codePointFromChar '?'
    || cp == codePointFromChar '"'
    || cp == codePointFromChar '('
    || cp == codePointFromChar ')'
    || cp == codePointFromChar '['
    || cp == codePointFromChar ']'
    || cp == codePointFromChar '{'
    || cp == codePointFromChar '}'
    || cp == codePointFromChar '-'
    || cp == codePointFromChar '_'
    || cp == codePointFromChar '/'
    || cp == codePointFromChar '\\'

-- | Lowercase a word and strip surrounding punctuation. Used as the
-- | frequency-map key so casing and punctuation differences collapse
-- | into a single bucket.
normalizeForFrequency :: String -> String
normalizeForFrequency = stripWordPunctuation >>> String.toLower

-- | The single most-used word in the period (and its count) or
-- | `Nothing` if the period is empty. Ties on count are broken
-- | alphabetically on the normalized key so the choice is
-- | deterministic across reloads.
mostFrequentWord :: WordStats -> Maybe WordFrequency
mostFrequentWord (WordStats stats) =
  case Array.head (sortWith rankKey (Map.toUnfoldable stats.frequencies)) of
    Nothing -> Nothing
    Just (Tuple word count) -> Just { word, count }
  where
  rankKey :: Tuple String Int -> Tuple Int String
  rankKey (Tuple word count) = Tuple (-count) word

-- | The longest word seen during the period (in its original
-- | casing). Ties go to the first occurrence.
longestWord :: WordStats -> Maybe String
longestWord (WordStats stats) = stats.longest
