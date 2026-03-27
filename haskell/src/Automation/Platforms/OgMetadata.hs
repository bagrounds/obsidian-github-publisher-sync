module Automation.Platforms.OgMetadata
  ( extractOgProperty
  , fetchOgMetadata
  , fetchImageAsBuffer
  ) where

import qualified Data.ByteString.Lazy as LBS
import Data.Text (Text)
import qualified Data.Text as T
import qualified Network.HTTP.Client as HTTP
import qualified Network.HTTP.Client.TLS as TLS

import Automation.Types (OgMetadata (..))

extractOgProperty :: Text -> Text -> Maybe Text
extractOgProperty property html =
  let marker = "property=\"og:" <> property <> "\" content=\""
  in case T.splitOn marker html of
    (_ : rest : _) -> Just (T.takeWhile (/= '"') rest)
    _              -> Nothing

fetchOgMetadata :: Text -> IO OgMetadata
fetchOgMetadata url = do
  manager <- TLS.newTlsManager
  request <- HTTP.parseRequest (T.unpack url)
  response <- HTTP.httpLbs request manager
  let body = T.pack (show (HTTP.responseBody response))
  pure OgMetadata
    { ogTitle       = extractOgProperty "title" body
    , ogDescription = extractOgProperty "description" body
    , ogImageUrl    = extractOgProperty "image" body
    }

fetchImageAsBuffer :: Text -> IO LBS.ByteString
fetchImageAsBuffer url = do
  manager <- TLS.newTlsManager
  request <- HTTP.parseRequest (T.unpack url)
  response <- HTTP.httpLbs request manager
  pure (HTTP.responseBody response)
