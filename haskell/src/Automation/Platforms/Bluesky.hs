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

import Control.Concurrent (threadDelay)
import Control.Exception (SomeException, throwIO, try)
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
import Automation.Platforms.OgMetadata (fetchImageAsBuffer)
import Automation.Retry (HttpCodeException (..), defaultRetryOptions, withRetry)
import Automation.Types
  ( BlueskyCredentials (..)
  , BlueskyPostResult (..)
  , EmbedResult (..)
  , LinkCard (..)
  , blueskyDisplayName
  , blueskyOembedInitialDelayMs
  , blueskyOembedRetryDelayMs
  )

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

createSession :: Manager -> BlueskyCredentials -> IO (Either Text AtpSession)
createSession manager BlueskyCredentials{..} = do
  let url = T.unpack (atpBaseUrl <> "com.atproto.server.createSession")
      bodyJson = encode (object
        [ "identifier" .= bcIdentifier
        , "password" .= bcPassword
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
    Left err   -> Left (T.pack (show err))
    Right body -> parseSession body

parseSession :: LBS.ByteString -> Either Text AtpSession
parseSession body =
  case eitherDecode @Json.Value body of
    Left err  -> Left (T.pack err)
    Right val -> case extractSession val of
      Left err  -> Left (T.pack err)
      Right s   -> Right s

extractSession :: Json.Value -> Either String AtpSession
extractSession = withObject "session response" $ \obj -> do
  did <- obj .: "did"
  token <- obj .: "accessJwt"
  pure AtpSession { asDid = did, asAccessToken = token }

-- ── URL Extraction (Pure) ──────────────────────────────────────────────

extractBlueskyPostId :: Text -> Maybe Text
extractBlueskyPostId uri =
  case T.splitOn "/" uri of
    parts | not (null parts) -> Just (last parts)
    _                        -> Nothing

extractBlueskyDid :: Text -> Maybe Text
extractBlueskyDid uri =
  case T.breakOn "did:" uri of
    (_, rest) | not (T.null rest) ->
      Just (T.takeWhile (\c -> c /= '/' && c /= '"' && c /= ' ') rest)
    _ -> case T.splitOn "/profile/" uri of
      [_, rest'] -> case T.splitOn "/post/" rest' of
        (did : _) -> Just did
        _         -> Nothing
      _ -> Nothing

buildBlueskyPostUrl :: Text -> Text -> Text
buildBlueskyPostUrl did postId =
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
      facets = if isUrl token
        then [Facet pos (pos + tokenLen) (FacetLink (normalizeUrl token))]
        else []
  in facets <> foldTokens fullEncoded (pos + tokenLen + spaceLen) rest

isUrl :: Text -> Bool
isUrl t = T.isPrefixOf "http://" t || T.isPrefixOf "https://" t

normalizeUrl :: Text -> Text
normalizeUrl t
  | T.isPrefixOf "http://" t || T.isPrefixOf "https://" t = t
  | otherwise = "https://" <> t

-- ── Blob Upload ────────────────────────────────────────────────────────

uploadBlob :: Manager -> AtpSession -> LBS.ByteString -> IO (Either Text Json.Value)
uploadBlob manager AtpSession{..} imageData = do
  let url = T.unpack (atpBaseUrl <> "com.atproto.repo.uploadBlob")
  result <- try @SomeException $ withRetry defaultRetryOptions $ do
    initialReq <- parseRequest url
    let req = initialReq
          { method = "POST"
          , requestBody = RequestBodyLBS imageData
          , requestHeaders =
              [ ("Authorization", "Bearer " <> TE.encodeUtf8 asAccessToken)
              , ("Content-Type", "image/jpeg")
              ]
          }
    response <- httpLbs req manager
    let status = statusCode (responseStatus response)
    when (status < 200 || status >= 300) $
      throwIO $ HttpCodeException status ("Bluesky blob upload error: " <> show status)
    pure (responseBody response)
  pure $ case result of
    Left err   -> Left (T.pack (show err))
    Right body -> case eitherDecode @Json.Value body of
      Left err  -> Left (T.pack err)
      Right val -> case withObject "blob response" (\obj -> obj .: "blob") val of
        Left err   -> Left (T.pack err)
        Right blob -> Right blob

-- ── Posting ────────────────────────────────────────────────────────────

postToBluesky
  :: Manager
  -> BlueskyCredentials
  -> Text
  -> Maybe LinkCard
  -> IO (Either Text BlueskyPostResult)
postToBluesky manager creds postText maybeLinkCard = do
  sessionResult <- createSession manager creds
  case sessionResult of
    Left err -> pure (Left err)
    Right session -> createPost manager session postText maybeLinkCard

createPost
  :: Manager
  -> AtpSession
  -> Text
  -> Maybe LinkCard
  -> IO (Either Text BlueskyPostResult)
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
        Left err   -> Left (T.pack (show err))
        Right body -> parsePostResponse postText body

buildEmbed
  :: Manager
  -> AtpSession
  -> Maybe LinkCard
  -> IO (Either Text (Maybe Json.Value))
buildEmbed _ _ Nothing = pure (Right Nothing)
buildEmbed manager session (Just LinkCard{..}) = do
  thumbResult <- case lcThumbUrl of
    Nothing       -> pure (Right Nothing)
    Just thumbUrl -> do
      imageData <- fetchImageAsBuffer thumbUrl
      blobResult <- uploadBlob manager session imageData
      pure (fmap Just blobResult)
  pure $ case thumbResult of
    Left err -> Left err
    Right maybeBlob ->
      let externalFields =
            [ "uri" .= lcUri
            , "title" .= lcTitle
            , "description" .= lcDescription
            ] <> maybe [] (\blob -> ["thumb" .= blob]) maybeBlob
      in Right $ Just $ object
            [ "$type" .= ("app.bsky.embed.external" :: Text)
            , "external" .= object externalFields
            ]

parsePostResponse :: Text -> LBS.ByteString -> Either Text BlueskyPostResult
parsePostResponse postText body =
  case eitherDecode @Json.Value body of
    Left err  -> Left (T.pack err)
    Right val -> case extractPostData postText val of
      Left err  -> Left (T.pack err)
      Right r   -> Right r

extractPostData :: Text -> Json.Value -> Either String BlueskyPostResult
extractPostData postText = withObject "create record response" $ \obj -> do
  uri <- obj .: "uri"
  cid <- obj .: "cid"
  pure BlueskyPostResult
    { bprUri = uri
    , bprCid = cid
    , bprText = postText
    }

-- ── Deleting ───────────────────────────────────────────────────────────

deleteBlueskyPost
  :: Manager
  -> BlueskyCredentials
  -> Text
  -> IO (Either Text ())
deleteBlueskyPost manager creds uri = do
  sessionResult <- createSession manager creds
  case sessionResult of
    Left err -> pure (Left err)
    Right session -> deleteRecord manager session uri

deleteRecord :: Manager -> AtpSession -> Text -> IO (Either Text ())
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
    Left err -> Left (T.pack (show err))
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

fetchBlueskyOEmbed :: Manager -> Text -> IO (Either Text EmbedResult)
fetchBlueskyOEmbed manager postUrl = do
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
    Left err   -> Left (T.pack (show err))
    Right body -> parseOEmbedHtml body

parseOEmbedHtml :: LBS.ByteString -> Either Text EmbedResult
parseOEmbedHtml body =
  case eitherDecode @Json.Value body of
    Left err  -> Left (T.pack err)
    Right val -> case withObject "oembed" (\obj -> obj .: "html") val of
      Left err   -> Left (T.pack err)
      Right html -> Right (EmbedResult html)

generateLocalBlueskyEmbed :: Text -> Text -> Text -> Text -> Maybe Text -> Text
generateLocalBlueskyEmbed uri postText date handle maybeCid =
  let did = fromMaybe "" (extractBlueskyDid uri)
      postId = fromMaybe "" (extractBlueskyPostId uri)
      postUrl = buildBlueskyPostUrl did postId
      htmlText = textToHtml postText
      displayDate = formatDisplayDate date
      cidAttr = maybe "" (\cid -> " data-bluesky-cid=\"" <> cid <> "\"") maybeCid
  in "<blockquote class=\"bluesky-embed\" data-bluesky-uri=\""
       <> uri <> "\"" <> cidAttr
       <> " data-bluesky-embed-color-mode=\"system\">"
       <> "<p lang=\"en\">" <> htmlText <> "</p>"
       <> "\n&mdash; " <> blueskyDisplayName <> " "
       <> "(<a href=\"https://bsky.app/profile/" <> did <> "?ref_src=embed\">@" <> handle <> "</a>) "
       <> "<a href=\"" <> postUrl <> "?ref_src=embed\">" <> displayDate <> "</a>"
       <> "</blockquote>"
       <> "<script async src=\"https://embed.bsky.app/static/embed.js\" charset=\"utf-8\"></script>"

getBlueskyEmbedHtml
  :: Manager
  -> Text
  -> Text
  -> Text
  -> Text
  -> Maybe Text
  -> IO Text
getBlueskyEmbedHtml manager uri postText date handle maybeCid =
  let did = fromMaybe "" (extractBlueskyDid uri)
      postId = fromMaybe "" (extractBlueskyPostId uri)
      postUrl = buildBlueskyPostUrl did postId
      fallback = generateLocalBlueskyEmbed uri postText date handle maybeCid
  in tryOEmbedWithRetry manager postUrl fallback 0 2

tryOEmbedWithRetry :: Manager -> Text -> Text -> Int -> Int -> IO Text
tryOEmbedWithRetry manager postUrl fallback attempt maxAttempts = do
  let delayMs = if attempt == 0
        then blueskyOembedInitialDelayMs
        else blueskyOembedRetryDelayMs
  when (delayMs > 0) $
    threadDelay (delayMs * 1000)
  result <- fetchBlueskyOEmbed manager postUrl
  case result of
    Right (EmbedResult html) -> pure html
    Left err
      | attempt + 1 < maxAttempts && "404" `T.isInfixOf` err ->
          tryOEmbedWithRetry manager postUrl fallback (attempt + 1) maxAttempts
      | otherwise -> pure fallback
