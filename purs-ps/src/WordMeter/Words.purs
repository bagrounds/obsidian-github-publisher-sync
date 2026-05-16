module WordMeter.Words (countWords) where

import Prelude

import Data.Array (filter, length)
import Data.String (Pattern(..), split, trim)
import WordMeter.Text (collapseWhitespaceToSpace)

countWords :: String -> Int
countWords transcript =
  length
    $ filter isNonEmpty
    $ split (Pattern " ")
    $ collapseWhitespaceToSpace
    $ trim transcript

isNonEmpty :: String -> Boolean
isNonEmpty value = value /= ""
