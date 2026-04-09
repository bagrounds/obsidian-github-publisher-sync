module Automation.Platforms.OgMetadata
  ( extractOgProperty
  , fetchOgMetadata
  , fetchImageAsBuffer
  , detectContentType
  ) where

import qualified Data.ByteString.Lazy as LBS
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Network.HTTP.Client as HTTP
import qualified Network.HTTP.Client.TLS as TLS

import Automation.Types (OgMetadata (..), mkTitle)

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
  let body = TE.decodeUtf8Lenient (LBS.toStrict (HTTP.responseBody response))
  pure OgMetadata
    { ogTitle       = extractOgProperty "title" body >>= either (const Nothing) Just . mkTitle
    , ogDescription = extractOgProperty "description" body
    , ogImageUrl    = extractOgProperty "image" body
    }

detectContentType :: Text -> Text
detectContentType imageUrl
  | ".webp" `T.isSuffixOf` lower = "image/webp"
  | ".png"  `T.isSuffixOf` lower = "image/png"
  | ".gif"  `T.isSuffixOf` lower = "image/gif"
  | ".svg"  `T.isSuffixOf` lower = "image/svg+xml"
  | otherwise                     = "image/jpeg"
  where lower = T.toLower (T.takeWhile (\c -> c /= '?' && c /= '#') imageUrl)

fetchImageAsBuffer :: Text -> IO LBS.ByteString
fetchImageAsBuffer url = do
  manager <- TLS.newTlsManager
  request <- HTTP.parseRequest (T.unpack url)
  response <- HTTP.httpLbs request manager
  pure (HTTP.responseBody response)
