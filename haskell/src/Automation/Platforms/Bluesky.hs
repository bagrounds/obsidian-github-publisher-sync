module Automation.Platforms.Bluesky
  ( Credentials (..)
  , PostResult (..)
  , EmbedResult (..)
  , LinkCard (..)
  , OEmbedConfig (..)
  , Error (HttpError, JsonParseError, ExtractionError, NetworkError)
  , Facet (..)
  , FacetType (..)
  , classifyException
  , parseSession
  , parsePostResponse
  , parseOEmbedHtml
  , detectLinkFacets
  , limits
  , displayName
  , sectionHeader
  , defaultOEmbedConfig
  , extractPostId
  , extractDid
  , buildPostUrl
  , toDarkMode
  , needsDarkModeUpdate
  , isBrokenEmbed
  , extractPostUrlFromBrokenEmbed
  , needsEmbedRegeneration
  , extractRegenerationUrl
  , replaceSectionContent
  , post
  , deletePost
  , fetchOEmbed
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

import qualified Automation.Json as Json
import Automation.Json ((.=), (.:), encode, eitherDecode, object, withObject)
import Automation.Platform (PlatformLimits (..))
import Automation.Platforms.OgMetadata (detectContentType, fetchImageAsBuffer)
import Automation.Retry (HttpCodeException (HttpCodeException), defaultRetryOptions, withRetry)
import Automation.Secret (Secret (..))
import Automation.Title (Title, unTitle)
import Automation.Url (Url, mkUrl, unUrl)

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
  { identifier :: Text
  , password :: Secret
  } deriving (Show, Eq)

data PostResult = PostResult
  { postUri :: Text
  , postCid :: Text
  , postText :: Text
  } deriving (Show, Eq)

newtype EmbedResult = EmbedResult
  { embedHtml :: Text
  } deriving (Show, Eq)

data LinkCard = LinkCard
  { uri :: Url
  , title :: Title
  , description :: Text
  , thumbUrl :: Maybe Text
  } deriving (Show, Eq)

data OEmbedConfig = OEmbedConfig
  { initialDelayMilliseconds :: Int
  , retryDelayMilliseconds :: Int
  , maxAttempts :: Int
  } deriving (Show, Eq)

defaultOEmbedConfig :: OEmbedConfig
defaultOEmbedConfig = OEmbedConfig
  { initialDelayMilliseconds = 3000
  , retryDelayMilliseconds = 3000
  , maxAttempts = 3
  }

limits :: PlatformLimits
limits = PlatformLimits
  { platformMaxCharacters = 300
  , platformUrlCountLength = Nothing
  }

displayName :: Text
displayName = "Bryan Grounds"

sectionHeader :: Text
sectionHeader = "## 🦋 Bluesky"

atpBaseUrl :: Text
atpBaseUrl = "https://bsky.social/xrpc/"

oembedBaseUrl :: Text
oembedBaseUrl = "https://embed.bsky.app/oembed"

data AtpSession = AtpSession
  { did         :: Text
  , accessToken :: Text
  }

createSession :: Manager -> Credentials -> IO (Either Error AtpSession)
createSession manager Credentials{..} = do
  let url = T.unpack (atpBaseUrl <> "com.atproto.server.createSession")
      bodyJson = encode (object
        [ "identifier" .= identifier
        , "password" .= unSecret password
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
  pure AtpSession { did = did, accessToken = token }


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


data Facet = Facet
  { facetStart :: Int
  , facetEnd   :: Int
  , facetType  :: FacetType
  } deriving (Show, Eq)

data FacetType
  = FacetLink Text
  | FacetMention Text
  deriving (Show, Eq)

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
detectLinkFacets = findUrlFacets 0

findUrlFacets :: Int -> Text -> [Facet]
findUrlFacets offset txt =
  case findNextUrl txt of
    Nothing -> []
    Just (before, url, after) ->
      let prefixBytes = BS.length (TE.encodeUtf8 before)
          urlBytes = BS.length (TE.encodeUtf8 url)
          start = offset + prefixBytes
          end = start + urlBytes
      in Facet start end (FacetLink (normalizeUrl url)) : findUrlFacets end after

findNextUrl :: Text -> Maybe (Text, Text, Text)
findNextUrl txt =
  let (beforeHttps, restHttps) = T.breakOn "https://" txt
      (beforeHttp, restHttp) = T.breakOn "http://" txt
  in pickEarliest (beforeHttps, restHttps) (beforeHttp, restHttp)

pickEarliest :: (Text, Text) -> (Text, Text) -> Maybe (Text, Text, Text)
pickEarliest (beforeHttps, restHttps) (beforeHttp, restHttp)
  | T.null restHttps && T.null restHttp = Nothing
  | T.null restHttp = Just (splitUrl beforeHttps restHttps)
  | T.null restHttps = Just (splitUrl beforeHttp restHttp)
  | T.length beforeHttps <= T.length beforeHttp = Just (splitUrl beforeHttps restHttps)
  | otherwise = Just (splitUrl beforeHttp restHttp)

splitUrl :: Text -> Text -> (Text, Text, Text)
splitUrl before rest =
  let url = T.takeWhile (not . isUrlTerminator) rest
      after = T.drop (T.length url) rest
  in (before, url, after)

isUrlTerminator :: Char -> Bool
isUrlTerminator character =
  character == ' ' || character == '\n' || character == '\r' || character == '\t'

normalizeUrl :: Text -> Text
normalizeUrl t
  | T.isPrefixOf "http://" t || T.isPrefixOf "https://" t = t
  | otherwise = "https://" <> t


uploadBlob :: Manager -> AtpSession -> BS.ByteString -> LBS.ByteString -> IO (Either Error Json.Value)
uploadBlob manager AtpSession{..} contentType imageData = do
  let url = T.unpack (atpBaseUrl <> "com.atproto.repo.uploadBlob")
  result <- try @SomeException $ withRetry defaultRetryOptions $ do
    initialReq <- parseRequest url
    let req = initialReq
          { method = "POST"
          , requestBody = RequestBodyLBS imageData
          , requestHeaders =
              [ ("Authorization", "Bearer " <> TE.encodeUtf8 accessToken)
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
            [ "repo" .= did
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
                  [ ("Authorization", "Bearer " <> TE.encodeUtf8 accessToken)
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
  thumbResult <- case thumbUrl of
    Nothing       -> pure (Right Nothing)
    Just thumbSource -> do
      imageData <- fetchImageAsBuffer thumbSource
      let mimeType = TE.encodeUtf8 (detectContentType thumbSource)
      blobResult <- uploadBlob manager session mimeType imageData
      pure (fmap Just blobResult)
  pure $ case thumbResult of
    Left err -> Left err
    Right maybeBlob ->
      let externalFields =
            [ "uri" .= unUrl uri
            , "title" .= unTitle title
            , "description" .= description
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
extractPostData originalText = withObject "create record response" $ \obj -> do
  uri <- obj .: "uri"
  cid <- obj .: "cid"
  pure PostResult
    { postUri = uri
    , postCid = cid
    , postText = originalText
    }


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
        [ "repo" .= did
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
              [ ("Authorization", "Bearer " <> TE.encodeUtf8 accessToken)
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


fetchOEmbed :: Manager -> Url -> IO (Either Error EmbedResult)
fetchOEmbed manager postUrl = do
  let url = T.unpack oembedBaseUrl
              <> "?url=" <> T.unpack (unUrl postUrl)
              <> "&format=json"
              <> "&theme=dark"
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

getEmbedHtml :: Manager -> OEmbedConfig -> Text -> IO Text
getEmbedHtml manager config atUri =
  let did = fromMaybe "" (extractDid atUri)
      postId = fromMaybe "" (extractPostId atUri)
  in case mkUrl (buildPostUrl did postId) of
    Left _ -> do
      putStrLn $ "  ⚠️  Could not build valid Bluesky post URL from AT URI: " <> T.unpack atUri
      pure (buildPostUrl did postId)
    Right postUrl -> tryOEmbedWithRetry manager config postUrl 0

tryOEmbedWithRetry :: Manager -> OEmbedConfig -> Url -> Int -> IO Text
tryOEmbedWithRetry manager config postUrl attempt = do
  let delayMs = if attempt == 0
        then initialDelayMilliseconds config
        else retryDelayMilliseconds config
  when (delayMs > 0) $
    threadDelay (delayMs * 1000)
  result <- fetchOEmbed manager postUrl
  case result of
    Right (EmbedResult html) -> pure html
    Left (HttpError 404 _)
      | attempt + 1 < maxAttempts config ->
          tryOEmbedWithRetry manager config postUrl (attempt + 1)
    Left err -> do
      putStrLn $ "  ⚠️  Bluesky oEmbed failed after " <> show (attempt + 1)
                   <> " attempts: " <> show err <> " — using placeholder link"
      pure (unUrl postUrl)

toDarkMode :: Text -> Text
toDarkMode =
    T.replace "data-bluesky-embed-color-mode=\"system\"" "data-bluesky-embed-color-mode=\"dark\""
  . T.replace "data-bluesky-embed-color-mode=\"light\"" "data-bluesky-embed-color-mode=\"dark\""

needsDarkModeUpdate :: Text -> Bool
needsDarkModeUpdate section =
  "<blockquote" `T.isInfixOf` section
    && "bluesky-embed" `T.isInfixOf` section
    && not (isBrokenEmbed section)
    && ("data-bluesky-embed-color-mode=\"system\"" `T.isInfixOf` section
         || "data-bluesky-embed-color-mode=\"light\"" `T.isInfixOf` section)

isBrokenEmbed :: Text -> Bool
isBrokenEmbed section =
  let trimmed = T.strip section
  in "<blockquote" `T.isInfixOf` trimmed
       && "data-bluesky-uri" `T.isInfixOf` trimmed
       && "did:plc:" `T.isInfixOf` extractParagraphContent trimmed

extractParagraphContent :: Text -> Text
extractParagraphContent html =
  case T.breakOn "<p " html of
    (_, rest) | not (T.null rest) ->
      let afterOpen = T.drop 1 (T.dropWhile (/= '>') rest)
      in T.takeWhile (/= '<') afterOpen
    _ -> ""

extractPostUrlFromBrokenEmbed :: Text -> Maybe Url
extractPostUrlFromBrokenEmbed section =
  case T.breakOn "data-bluesky-uri=\"" section of
    (_, rest) | not (T.null rest) ->
      let afterAttr = T.drop (T.length "data-bluesky-uri=\"") rest
          uriValue = T.takeWhile (/= '"') afterAttr
      in extractUrlFromUri uriValue
    _ -> Nothing

extractUrlFromUri :: Text -> Maybe Url
extractUrlFromUri uriValue
  | "https://bsky.app/" `T.isPrefixOf` uriValue =
      either (const Nothing) Just (mkUrl uriValue)
  | "at://" `T.isPrefixOf` uriValue =
      let did = fromMaybe "" (extractDid uriValue)
          postId = fromMaybe "" (extractPostId uriValue)
      in either (const Nothing) Just (mkUrl (buildPostUrl did postId))
  | otherwise = Nothing

needsEmbedRegeneration :: Text -> Bool
needsEmbedRegeneration section =
  isPlaceholderLink section || isBrokenEmbed section || needsDarkModeUpdate section

isPlaceholderLink :: Text -> Bool
isPlaceholderLink section =
  let trimmed = T.strip section
  in "https://bsky.app/profile/" `T.isInfixOf` trimmed
       && not ("<blockquote" `T.isInfixOf` trimmed)

extractRegenerationUrl :: Text -> Maybe Url
extractRegenerationUrl section
  | isPlaceholderLink section =
      either (const Nothing) Just (mkUrl (T.strip section))
  | isBrokenEmbed section =
      extractPostUrlFromBrokenEmbed section
  | otherwise = Nothing

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
