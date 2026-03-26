module Automation.Platforms.Mastodon
  ( extractMastodonInstanceUrl
  , extractMastodonStatusId
  , extractMastodonUsername
  , postToMastodon
  , deleteMastodonPost
  , fetchMastodonOEmbed
  , generateLocalMastodonEmbed
  , getMastodonEmbedHtml
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import qualified Network.HTTP.Client as HTTP
import qualified Network.HTTP.Client.TLS as TLS

import Automation.Types (MastodonCredentials, EmbedResult (..))

extractMastodonInstanceUrl :: Text -> Maybe Text
extractMastodonInstanceUrl url =
  case T.splitOn "/@" url of
    (instanceUrl : _) -> Just instanceUrl
    _                 -> Nothing

extractMastodonStatusId :: Text -> Maybe Text
extractMastodonStatusId url =
  let parts = T.splitOn "/" url
  in case reverse parts of
    (statusId : _) -> Just statusId
    _              -> Nothing

extractMastodonUsername :: Text -> Maybe Text
extractMastodonUsername url =
  case T.splitOn "/@" url of
    (_ : rest) -> case T.splitOn "/" (T.intercalate "/@" rest) of
      (username : _) -> Just username
      _              -> Nothing
    _ -> Nothing

postToMastodon :: MastodonCredentials -> Text -> IO (Maybe Text)
postToMastodon _creds _text = pure Nothing

deleteMastodonPost :: MastodonCredentials -> Text -> IO Bool
deleteMastodonPost _creds _statusId = pure False

fetchMastodonOEmbed :: Text -> Text -> IO (Maybe EmbedResult)
fetchMastodonOEmbed instanceUrl statusUrl = do
  manager <- TLS.newTlsManager
  let url = instanceUrl <> "/api/oembed?url=" <> statusUrl
  request <- HTTP.parseRequest (T.unpack url)
  _response <- HTTP.httpLbs request manager
  pure Nothing

generateLocalMastodonEmbed :: Text -> Text -> Text
generateLocalMastodonEmbed statusUrl author =
  "<blockquote class=\"mastodon-embed\"><a href=\""
    <> statusUrl
    <> "\">Post by @"
    <> author
    <> "</a></blockquote>"

getMastodonEmbedHtml :: Text -> Text -> Text -> IO Text
getMastodonEmbedHtml instanceUrl statusUrl author = do
  result <- fetchMastodonOEmbed instanceUrl statusUrl
  pure $ case result of
    Just (EmbedResult html) -> html
    Nothing                 -> generateLocalMastodonEmbed statusUrl author
