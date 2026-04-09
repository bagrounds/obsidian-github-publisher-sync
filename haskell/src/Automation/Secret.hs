module Automation.Secret
  ( Secret (..)
  , mkSecret
  ) where

import Data.Text (Text)
import qualified Data.Text as T

newtype Secret = Secret { unSecret :: Text }
  deriving (Eq)

instance Show Secret where
  show _ = "<redacted>"

mkSecret :: Text -> Either Text Secret
mkSecret value
  | T.null (T.strip value) = Left "Secret must not be empty"
  | otherwise = Right (Secret value)
