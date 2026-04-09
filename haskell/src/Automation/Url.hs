module Automation.Url
  ( Url
  , unUrl
  , mkUrl
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import qualified Network.URI as URI

newtype Url = Url { unUrl :: Text }
  deriving (Eq, Ord)

instance Show Url where
  show (Url value) = "Url " <> show value

mkUrl :: Text -> Either Text Url
mkUrl value = case URI.parseURI (T.unpack value) of
  Nothing -> Left ("Invalid URL: " <> T.take 50 value)
  Just uri
    | URI.uriScheme uri `elem` ["http:", "https:"] -> Right (Url value)
    | otherwise -> Left ("URL must use http or https scheme: " <> T.take 50 value)
