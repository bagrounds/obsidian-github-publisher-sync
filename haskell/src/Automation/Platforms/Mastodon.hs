module Automation.Platforms.Mastodon
  ( Credentials (..)
  , PostResult (..)
  , Error (HttpError, JsonParseError, ExtractionError, NetworkError)
  , classifyException
  , parseMastodonResponse
  , parseOEmbedHtml
  , limits
  , displayName
  , sectionHeader
  , extractInstanceUrl
  , extractStatusId
  , extractUsername
  , toDarkMode
  , needsDarkModeUpdate
  , needsEmbedRegeneration
  , extractRegenerationUrl
  , replaceSectionContent
  , post
  , deletePost
  , fetchOEmbed
  , generateLocalEmbed
  , getEmbedHtml
  ) where

import Control.Applicative ((<|>))
import Control.Exception (SomeException, fromException, throwIO, try)
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
import Automation.Platform (PlatformLimits (..))
import Automation.Retry (HttpCodeException (HttpCodeException), defaultRetryOptions, withRetry)
import Automation.Secret (Secret (..))
import Automation.Url (Url, unUrl, mkUrl)

-- | Typed error for Mastodon API operations.
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
  { instanceUrl :: Url
  , accessToken :: Secret
  } deriving (Show, Eq)

data PostResult = PostResult
  { postId :: Text
  , url :: Url
  , content :: Text
  } deriving (Show, Eq)

limits :: PlatformLimits
limits = PlatformLimits
  { platformMaxCharacters = 500
  , platformUrlCountLength = Nothing
  }

displayName :: Text
displayName = "Bryan Grounds"

sectionHeader :: Text
sectionHeader = "## 🐘 Mastodon"

extractInstanceUrl :: Text -> Maybe Text
extractInstanceUrl url =
  case T.splitOn "/@" url of
    (instanceUrl : _) -> Just instanceUrl
    _                 -> Nothing

extractStatusId :: Text -> Maybe Text
extractStatusId url =
  let parts = T.splitOn "/" url
  in case reverse parts of
    (statusId : _) -> Just statusId
    _              -> Nothing

extractUsername :: Text -> Maybe Text
extractUsername url =
  case T.splitOn "/@" url of
    (_ : rest) -> case T.splitOn "/" (T.intercalate "/@" rest) of
      (username : _) -> Just username
      _              -> Nothing
    _ -> Nothing

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

