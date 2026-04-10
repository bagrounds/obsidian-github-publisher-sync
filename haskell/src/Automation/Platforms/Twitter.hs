module Automation.Platforms.Twitter
  ( Credentials (..)
  , PostResult (..)
  , Error (HttpError, JsonParseError, ExtractionError, NetworkError)
  , classifyException
  , parseTweetResponse
  , parseOEmbedHtml
  , limits
  , twitterHandle
  , displayName
  , sectionHeader
  , post
  , deletePost
  , fetchOEmbed
  , generateLocalEmbed
  , getEmbedHtml
  ) where

import Control.Exception (SomeException, fromException, throwIO, try)
import Control.Monad (when)
import Crypto.Hash (SHA1)
import Crypto.MAC.HMAC (HMAC, hmac)
import Data.ByteArray (convert)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Base64 as B64
import qualified Data.ByteString.Lazy as LBS
import Data.Char (intToDigit, toUpper)
import Data.List (sort)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Time.Clock.POSIX (getPOSIXTime)
import Data.Word (Word8)
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

import Automation.Html (formatDisplayDate, textToHtml)
import Automation.Json ((.=), (.:), (.:?), eitherDecode, encode, object, withObject)
import qualified Automation.Json as Json
import Automation.Platform (PlatformLimits (..))
import Automation.Retry (HttpCodeException (HttpCodeException), defaultRetryOptions, withRetry)
import Automation.Secret (Secret (..))

-- | Typed error for Twitter API operations.
-- Structured constructors preserve error context and enable pattern matching
-- for decisions (e.g., checking HTTP status codes) without string inspection.
data Error
  = HttpError Int Text
  | JsonParseError Text
  | ExtractionError Text
  | NetworkError Text
  deriving (Show, Eq)

classifyException :: SomeException -> Error
classifyException exception =
  case fromException @HttpCodeException exception of
    Just (HttpCodeException code message) -> HttpError code (T.pack message)
    Nothing -> NetworkError (T.pack (show exception))

data Credentials = Credentials
  { tcApiKey :: Secret
  , tcApiSecret :: Secret
  , tcAccessToken :: Secret
  , tcAccessSecret :: Secret
  } deriving (Show, Eq)

data PostResult = PostResult
  { trId :: Text
  , trText :: Text
  } deriving (Show, Eq)

-- ── Platform constants ─────────────────────────────────────────────────

limits :: PlatformLimits
limits = PlatformLimits
  { platformMaxCharacters = 280
  , platformUrlCountLength = Just 23
  }

twitterHandle :: Text
twitterHandle = "bagrounds"

displayName :: Text
displayName = "Bryan Grounds"

sectionHeader :: Text
sectionHeader = "## 🐦 Tweet"

-- ── Constants ──────────────────────────────────────────────────────────

tweetsApiUrl :: Text
tweetsApiUrl = "https://api.twitter.com/2/tweets"

oembedBaseUrl :: String
oembedBaseUrl = "https://publish.twitter.com/oembed"

-- ── OAuth 1.0a (RFC 5849) ─────────────────────────────────────────────

percentEncode :: Text -> Text
percentEncode = T.pack . concatMap encodeByte . BS.unpack . TE.encodeUtf8
  where
    encodeByte :: Word8 -> String
    encodeByte w
      | isUnreserved w = [toEnum (fromIntegral w)]
      | otherwise = ['%', hexUpper (w `div` 16), hexUpper (w `mod` 16)]
    isUnreserved :: Word8 -> Bool
    isUnreserved w =
      (w >= 0x41 && w <= 0x5A)
        || (w >= 0x61 && w <= 0x7A)
        || (w >= 0x30 && w <= 0x39)
        || w == 0x2D
        || w == 0x2E
        || w == 0x5F
        || w == 0x7E
    hexUpper :: Word8 -> Char
    hexUpper = toUpper . intToDigit . fromIntegral

hmacSHA1 :: BS.ByteString -> BS.ByteString -> BS.ByteString
hmacSHA1 key msg = convert (hmac key msg :: HMAC SHA1)

generateNonce :: IO Text
generateNonce = T.pack <$> traverse (const randomAlphaNum) [1 :: Int .. 32]
  where
    chars :: String
    chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    randomAlphaNum :: IO Char
    randomAlphaNum = (chars !!) <$> randomRIO (0, length chars - 1)

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

buildOAuthHeader :: Credentials -> Text -> Text -> IO Text
buildOAuthHeader Credentials {..} httpMethod baseUrl = do
  timestamp <- T.pack . show . (floor @Double @Integer) . realToFrac <$> getPOSIXTime
  nonce <- generateNonce
  let oauthParams =
        [ ("oauth_consumer_key", unSecret tcApiKey)
        , ("oauth_nonce", nonce)
        , ("oauth_signature_method", "HMAC-SHA1")
        , ("oauth_timestamp", timestamp)
        , ("oauth_token", unSecret tcAccessToken)
        , ("oauth_version", "1.0")
        ]
      paramString =
        T.intercalate "&" $
          fmap (\(k, v) -> percentEncode k <> "=" <> percentEncode v) (sort oauthParams)
      signatureBase =
        httpMethod <> "&" <> percentEncode baseUrl <> "&" <> percentEncode paramString
      signingKey =
        TE.encodeUtf8 $ percentEncode (unSecret tcApiSecret) <> "&" <> percentEncode (unSecret tcAccessSecret)
      signature =
        TE.decodeUtf8 $ B64.encode $ hmacSHA1 signingKey (TE.encodeUtf8 signatureBase)
      allParams = sort $ ("oauth_signature", signature) : oauthParams
      headerParts =
        fmap (\(k, v) -> percentEncode k <> "=\"" <> percentEncode v <> "\"") allParams
  pure $ "OAuth " <> T.intercalate ", " headerParts

