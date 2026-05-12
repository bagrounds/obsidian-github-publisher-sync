module WordMeter.Words (countWords) where

import Prelude

import Data.Array (filter, length)
import Data.String (Pattern(..), Replacement(..), replaceAll, split, trim)

countWords :: String -> Int
countWords transcript =
  length
    $ filter isNonEmpty
    $ split (Pattern " ")
    $ collapseWhitespaceToSpace
    $ trim transcript

isNonEmpty :: String -> Boolean
isNonEmpty value = value /= ""

collapseWhitespaceToSpace :: String -> String
collapseWhitespaceToSpace =
  replaceAll (Pattern "\t") (Replacement " ")
    >>> replaceAll (Pattern "\n") (Replacement " ")
    >>> replaceAll (Pattern "\r") (Replacement " ")