post :: Manager -> Credentials -> Text -> IO (Either Error PostResult)
post manager Credentials{..} statusText = do
  idempotencyKey <- generateUUID
  let apiUrl = unUrl instanceUrl <> "/api/v1/statuses"
      bodyJson = encode (object
        [ "status"     .= statusText
        , "visibility" .= ("public" :: Text)
        , "language"   .= ("en" :: Text)
        ])
  result <- try @SomeException $ withRetry defaultRetryOptions $ do
    initialRequest <- parseRequest (T.unpack apiUrl)
    let req =
          initialRequest
            { method = "POST"
            , requestBody = RequestBodyLBS bodyJson
            , requestHeaders =
                [ ("Authorization", "Bearer " <> TE.encodeUtf8 (unSecret accessToken))
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
    Left err -> Left (classifyException err)
    Right body -> parseMastodonResponse statusText body

parseMastodonResponse :: Text -> LBS.ByteString -> Either Error PostResult
parseMastodonResponse fallbackText body =
  case eitherDecode @Json.Value body of
    Left err -> Left (JsonParseError (T.pack err))
    Right jsonValue -> case extractMastodonData fallbackText jsonValue of
      Left err -> Left (ExtractionError (T.pack err))
      Right r -> Right r

extractMastodonData :: Text -> Json.Value -> Either String PostResult
extractMastodonData fallbackText = withObject "mastodon response" $ \obj -> do
  statusId <- obj .: "id"
  statusUrl <- obj .: "url"
  case mkUrl statusUrl of
    Right url -> pure PostResult
      { postId = statusId
      , url = url
      , content = fallbackText
      }
    Left err -> Left (T.unpack err)

deletePost :: Manager -> Credentials -> Text -> IO (Either Error ())
deletePost manager Credentials{..} statusId = do
  let apiUrl = unUrl instanceUrl <> "/api/v1/statuses/" <> statusId
  result <- try @SomeException $ do
    initialRequest <- parseRequest (T.unpack apiUrl)
    let req =
          initialRequest
            { method = "DELETE"
            , requestHeaders =
                [("Authorization", "Bearer " <> TE.encodeUtf8 (unSecret accessToken))]
            }
    response <- httpLbs req manager
    let status = statusCode (responseStatus response)
    when (status < 200 || status >= 300) $
      throwIO $
        HttpCodeException status ("Mastodon delete error: " <> show status)
  pure $ case result of
    Left err -> Left (classifyException err)
    Right () -> Right ()

fetchOEmbed :: Manager -> Text -> Text -> IO (Either Error Text)
fetchOEmbed manager instanceUrl statusUrl = do
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
    Left err -> Left (classifyException err)
    Right body -> fmap toDarkMode (parseOEmbedHtml body)

parseOEmbedHtml :: LBS.ByteString -> Either Error Text
parseOEmbedHtml body =
  case eitherDecode @Json.Value body of
    Left err -> Left (JsonParseError (T.pack err))
    Right jsonValue -> case withObject "oembed" (.: "html") jsonValue of
      Left err -> Left (ExtractionError (T.pack err))
      Right html -> Right html

toDarkMode :: Text -> Text
toDarkMode = replaceLightColors

replaceLightColors :: Text -> Text
replaceLightColors =
    T.replace "background: #FCF8FF" "background: #282c37"
  . T.replace "border: 1px solid #C9C4DA" "border: 1px solid #393f4f"
  . T.replace "color: #1C1A25" "color: #d9e1e8"
  . T.replace "color: #787588" "color: #9baec8"

needsDarkModeUpdate :: Text -> Bool
needsDarkModeUpdate section =
  "mastodon-embed" `T.isInfixOf` section
    && ("background: #FCF8FF" `T.isInfixOf` section
         || "color: #1C1A25" `T.isInfixOf` section)

needsEmbedRegeneration :: Text -> Bool
needsEmbedRegeneration = needsDarkModeUpdate

extractRegenerationUrl :: Text -> Maybe Text
extractRegenerationUrl section
  | needsDarkModeUpdate section = extractEmbedUrl section
  | otherwise = Nothing

extractEmbedUrl :: Text -> Maybe Text
extractEmbedUrl section =
  extractFromDataAttribute section <|> extractFromHref section

extractFromDataAttribute :: Text -> Maybe Text
extractFromDataAttribute section =
  case T.breakOn "data-embed-url=\"" section of
    (_, rest) | not (T.null rest) ->
      let afterAttr = T.drop (T.length "data-embed-url=\"") rest
          embedUrl = T.takeWhile (/= '"') afterAttr
      in Just (T.replace "/embed" "" embedUrl)
    _ -> Nothing

extractFromHref :: Text -> Maybe Text
extractFromHref section =
  case T.breakOn "<a href=\"" section of
    (_, rest) | not (T.null rest) ->
      let afterHref = T.drop (T.length "<a href=\"") rest
          hrefUrl = T.takeWhile (/= '"') afterHref
      in Just hrefUrl
    _ -> Nothing

replaceSectionContent :: Text -> Text -> Text
replaceSectionContent fileContent newEmbedHtml =
  T.unlines (replaceLinesAfterHeader sectionHeader newEmbedHtml (T.lines fileContent))

replaceLinesAfterHeader :: Text -> Text -> [Text] -> [Text]
replaceLinesAfterHeader _ _ [] = []
replaceLinesAfterHeader header newContent (line : rest)
  | header `T.isPrefixOf` T.stripEnd line =
      let (_, remaining) = spanSection rest
      in line : T.stripEnd newContent : remaining
  | otherwise = line : replaceLinesAfterHeader header newContent rest

spanSection :: [Text] -> ([Text], [Text])
spanSection [] = ([], [])
spanSection (line : rest)
  | "## " `T.isPrefixOf` T.stripStart line = ([], line : rest)
  | otherwise =
      let (sectionRest, remaining) = spanSection rest
      in (line : sectionRest, remaining)

generateLocalEmbed :: Text -> Text
generateLocalEmbed postUrl =
  let instanceUrl = fromMaybe "" (extractInstanceUrl postUrl)
  in "<iframe src=\""
       <> postUrl
       <> "/embed\" class=\"mastodon-embed\" "
       <> "style=\"max-width: 100%; border: 0\" width=\"400\" "
       <> "allowfullscreen=\"allowfullscreen\"></iframe>"
       <> "<script src=\""
       <> instanceUrl
       <> "/embed.js\" async=\"async\"></script>"

getEmbedHtml :: Manager -> Text -> Text -> Text -> IO Text
getEmbedHtml manager postUrl _postText _date = do
  let instanceUrl = fromMaybe "" (extractInstanceUrl postUrl)
  result <- fetchOEmbed manager instanceUrl postUrl
  pure $ case result of
    Right html -> html
    Left _     -> generateLocalEmbed postUrl
