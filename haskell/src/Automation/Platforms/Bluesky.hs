module Automation.Platforms.Bluesky
  ( Credentials (..)
  , PostResult (..)
  , EmbedResult (..)
  , LinkCard (..)
  , Error (HttpError, JsonParseError, ExtractionError, NetworkError)
  , classifyException
  , parseSession
  , parsePostResponse
  , parseOEmbedHtml
  , limits
  , displayName
  , sectionHeader
  , oembedInitialDelayMs
  , oembedRetryDelayMs
  , oembedMaxAttempts
  , extractPostId
  , extractDid
  , buildPostUrl
  , buildPlaceholderLink
  , isPlaceholderLink
  , replacePlaceholderWithEmbed
  , post
  , deletePost
  , fetchOEmbed
  , generateLocalEmbed
  , getEmbedHtml
  ) where

import Control.Concurrent (threadDelay)
import Control.Exception (SomeException, fromException, throwIO, try)
import Control.Monad (when)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Time.Clock (getCurrentTime)
import Data.Time.Format (defaultTimeLocale, formatTime)
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

import Automation.Html (formatDisplayDate, textToHtml)
import qualified Automation.Json as Json
import Automation.Json ((.=), (.:), encode, eitherDecode, object, withObject)
import Automation.Platform (PlatformLimits (..))
import Automation.Platforms.OgMetadata (detectContentType, fetchImageAsBuffer)
import Automation.Retry (HttpCodeException (HttpCodeException), defaultRetryOptions, withRetry)
import Automation.Secret (Secret (..))
import Automation.Title (Title, unTitle)
import Automation.Url (Url, unUrl)

-- ── Domain types ───────────────────────────────────────────────────────

-- | Typed error for Bluesky API operations.
-- Structured constructors preserve error context and enable pattern matching
-- for decisions (e.g., retrying on HTTP 404) without string inspection.
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
  { bcIdentifier :: Text
  , bcPassword :: Secret
  } deriving (Show, Eq)

data PostResult = PostResult
  { bprUri :: Text
  , bprCid :: Text
  , bprText :: Text
  } deriving (Show, Eq)

newtype EmbedResult = EmbedResult
  { erHtml :: Text
  } deriving (Show, Eq)

data LinkCard = LinkCard
  { lcUri :: Url
  , lcTitle :: Title
  , lcDescription :: Text
  , lcThumbUrl :: Maybe Text
  } deriving (Show, Eq)

-- ── Platform constants ─────────────────────────────────────────────────

limits :: PlatformLimits
limits = PlatformLimits
  { platformMaxCharacters = 300
  , platformUrlCountLength = Nothing
  }

displayName :: Text
displayName = "Bryan Grounds"

sectionHeader :: Text
sectionHeader = "## 🦋 Bluesky"

oembedInitialDelayMs :: Int
oembedInitialDelayMs = 3000

oembedRetryDelayMs :: Int
oembedRetryDelayMs = 3000

oembedMaxAttempts :: Int
oembedMaxAttempts = 3

-- ── Constants ──────────────────────────────────────────────────────────

atpBaseUrl :: Text
atpBaseUrl = "https://bsky.social/xrpc/"

oembedBaseUrl :: Text
oembedBaseUrl = "https://embed.bsky.app/oembed"

-- ── AT Protocol Session ────────────────────────────────────────────────

data AtpSession = AtpSession
  { asDid         :: Text
  , asAccessToken :: Text
  }

createSession :: Manager -> Credentials -> IO (Either Error AtpSession)
createSession manager Credentials{..} = do
  let url = T.unpack (atpBaseUrl <> "com.atproto.server.createSession")
      bodyJson = encode (object
        [ "identifier" .= bcIdentifier
        , "password" .= unSecret bcPassword
        ])
  result <- try @SomeException $ withRetry defaultRetryOptions $ do
    initialReq <- parseRequest url
    let req = initialReq
          { method = "POST"
          , requestBody = RequestBodyLBS bodyJson
          , requestHeaders = [("Content-Type", "application/json")]
          }
    response <- httpLbs req manager
    let status = statusCode (responseStatus response)
    when (status < 200 || status >= 300) $
      throwIO $ HttpCodeException status ("Bluesky login error: " <> show status)
    pure (responseBody response)
  pure $ case result of
    Left err   -> Left (classifyException err)
    Right body -> parseSession body