-- ── Posting ────────────────────────────────────────────────────────────

post :: Manager -> Credentials -> Text -> IO (Either Error (Text, Text))
post manager creds tweetText = do
  idempotencyKey <- generateUUID
  let bodyJson = encode (object ["text" .= tweetText])
  result <- try @SomeException $ withRetry defaultRetryOptions $ do
    authHeader <- buildOAuthHeader creds "POST" tweetsApiUrl
    initialReq <- parseRequest (T.unpack tweetsApiUrl)
    let req =
          initialReq
            { method = "POST"
            , requestBody = RequestBodyLBS bodyJson
            , requestHeaders =
                [ ("Authorization", TE.encodeUtf8 authHeader)
                , ("Content-Type", "application/json")
                , ("X-Idempotency-Key", TE.encodeUtf8 idempotencyKey)
                ]
            }
    response <- httpLbs req manager
    let status = statusCode (responseStatus response)
    when (status < 200 || status >= 300) $
      throwIO $
        HttpCodeException status ("Twitter API error: " <> show status)
    pure (responseBody response)
  pure $ case result of
    Left err -> Left (classifyException err)
    Right body -> parseTweetResponse tweetText body

parseTweetResponse :: Text -> LBS.ByteString -> Either Error (Text, Text)
parseTweetResponse fallbackText body =
  case eitherDecode @Json.Value body of
    Left err -> Left (JsonParseError (T.pack err))
    Right val -> case extractTweetData fallbackText val of
      Left err -> Left (ExtractionError (T.pack err))
      Right r -> Right r

extractTweetData :: Text -> Json.Value -> Either String (Text, Text)
extractTweetData fallbackText = withObject "tweet response" $ \obj -> do
  dataVal <- obj .: "data"
  withObject "tweet data"
    ( \dataObj -> do
        tweetId <- dataObj .: "id"
        mTweetTxt <- dataObj .:? "text"
        pure (tweetId, fromMaybe fallbackText mTweetTxt)
    )
    dataVal

-- ── Deleting ───────────────────────────────────────────────────────────

deletePost :: Manager -> Credentials -> Text -> IO (Either Error ())
deletePost manager creds tweetId = do
  let url = tweetsApiUrl <> "/" <> tweetId
  result <- try @SomeException $ do
    authHeader <- buildOAuthHeader creds "DELETE" url
    initialReq <- parseRequest (T.unpack url)
    let req =
          initialReq
            { method = "DELETE"
            , requestHeaders =
                [("Authorization", TE.encodeUtf8 authHeader)]
            }
    response <- httpLbs req manager
    let status = statusCode (responseStatus response)
    when (status < 200 || status >= 300) $
      throwIO $
        HttpCodeException status ("Twitter delete error: " <> show status)
  pure $ case result of
    Left err -> Left (classifyException err)
    Right () -> Right ()

-- ── Embed HTML ─────────────────────────────────────────────────────────

fetchOEmbed :: Manager -> Text -> IO (Either Error Text)
fetchOEmbed manager tweetUrl = do
  let url =
        oembedBaseUrl
          <> "?url="
          <> T.unpack (percentEncode tweetUrl)
          <> "&theme=dark&omit_script=false"
  result <- try @SomeException $ do
    request <- parseRequest url
    response <- httpLbs request manager
    let status = statusCode (responseStatus response)
    when (status < 200 || status >= 300) $
      throwIO $
        HttpCodeException status ("oEmbed API returned " <> show status)
    pure (responseBody response)
  pure $ case result of
    Left err -> Left (classifyException err)
    Right body -> parseOEmbedHtml body

parseOEmbedHtml :: LBS.ByteString -> Either Error Text
parseOEmbedHtml body =
  case eitherDecode @Json.Value body of
    Left err -> Left (JsonParseError (T.pack err))
    Right val -> case withObject "oembed" (.: "html") val of
      Left err -> Left (ExtractionError (T.pack err))
      Right html -> Right html

generateLocalEmbed :: Text -> Text -> Text -> Text -> Text
generateLocalEmbed tweetId tweetText date handle =
  let htmlText = textToHtml tweetText
      displayDate = formatDisplayDate date
  in "<blockquote class=\"twitter-tweet\" data-theme=\"dark\">"
       <> "<p lang=\"en\" dir=\"ltr\">"
       <> htmlText
       <> "</p>"
       <> "&mdash; "
       <> displayName
       <> " (@"
       <> handle
       <> ") "
       <> "<a href=\"https://twitter.com/"
       <> handle
       <> "/status/"
       <> tweetId
       <> "?ref_src=twsrc%5Etfw\">"
       <> displayDate
       <> "</a>"
       <> "</blockquote> "
       <> "<script async src=\"https://platform.twitter.com/widgets.js\" charset=\"utf-8\"></script>"

getEmbedHtml :: Manager -> Text -> Text -> Text -> Text -> IO Text
getEmbedHtml manager tweetId tweetText date handle = do
  let tweetUrl = "https://twitter.com/" <> handle <> "/status/" <> tweetId
  result <- fetchOEmbed manager tweetUrl
  pure $ case result of
    Right html -> html
    Left _ -> generateLocalEmbed tweetId tweetText date handle
