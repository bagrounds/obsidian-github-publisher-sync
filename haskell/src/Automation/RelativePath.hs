module Automation.RelativePath
  ( RelativePath (..)
  , mkRelativePath
  ) where

import Data.Text (Text)
import qualified Data.Text as T

newtype RelativePath = RelativePath { unRelativePath :: Text }
  deriving (Eq, Ord)

instance Show RelativePath where
  show (RelativePath value) = "RelativePath " <> show value

mkRelativePath :: Text -> Either Text RelativePath
mkRelativePath value
  | T.null value = Left "RelativePath must not be empty"
  | T.isPrefixOf "/" value = Left ("Path must be relative, got absolute: " <> T.take 50 value)
  | otherwise = Right (RelativePath value)
