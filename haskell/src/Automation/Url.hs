module Automation.Url
  ( Url (..)
  , mkUrl
  ) where

import Data.Text (Text)
import qualified Data.Text as T

newtype Url = Url { unUrl :: Text }
  deriving (Eq, Ord)

instance Show Url where
  show (Url value) = "Url " <> show value

mkUrl :: Text -> Either Text Url
mkUrl value
  | T.isPrefixOf "https://" value = Right (Url value)
  | T.isPrefixOf "http://" value = Right (Url value)
  | otherwise = Left ("Invalid URL (must start with http:// or https://): " <> T.take 50 value)
