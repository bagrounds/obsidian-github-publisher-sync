module Automation.Platforms.Bluesky
  ( extractBlueskyPostId
  , extractBlueskyDid
  , buildBlueskyPostUrl
  , postToBluesky
  , deleteBlueskyPost
  , fetchBlueskyOEmbed
  , generateLocalBlueskyEmbed
  , getBlueskyEmbedHtml
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import qualified Network.HTTP.Client as HTTP
import qualified Network.HTTP.Client.TLS as TLS

import Automation.Types
  ( BlueskyCredentials
  , EmbedResult (..)
  , LinkCard
  )

extractBlueskyPostId :: Text -> Maybe Text
extractBlueskyPostId url =
  case T.splitOn "/post/" url of
    [_, postId] -> Just postId
    _           -> Nothing

extractBlueskyDid :: Text -> Maybe Text
extractBlueskyDid url =
  case T.splitOn "/profile/" url of
    [_, rest] -> case T.splitOn "/post/" rest of
      (did : _) -> Just did
      _         -> Nothing
    _ -> Nothing

buildBlueskyPostUrl :: Text -> Text -> Text
buildBlueskyPostUrl did postId =
  "https://bsky.app/profile/" <> did <> "/post/" <> postId

postToBluesky :: BlueskyCredentials -> Text -> Maybe LinkCard -> IO (Maybe Text)
postToBluesky _creds _text _linkCard = pure Nothing

deleteBlueskyPost :: BlueskyCredentials -> Text -> IO Bool
deleteBlueskyPost _creds _uri = pure False

fetchBlueskyOEmbed :: Text -> IO (Maybe EmbedResult)
fetchBlueskyOEmbed postUrl = do
  manager <- TLS.newTlsManager
  let url = "https://embed.bsky.app/oembed?url=" <> postUrl
  request <- HTTP.parseRequest (T.unpack url)
  _response <- HTTP.httpLbs request manager
  pure Nothing

generateLocalBlueskyEmbed :: Text -> Text -> Text
generateLocalBlueskyEmbed postUrl author =
  "<blockquote class=\"bluesky-embed\"><a href=\""
    <> postUrl
    <> "\">Post by "
    <> author
    <> "</a></blockquote>"

getBlueskyEmbedHtml :: Text -> Text -> IO Text
getBlueskyEmbedHtml postUrl author = do
  result <- fetchBlueskyOEmbed postUrl
  pure $ case result of
    Just (EmbedResult html) -> html
    Nothing                 -> generateLocalBlueskyEmbed postUrl author
