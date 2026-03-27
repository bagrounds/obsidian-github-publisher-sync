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

import Control.Exception (SomeException, throwIO, try)
import Control.Monad (when)
import Data.Char (intToDigit)
import Data.Maybe (fromMaybe)
import qualified Data.ByteString.Lazy as LBS
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Network.HTTP.Client
  ( Manager
  , Request (..)
  , RequestBody (..)
  , httpLbs
  , parseRequest
  , responseBody
  , responseStatus
  )
import Network.HTTP.Types.Status (statusCode)
import System.Random (randomRIO)

import Automation.Json ((.=), (.:), eitherDecode, encode, object, withObject)
import qualified Automation.Json as Json
import Automation.Retry (HttpCodeException (..), defaultRetryOptions, withRetry)
import Automation.Types (MastodonCredentials (..), MastodonPostResult (..))

-- ── URL Parsing ────────────────────────────────────────────────────────

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

-- ── UUID Generation ────────────────────────────────────────────────────

generateUUID :: IO Text
generateUUID = do
  bytes <- traverse (const (randomRIO @Int (0, 255))) [1 :: Int .. 16]
  let adjusted = zipWith adjust [0 :: Int ..] bytes
      hex = concatMap toHex adjusted
  pure $
    T.pack $
      take 8 hex
        <> "-"
        <> take 4 (drop 8 hex)
        <> "-"
        <> take 4 (drop 12 hex)
        <> "-"
        <> take 4 (drop 16 hex)
        <> "-"
        <> drop 20 hex
  where
    adjust :: Int -> Int -> Int
    adjust 6 b = (b `mod` 16) + 0x40
    adjust 8 b = (b `mod` 64) + 0x80
    adjust _ b = b
    toHex :: Int -> String
    toHex b = [intToDigit (b `div` 16), intToDigit (b `mod` 16)]

-- ── Posting ────────────────────────────────────────────────────────────

postToMastodon :: Manager -> MastodonCredentials -> Text -> IO (Either Text MastodonPostResult)
postToMastodon manager MastodonCredentials{..} statusText = do
  idempotencyKey <- generateUUID
  let apiUrl = mcInstanceUrl <> "/api/v1/statuses"
      bodyJson = encode (object
        [ "status"     .= statusText
        , "visibility" .= ("public" :: Text)
        , "language"   .= ("en" :: Text)
        ])
  result <- try @SomeException $ withRetry defaultRetryOptions $ do
    initialReq <- parseRequest (T.unpack apiUrl)
    let req =
          initialReq
            { method = "POST"
            , requestBody = RequestBodyLBS bodyJson
            , requestHeaders =
                [ ("Authorization", "Bearer " <> TE.encodeUtf8 mcAccessToken)
                , ("Content-Type", "application/json")
                , ("Idempotency-Key", TE.encodeUtf8 idempotencyKey)
                ]
            }
    response <- httpLbs req manager
    let status = statusCode (responseStatus response)
    when (status < 200 || status >= 300) $
      throwIO $
        HttpCodeException status ("Mastodon API error: " <> show status)
    pure (responseBody response)
  pure $ case result of
    Left err -> Left (T.pack (show err))
    Right body -> parseMastodonResponse statusText body

parseMastodonResponse :: Text -> LBS.ByteString -> Either Text MastodonPostResult
parseMastodonResponse fallbackText body =
  case eitherDecode @Json.Value body of
    Left err -> Left (T.pack err)
    Right val -> case extractMastodonData fallbackText val of
      Left err -> Left (T.pack err)
      Right r -> Right r

extractMastodonData :: Text -> Json.Value -> Either String MastodonPostResult
extractMastodonData fallbackText = withObject "mastodon response" $ \obj -> do
  statusId <- obj .: "id"
  statusUrl <- obj .: "url"
  pure MastodonPostResult
    { mprId = statusId
    , mprUrl = statusUrl
    , mprText = fallbackText
    }

-- ── Deleting ───────────────────────────────────────────────────────────

deleteMastodonPost :: Manager -> MastodonCredentials -> Text -> IO (Either Text ())
deleteMastodonPost manager MastodonCredentials{..} statusId = do
  let apiUrl = mcInstanceUrl <> "/api/v1/statuses/" <> statusId
  result <- try @SomeException $ do
    initialReq <- parseRequest (T.unpack apiUrl)
    let req =
          initialReq
            { method = "DELETE"
            , requestHeaders =
                [("Authorization", "Bearer " <> TE.encodeUtf8 mcAccessToken)]
            }
    response <- httpLbs req manager
    let status = statusCode (responseStatus response)
    when (status < 200 || status >= 300) $
      throwIO $
        HttpCodeException status ("Mastodon delete error: " <> show status)
  pure $ case result of
    Left err -> Left (T.pack (show err))
    Right () -> Right ()

-- ── Embed HTML ─────────────────────────────────────────────────────────

fetchMastodonOEmbed :: Manager -> Text -> Text -> IO (Either Text Text)
fetchMastodonOEmbed manager instanceUrl statusUrl = do
  let url = T.unpack instanceUrl <> "/api/oembed?url=" <> T.unpack statusUrl
  result <- try @SomeException $ do
    request <- parseRequest url
    response <- httpLbs request manager
    let status = statusCode (responseStatus response)
    when (status < 200 || status >= 300) $
      throwIO $
        HttpCodeException status ("Mastodon oEmbed API returned " <> show status)
    pure (responseBody response)
  pure $ case result of
    Left err -> Left (T.pack (show err))
    Right body -> parseOEmbedHtml body

parseOEmbedHtml :: LBS.ByteString -> Either Text Text
parseOEmbedHtml body =
  case eitherDecode @Json.Value body of
    Left err -> Left (T.pack err)
    Right val -> case withObject "oembed" (\obj -> obj .: "html") val of
      Left err -> Left (T.pack err)
      Right html -> Right html

generateLocalMastodonEmbed :: Text -> Text
generateLocalMastodonEmbed postUrl =
  let instanceUrl = fromMaybe "" (extractMastodonInstanceUrl postUrl)
  in "<iframe src=\""
       <> postUrl
       <> "/embed\" class=\"mastodon-embed\" "
       <> "style=\"max-width: 100%; border: 0\" width=\"400\" "
       <> "allowfullscreen=\"allowfullscreen\"></iframe>"
       <> "<script src=\""
       <> instanceUrl
       <> "/embed.js\" async=\"async\"></script>"

getMastodonEmbedHtml :: Manager -> Text -> Text -> Text -> IO Text
getMastodonEmbedHtml manager postUrl _postText _date = do
  let instanceUrl = fromMaybe "" (extractMastodonInstanceUrl postUrl)
  result <- fetchMastodonOEmbed manager instanceUrl postUrl
  pure $ case result of
    Right html -> html
    Left _     -> generateLocalMastodonEmbed postUrl
