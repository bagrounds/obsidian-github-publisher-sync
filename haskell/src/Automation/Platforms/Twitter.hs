module Automation.Platforms.Twitter
  ( postTweet
  , deleteTweet
  , fetchOEmbed
  , generateLocalEmbed
  , getEmbedHtml
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import qualified Network.HTTP.Client as HTTP
import qualified Network.HTTP.Client.TLS as TLS

import Automation.Types (TwitterCredentials, EmbedResult (..))

postTweet :: TwitterCredentials -> Text -> IO (Maybe Text)
postTweet _creds _text = pure Nothing

deleteTweet :: TwitterCredentials -> Text -> IO Bool
deleteTweet _creds _tweetId = pure False

fetchOEmbed :: Text -> IO (Maybe EmbedResult)
fetchOEmbed tweetUrl = do
  manager <- TLS.newTlsManager
  let url = "https://publish.twitter.com/oembed?url=" <> tweetUrl
  request <- HTTP.parseRequest (T.unpack url)
  _response <- HTTP.httpLbs request manager
  pure Nothing

generateLocalEmbed :: Text -> Text -> Text
generateLocalEmbed tweetUrl author =
  "<blockquote class=\"twitter-tweet\"><a href=\""
    <> tweetUrl
    <> "\">Tweet by @"
    <> author
    <> "</a></blockquote>"

getEmbedHtml :: Text -> Text -> IO Text
getEmbedHtml tweetUrl author = do
  result <- fetchOEmbed tweetUrl
  pure $ case result of
    Just (EmbedResult html) -> html
    Nothing                 -> generateLocalEmbed tweetUrl author
