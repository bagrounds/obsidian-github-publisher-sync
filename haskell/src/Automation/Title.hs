module Automation.Title
  ( Title
  , unTitle
  , mkTitle
  ) where

import Data.Text (Text)
import qualified Data.Text as T

newtype Title = Title { unTitle :: Text }
  deriving (Eq, Ord)

instance Show Title where
  show (Title value) = "Title " <> show value

mkTitle :: Text -> Either Text Title
mkTitle value
  | T.null (T.strip value) = Left "Title must not be empty or whitespace"
  | otherwise = Right (Title value)