parseSession :: LBS.ByteString -> Either Error AtpSession
parseSession body =
  case eitherDecode @Json.Value body of
    Left err  -> Left (JsonParseError (T.pack err))
    Right val -> case extractSession val of
      Left err  -> Left (ExtractionError (T.pack err))
      Right s   -> Right s

extractSession :: Json.Value -> Either String AtpSession
extractSession = withObject "session response" $ \obj -> do
  did <- obj .: "did"
  token <- obj .: "accessJwt"
  pure AtpSession { asDid = did, asAccessToken = token }

-- ── URL Extraction (Pure) ──────────────────────────────────────────────

extractPostId :: Text -> Maybe Text
extractPostId uri =
  case T.splitOn "/" uri of
    parts | not (null parts) -> Just (last parts)
    _                        -> Nothing

extractDid :: Text -> Maybe Text
extractDid uri =
  case T.breakOn "did:" uri of
    (_, rest) | not (T.null rest) ->
      Just (T.takeWhile (\c -> c /= '/' && c /= '"' && c /= ' ') rest)
    _ -> case T.splitOn "/profile/" uri of
      [_, rest'] -> case T.splitOn "/post/" rest' of
        (did : _) -> Just did
        _         -> Nothing
      _ -> Nothing

buildPostUrl :: Text -> Text -> Text
buildPostUrl did postId =
  "https://bsky.app/profile/" <> did <> "/post/" <> postId

-- ── Facet Detection ────────────────────────────────────────────────────

data Facet = Facet
  { facetStart :: Int
  , facetEnd   :: Int
  , facetType  :: FacetType
  }

data FacetType
  = FacetLink Text
  | FacetMention Text

encodeFacet :: Facet -> Json.Value
encodeFacet Facet{..} =
  object
    [ "index" .= object
        [ "byteStart" .= facetStart
        , "byteEnd" .= facetEnd
        ]
    , "features" .= [encodeFeature facetType]
    ]

encodeFeature :: FacetType -> Json.Value
encodeFeature (FacetLink uri) =
  object
    [ "$type" .= ("app.bsky.richtext.facet#link" :: Text)
    , "uri" .= uri
    ]
encodeFeature (FacetMention did) =
  object
    [ "$type" .= ("app.bsky.richtext.facet#mention" :: Text)
    , "did" .= did
    ]

detectLinkFacets :: Text -> [Facet]
detectLinkFacets txt =
  let encoded = TE.encodeUtf8 txt
      tokens = T.words txt
  in foldTokens encoded 0 tokens

foldTokens :: BS.ByteString -> Int -> [Text] -> [Facet]
foldTokens _ _ [] = []
foldTokens fullEncoded pos (token : rest) =
  let tokenBytes = TE.encodeUtf8 token
      tokenLen = BS.length tokenBytes
      spaceLen = if null rest then 0 else 1
      facets = [Facet pos (pos + tokenLen) (FacetLink (normalizeUrl token)) | isUrl token]
  in facets <> foldTokens fullEncoded (pos + tokenLen + spaceLen) rest

isUrl :: Text -> Bool
isUrl t = T.isPrefixOf "http://" t || T.isPrefixOf "https://" t

normalizeUrl :: Text -> Text
normalizeUrl t
  | T.isPrefixOf "http://" t || T.isPrefixOf "https://" t = t
  | otherwise = "https://" <> t

-- ── Blob Upload ────────────────────────────────────────────────────────

uploadBlob :: Manager -> AtpSession -> BS.ByteString -> LBS.ByteString -> IO (Either Error Json.Value)
uploadBlob manager AtpSession{..} contentType imageData = do
  let url = T.unpack (atpBaseUrl <> "com.atproto.repo.uploadBlob")
  result <- try @SomeException $ withRetry defaultRetryOptions $ do
    initialReq <- parseRequest url
    let req = initialReq
          { method = "POST"
          , requestBody = RequestBodyLBS imageData
          , requestHeaders =
              [ ("Authorization", "Bearer " <> TE.encodeUtf8 asAccessToken)
              , ("Content-Type", contentType)
              ]
          }
    response <- httpLbs req manager
    let status = statusCode (responseStatus response)
    when (status < 200 || status >= 300) $
      throwIO $ HttpCodeException status ("Bluesky blob upload error: " <> show status)
    pure (responseBody response)
  pure $ case result of
    Left err   -> Left (classifyException err)
    Right body -> case eitherDecode @Json.Value body of
      Left err  -> Left (JsonParseError (T.pack err))
      Right val -> case withObject "blob response" (.: "blob") val of
        Left err   -> Left (ExtractionError (T.pack err))
        Right blob -> Right blob

-- ── Posting ────────────────────────────────────────────────────────────

post
  :: Manager
  -> Credentials
  -> Text
  -> Maybe LinkCard
  -> IO (Either Error PostResult)
post manager creds postText maybeLinkCard = do
  sessionResult <- createSession manager creds
  case sessionResult of
    Left err -> pure (Left err)
    Right session -> createPost manager session postText maybeLinkCard

createPost
  :: Manager
  -> AtpSession
  -> Text
  -> Maybe LinkCard
  -> IO (Either Error PostResult)
createPost manager session@AtpSession{..} postText maybeLinkCard = do
  now <- getCurrentTime
  let createdAt = T.pack (formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%S.000Z" now)
      facets = detectLinkFacets postText
      facetValues = Json.Array (fmap encodeFacet facets)
  embedResult <- buildEmbed manager session maybeLinkCard
  case embedResult of
    Left err -> pure (Left err)
    Right maybeEmbed -> do
      let baseRecord =
            [ "$type" .= ("app.bsky.feed.post" :: Text)
            , "text" .= postText
            , "createdAt" .= createdAt
            , "facets" .= facetValues
            ]
          record = case maybeEmbed of
            Nothing    -> object baseRecord
            Just embed -> object (baseRecord <> ["embed" .= embed])
          bodyJson = encode (object
            [ "repo" .= asDid
            , "collection" .= ("app.bsky.feed.post" :: Text)
            , "record" .= record
            ])
          url = T.unpack (atpBaseUrl <> "com.atproto.repo.createRecord")
      result <- try @SomeException $ withRetry defaultRetryOptions $ do
        initialReq <- parseRequest url
        let req = initialReq
              { method = "POST"
              , requestBody = RequestBodyLBS bodyJson
              , requestHeaders =
                  [ ("Authorization", "Bearer " <> TE.encodeUtf8 asAccessToken)
                  , ("Content-Type", "application/json")
                  ]
              }
        response <- httpLbs req manager
        let status = statusCode (responseStatus response)
        when (status < 200 || status >= 300) $
          throwIO $ HttpCodeException status ("Bluesky create post error: " <> show status)
        pure (responseBody response)
      pure $ case result of
        Left err   -> Left (classifyException err)
        Right body -> parsePostResponse postText body

buildEmbed
  :: Manager
  -> AtpSession
  -> Maybe LinkCard
  -> IO (Either Error (Maybe Json.Value))
buildEmbed _ _ Nothing = pure (Right Nothing)
buildEmbed manager session (Just LinkCard{..}) = do
  thumbResult <- case lcThumbUrl of
    Nothing       -> pure (Right Nothing)
    Just thumbUrl -> do
      imageData <- fetchImageAsBuffer thumbUrl
      let mimeType = TE.encodeUtf8 (detectContentType thumbUrl)
      blobResult <- uploadBlob manager session mimeType imageData
      pure (fmap Just blobResult)
  pure $ case thumbResult of
    Left err -> Left err
    Right maybeBlob ->
      let externalFields =
            [ "uri" .= unUrl lcUri
            , "title" .= unTitle lcTitle
            , "description" .= lcDescription
            ] <> maybe [] (\blob -> ["thumb" .= blob]) maybeBlob
      in Right $ Just $ object
            [ "$type" .= ("app.bsky.embed.external" :: Text)
            , "external" .= object externalFields
            ]

parsePostResponse :: Text -> LBS.ByteString -> Either Error PostResult
parsePostResponse postText body =
  case eitherDecode @Json.Value body of
    Left err  -> Left (JsonParseError (T.pack err))
    Right val -> case extractPostData postText val of
      Left err  -> Left (ExtractionError (T.pack err))
      Right r   -> Right r

extractPostData :: Text -> Json.Value -> Either String PostResult
extractPostData postText = withObject "create record response" $ \obj -> do
  uri <- obj .: "uri"
  cid <- obj .: "cid"
  pure PostResult
    { bprUri = uri
    , bprCid = cid
    , bprText = postText
    }

-- ── Deleting ───────────────────────────────────────────────────────────

deletePost
  :: Manager
  -> Credentials
  -> Text
  -> IO (Either Error ())
deletePost manager creds uri = do
  sessionResult <- createSession manager creds
  case sessionResult of
    Left err -> pure (Left err)
    Right session -> deleteRecord manager session uri

deleteRecord :: Manager -> AtpSession -> Text -> IO (Either Error ())
deleteRecord manager AtpSession{..} uri = do
  let (collection, rkey) = parseAtUri uri
      bodyJson = encode (object
        [ "repo" .= asDid
        , "collection" .= collection
        , "rkey" .= rkey
        ])
      url = T.unpack (atpBaseUrl <> "com.atproto.repo.deleteRecord")
  result <- try @SomeException $ withRetry defaultRetryOptions $ do
    initialReq <- parseRequest url
    let req = initialReq
          { method = "POST"
          , requestBody = RequestBodyLBS bodyJson
          , requestHeaders =
              [ ("Authorization", "Bearer " <> TE.encodeUtf8 asAccessToken)
              , ("Content-Type", "application/json")
              ]
          }
    response <- httpLbs req manager
    let status = statusCode (responseStatus response)
    when (status < 200 || status >= 300) $
      throwIO $ HttpCodeException status ("Bluesky delete error: " <> show status)
  pure $ case result of
    Left err -> Left (classifyException err)
    Right () -> Right ()

parseAtUri :: Text -> (Text, Text)
parseAtUri uri =
  case T.stripPrefix "at://" uri of
    Just rest ->
      let parts = T.splitOn "/" rest
      in case parts of
        [_did, collection, rkey] -> (collection, rkey)
        _                        -> ("app.bsky.feed.post", rest)
    Nothing -> ("app.bsky.feed.post", uri)

-- ── Embed HTML ─────────────────────────────────────────────────────────

fetchOEmbed :: Manager -> Text -> IO (Either Error EmbedResult)
fetchOEmbed manager postUrl = do
  let url = T.unpack oembedBaseUrl
              <> "?url=" <> T.unpack postUrl
              <> "&format=json"
  result <- try @SomeException $ do
    request <- parseRequest url
    response <- httpLbs request manager
    let status = statusCode (responseStatus response)
    when (status < 200 || status >= 300) $
      throwIO $ HttpCodeException status ("Bluesky oEmbed API returned " <> show status)
    pure (responseBody response)
  pure $ case result of
    Left err   -> Left (classifyException err)
    Right body -> parseOEmbedHtml body

parseOEmbedHtml :: LBS.ByteString -> Either Error EmbedResult
parseOEmbedHtml body =
  case eitherDecode @Json.Value body of
    Left err  -> Left (JsonParseError (T.pack err))
    Right val -> case withObject "oembed" (.: "html") val of
      Left err   -> Left (ExtractionError (T.pack err))
      Right html -> Right (EmbedResult html)

generateLocalEmbed :: Text -> Text -> Text -> Text -> Maybe Text -> Text
generateLocalEmbed uri postText date handle maybeCid =
  let did = fromMaybe "" (extractDid uri)
      postId = fromMaybe "" (extractPostId uri)
      postUrl = buildPostUrl did postId
      htmlText = textToHtml postText
      displayDate = formatDisplayDate date
      cidAttr = maybe "" (\cid -> " data-bluesky-cid=\"" <> cid <> "\"") maybeCid
  in "<blockquote class=\"bluesky-embed\" data-bluesky-uri=\""
       <> uri <> "\"" <> cidAttr
       <> " data-bluesky-embed-color-mode=\"system\">"
       <> "<p lang=\"en\">" <> htmlText <> "</p>"
       <> "\n&mdash; " <> displayName <> " "
       <> "(<a href=\"https://bsky.app/profile/" <> did <> "?ref_src=embed\">@" <> handle <> "</a>) "
       <> "<a href=\"" <> postUrl <> "?ref_src=embed\">" <> displayDate <> "</a>"
       <> "</blockquote>"
       <> "<script async src=\"https://embed.bsky.app/static/embed.js\" charset=\"utf-8\"></script>"

getEmbedHtml :: Manager -> Text -> IO Text
getEmbedHtml manager uri =
  let did = fromMaybe "" (extractDid uri)
      postId = fromMaybe "" (extractPostId uri)
      postUrl = buildPostUrl did postId
      fallback = buildPlaceholderLink postUrl
  in tryOEmbedWithRetry manager postUrl fallback 0 oembedMaxAttempts

tryOEmbedWithRetry :: Manager -> Text -> Text -> Int -> Int -> IO Text
tryOEmbedWithRetry manager postUrl fallback attempt maxAttempts = do
  let delayMs = if attempt == 0
        then oembedInitialDelayMs
        else oembedRetryDelayMs
  when (delayMs > 0) $
    threadDelay (delayMs * 1000)
  result <- fetchOEmbed manager postUrl
  case result of
    Right (EmbedResult html) -> pure html
    Left (HttpError 404 _)
      | attempt + 1 < maxAttempts ->
          tryOEmbedWithRetry manager postUrl fallback (attempt + 1) maxAttempts
    Left err -> do
      putStrLn $ "  ⚠️  Bluesky oEmbed failed after " <> show (attempt + 1)
                   <> " attempts: " <> show err <> " — using placeholder link"
      pure fallback

buildPlaceholderLink :: Text -> Text
buildPlaceholderLink postUrl = postUrl

isPlaceholderLink :: Text -> Bool
isPlaceholderLink section =
  let trimmed = T.strip section
      hasUrl = "https://bsky.app/profile/" `T.isInfixOf` trimmed
      hasBlockquote = "<blockquote" `T.isInfixOf` trimmed
  in hasUrl && not hasBlockquote

replacePlaceholderWithEmbed :: Text -> Text -> Text
replacePlaceholderWithEmbed fileContent embedHtml =
  let sectionStart = sectionHeader
      lines' = T.lines fileContent
  in T.unlines (replaceLinesAfterHeader sectionStart embedHtml lines')

replaceLinesAfterHeader :: Text -> Text -> [Text] -> [Text]
replaceLinesAfterHeader _ _ [] = []
replaceLinesAfterHeader header embedHtml (line : rest)
  | header `T.isPrefixOf` T.stripEnd line =
      let (sectionLines, remaining) = spanSection rest
          sectionContent = T.unlines sectionLines
      in if isPlaceholderLink sectionContent
           then line : T.stripEnd embedHtml : remaining
           else line : sectionLines <> remaining
  | otherwise = line : replaceLinesAfterHeader header embedHtml rest

spanSection :: [Text] -> ([Text], [Text])
spanSection [] = ([], [])
spanSection (line : rest)
  | "## " `T.isPrefixOf` T.stripStart line = ([], line : rest)
  | otherwise =
      let (sectionRest, remaining) = spanSection rest
      in (line : sectionRest, remaining)
