module Automation.BlogImage.Provider
  ( ImageProvider (..)
  , PromptDescriber (..)
  , ImageProviderConfig (..)
  , ImageGenerationResult (..)
  , providerName
  , generateImage
  , describeContent
  , describeImageWithGemini
  , resolveImageProviders
  , isQuotaError
  , isDailyQuotaError
  , isProviderUnavailableError
  , mimeTypeToExtension
  , generateWithCloudflare
  , generateWithHuggingFace
  , generateWithTogether
  , generateWithPollinations
  , generateImageWithGemini
  ) where

import qualified Data.ByteString.Base64 as B64
import qualified Data.ByteString.Lazy as LBS
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (catMaybes, fromMaybe)
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
  , responseHeaders
  , responseStatus
  )
import Network.HTTP.Types.Header (hContentType)
import Network.HTTP.Types.Status (statusCode)
import Network.HTTP.Types.URI (urlEncode)

import qualified Automation.Gemini as Gemini
import qualified Automation.Json as Json
import Automation.Secret (Secret (..), unSecret)

data ImageGenerationResult = ImageGenerationResult
  { igrSkipped     :: Bool
  , igrImagePath   :: Maybe FilePath
  , igrImageName   :: Maybe Text
  , igrImagePrompt :: Maybe Text
  } deriving (Show, Eq)

data ImageProvider
  = Cloudflare Text  -- account ID
  | HuggingFace
  | Together
  | Pollinations
  | GeminiImage
  deriving (Show, Eq)

providerName :: ImageProvider -> Text
providerName = \case
  Cloudflare _ -> "cloudflare"
  HuggingFace  -> "huggingface"
  Together     -> "together"
  Pollinations -> "pollinations"
  GeminiImage  -> "gemini"

data PromptDescriber = PromptDescriber
  { describerApiKey :: Secret
  , describerModel  :: Gemini.Model
  } deriving (Eq)

instance Show PromptDescriber where
  show (PromptDescriber key mdl) = "PromptDescriber " <> show key <> " " <> show mdl

data ImageProviderConfig = ImageProviderConfig
  { ipcProvider  :: ImageProvider
  , ipcApiKey    :: Secret
  , ipcModel     :: Text
  , ipcDescriber :: Maybe PromptDescriber
  } deriving (Show, Eq)

mimeTypeToExtension :: Text -> Text
mimeTypeToExtension mime = case T.takeWhile (/= ';') (T.strip mime) of
  "image/jpeg" -> ".jpg"
  "image/png"  -> ".png"
  "image/gif"  -> ".gif"
  "image/webp" -> ".webp"
  _            -> ".jpg"

isQuotaError :: Text -> Bool
isQuotaError msg =
  T.isInfixOf "429" msg
    || T.isInfixOf "RESOURCE_EXHAUSTED" msg
    || T.isInfixOf "quota" msg

isDailyQuotaError :: Text -> Bool
isDailyQuotaError msg =
  T.isInfixOf "quota" msg
    && (T.isInfixOf "daily" msg || T.isInfixOf "per day" msg || T.isInfixOf "PerDay" msg)

isProviderUnavailableError :: Text -> Bool
isProviderUnavailableError msg =
  T.isInfixOf "410" msg
    || T.isInfixOf "401" msg
    || T.isInfixOf "403" msg
    || T.isInfixOf "no longer supported" msg
    || T.isInfixOf "deprecated" msg

defaultDescriberModel :: Gemini.Model
defaultDescriberModel = Gemini.Gemini31FlashLite

imageDescriptionSystemPrompt :: Text
imageDescriptionSystemPrompt = T.intercalate " "
  [ "Describe a cover image for the following blog post."
  , "Focus on visual elements that would make an appealing illustration."
  , "Be concise — respond in under 150 words."
  , "Do not include any text or words in the image."
  , "Respond with only the image description, no preamble."
  ]

generateWithCloudflare
  :: Manager -> Text -> Text -> Text -> Text -> IO (Either Text (LBS.ByteString, Text))
generateWithCloudflare manager apiToken accountId model prompt = do
  let url = "https://api.cloudflare.com/client/v4/accounts/"
            <> T.unpack accountId <> "/ai/run/" <> T.unpack model
  initialRequest <- parseRequest url
  let body = Json.encode $ Json.object
        [ "prompt" Json..= prompt
        , "steps"  Json..= (4 :: Int)
        ]
      httpReq = initialRequest
        { method = "POST"
        , requestBody = RequestBodyLBS body
        , requestHeaders =
            [ ("Authorization", "Bearer " <> TE.encodeUtf8 apiToken)
            , ("Content-Type", "application/json")
            ]
        }
  resp <- httpLbs httpReq manager
  let status = statusCode (responseStatus resp)
  case status of
    200 -> pure $ parseCloudflareResponse (responseBody resp)
    code -> pure $ Left $
      "Cloudflare API error " <> T.pack (show code) <> ": "
        <> TE.decodeUtf8 (LBS.toStrict (responseBody resp))

parseCloudflareResponse :: LBS.ByteString -> Either Text (LBS.ByteString, Text)
parseCloudflareResponse body =
  case Json.eitherDecode body :: Either String Json.Value of
    Left err -> Left (T.pack err)
    Right (Json.Object obj) -> do
      success <- mapLeft T.pack (obj Json..: "success" :: Either String Bool)
      if not success
        then Left "Cloudflare image generation failed: success=false"
        else case lookup "result" obj of
          Just (Json.Object resultObj) ->
            case lookup "image" resultObj of
              Just (Json.String b64) ->
                case B64.decode (TE.encodeUtf8 b64) of
                  Left err -> Left ("Base64 decode error: " <> T.pack err)
                  Right bs -> Right (LBS.fromStrict bs, "image/jpeg")
              _ -> Left "No image in Cloudflare response"
          _ -> Left "No result in Cloudflare response"
    Right _ -> Left "Cloudflare response is not a JSON object"

generateWithHuggingFace
  :: Manager -> Text -> Text -> Text -> IO (Either Text (LBS.ByteString, Text))
generateWithHuggingFace manager apiToken model prompt = do
  let url = "https://router.huggingface.co/hf-inference/models/" <> T.unpack model
  initialRequest <- parseRequest url
  let body = Json.encode $ Json.object [ "inputs" Json..= prompt ]
      httpReq = initialRequest
        { method = "POST"
        , requestBody = RequestBodyLBS body
        , requestHeaders =
            [ ("Authorization", "Bearer " <> TE.encodeUtf8 apiToken)
            , ("Content-Type", "application/json")
            ]
        }
  resp <- httpLbs httpReq manager
  let status = statusCode (responseStatus resp)
  case status of
    200 ->
      let contentType = maybe "image/jpeg" (T.takeWhile (/= ';') . TE.decodeUtf8)
                          (lookup hContentType (responseHeaders resp))
      in if "image/" `T.isPrefixOf` contentType
         then pure $ Right (responseBody resp, contentType)
         else pure $ Left $ "HuggingFace returned non-image response: "
                <> TE.decodeUtf8 (LBS.toStrict (responseBody resp))
    code -> pure $ Left $
      "HuggingFace API error " <> T.pack (show code) <> ": "
        <> TE.decodeUtf8 (LBS.toStrict (responseBody resp))

generateWithTogether
  :: Manager -> Text -> Text -> Text -> IO (Either Text (LBS.ByteString, Text))
generateWithTogether manager apiKey model prompt = do
  initialRequest <- parseRequest "https://api.together.ai/v1/images/generations"
  let body = Json.encode $ Json.object
        [ "model"           Json..= model
        , "prompt"          Json..= prompt
        , "steps"           Json..= (4 :: Int)
        , "n"               Json..= (1 :: Int)
        , "response_format" Json..= ("b64_json" :: Text)
        ]
      httpReq = initialRequest
        { method = "POST"
        , requestBody = RequestBodyLBS body
        , requestHeaders =
            [ ("Authorization", "Bearer " <> TE.encodeUtf8 apiKey)
            , ("Content-Type", "application/json")
            ]
        }
  resp <- httpLbs httpReq manager
  let status = statusCode (responseStatus resp)
  case status of
    200 -> pure $ parseTogetherResponse (responseBody resp)
    code -> pure $ Left $
      "Together API error " <> T.pack (show code) <> ": "
        <> TE.decodeUtf8 (LBS.toStrict (responseBody resp))

parseTogetherResponse :: LBS.ByteString -> Either Text (LBS.ByteString, Text)
parseTogetherResponse body =
  case Json.eitherDecode body :: Either String Json.Value of
    Left err -> Left (T.pack err)
    Right (Json.Object obj) ->
      case lookup "data" obj of
        Just (Json.Array (Json.Object item : _)) ->
          case lookup "b64_json" item of
            Just (Json.String b64) ->
              case B64.decode (TE.encodeUtf8 b64) of
                Left err -> Left ("Base64 decode error: " <> T.pack err)
                Right bs -> Right (LBS.fromStrict bs, "image/jpeg")
            _ -> Left "No b64_json in Together response"
        _ -> Left "No data array in Together response"
    Right _ -> Left "Together response is not a JSON object"

generateWithPollinations
  :: Manager -> Text -> Text -> IO (Either Text (LBS.ByteString, Text))
generateWithPollinations manager model prompt = do
  let encodedPrompt = TE.decodeUtf8 (urlEncode True (TE.encodeUtf8 prompt))
      encodedModel = TE.decodeUtf8 (urlEncode True (TE.encodeUtf8 model))
      url = "https://image.pollinations.ai/prompt/" <> T.unpack encodedPrompt
            <> "?model=" <> T.unpack encodedModel
            <> "&width=1024&height=1024&nologo=true"
  initialRequest <- parseRequest url
  resp <- httpLbs initialRequest manager
  let status = statusCode (responseStatus resp)
  case status of
    200 ->
      let contentType = maybe "image/jpeg" (T.takeWhile (/= ';') . TE.decodeUtf8)
                          (lookup hContentType (responseHeaders resp))
      in if "image/" `T.isPrefixOf` contentType
         then pure $ Right (responseBody resp, contentType)
         else pure $ Left $ "Pollinations returned non-image response: "
                <> TE.decodeUtf8 (LBS.toStrict (responseBody resp))
    code -> pure $ Left $
      "Pollinations API error " <> T.pack (show code) <> ": "
        <> TE.decodeUtf8 (LBS.toStrict (responseBody resp))

isImagenModel :: Text -> Bool
isImagenModel = T.isPrefixOf "imagen-"

generateImageWithGemini
  :: Manager -> Text -> Text -> Text -> IO (Either Text (LBS.ByteString, Text))
generateImageWithGemini manager apiKey model prompt
  | isImagenModel model = generateWithImagen manager apiKey model prompt
  | otherwise           = generateWithGeminiContent manager apiKey model prompt

generateWithImagen
  :: Manager -> Text -> Text -> Text -> IO (Either Text (LBS.ByteString, Text))
generateWithImagen manager apiKey model prompt = do
  let url = "https://generativelanguage.googleapis.com/v1beta/models/"
            <> T.unpack model <> ":predict?key=" <> T.unpack apiKey
  initialRequest <- parseRequest url
  let body = Json.encode $ Json.object
        [ "instances"  Json..= [ Json.object [ "prompt" Json..= prompt ] ]
        , "parameters" Json..= Json.object [ "sampleCount" Json..= (1 :: Int) ]
        ]
      httpReq = initialRequest
        { method = "POST"
        , requestBody = RequestBodyLBS body
        , requestHeaders = [("Content-Type", "application/json")]
        }
  resp <- httpLbs httpReq manager
  let status = statusCode (responseStatus resp)
  case status of
    200 -> pure $ parseImagenResponse (responseBody resp)
    code -> pure $ Left $
      "Imagen API returned status " <> T.pack (show code) <> ": "
        <> TE.decodeUtf8 (LBS.toStrict (responseBody resp))

parseImagenResponse :: LBS.ByteString -> Either Text (LBS.ByteString, Text)
parseImagenResponse body =
  case Json.eitherDecode body :: Either String Json.Value of
    Left err -> Left (T.pack err)
    Right (Json.Object obj) ->
      case lookup "predictions" obj of
        Just (Json.Array (Json.Object pred' : _)) ->
          case lookup "bytesBase64Encoded" pred' of
            Just (Json.String b64) ->
              case B64.decode (TE.encodeUtf8 b64) of
                Left err -> Left ("Base64 decode error: " <> T.pack err)
                Right bs ->
                  let mime = case lookup "mimeType" pred' of
                        Just (Json.String m) -> m
                        _                    -> "image/png"
                  in Right (LBS.fromStrict bs, mime)
            _ -> Left "No bytesBase64Encoded in Imagen response"
        _ -> Left "No predictions in Imagen response"
    Right _ -> Left "Imagen response is not a JSON object"

generateWithGeminiContent
  :: Manager -> Text -> Text -> Text -> IO (Either Text (LBS.ByteString, Text))
generateWithGeminiContent manager apiKey model prompt = do
  let url = "https://generativelanguage.googleapis.com/v1beta/models/"
            <> T.unpack model <> ":generateContent?key=" <> T.unpack apiKey
  initialRequest <- parseRequest url
  let body = Json.encode $ Json.object
        [ "contents" Json..=
            [ Json.object [ "parts" Json..= [ Json.object [ "text" Json..= prompt ] ] ] ]
        , "generationConfig" Json..= Json.object
            [ "responseModalities" Json..= (["IMAGE"] :: [Text]) ]
        ]
      httpReq = initialRequest
        { method = "POST"
        , requestBody = RequestBodyLBS body
        , requestHeaders = [("Content-Type", "application/json")]
        }
  resp <- httpLbs httpReq manager
  let status = statusCode (responseStatus resp)
  case status of
    200 -> pure $ parseGeminiImageResponse (responseBody resp)
    code -> pure $ Left $
      "Gemini image API returned status " <> T.pack (show code) <> ": "
        <> TE.decodeUtf8 (LBS.toStrict (responseBody resp))

parseGeminiImageResponse :: LBS.ByteString -> Either Text (LBS.ByteString, Text)
parseGeminiImageResponse body =
  case Json.eitherDecode body :: Either String Json.Value of
    Left err -> Left (T.pack err)
    Right (Json.Object obj) ->
      case lookup "candidates" obj of
        Just (Json.Array (Json.Object cand : _)) ->
          case lookup "content" cand of
            Just (Json.Object contentObj) ->
              case lookup "parts" contentObj of
                Just (Json.Array parts) -> findInlineData parts
                _ -> Left "No parts in Gemini image response"
            _ -> Left "No content in candidate"
        _ -> Left "No candidates in Gemini image response"
    Right _ -> Left "Gemini image response is not a JSON object"

findInlineData :: [Json.Value] -> Either Text (LBS.ByteString, Text)
findInlineData [] = Left "No image generated"
findInlineData (Json.Object partObj : rest) =
  case lookup "inlineData" partObj of
    Just (Json.Object inlineObj) ->
      case lookup "data" inlineObj of
        Just (Json.String b64) ->
          case B64.decode (TE.encodeUtf8 b64) of
            Left err -> Left ("Base64 decode error: " <> T.pack err)
            Right bs ->
              let mime = case lookup "mimeType" inlineObj of
                    Just (Json.String m) -> m
                    _                    -> "image/png"
              in Right (LBS.fromStrict bs, mime)
        _ -> findInlineData rest
    _ -> findInlineData rest
findInlineData (_ : rest) = findInlineData rest

describeImageWithGemini
  :: Manager -> Text -> Gemini.Model -> Text -> IO (Either Text Text)
describeImageWithGemini manager apiKey model content = do
  let req = Gemini.Request
        { Gemini.requestPrompt = content
        , Gemini.requestSystemInstruction = Just imageDescriptionSystemPrompt
        , Gemini.requestModel = model
        , Gemini.requestApiKey = Secret apiKey
        , Gemini.requestGenerationConfig = Gemini.defaultGenerationConfig
        }
  result <- Gemini.generateContent manager req
  case result of
    Right response -> pure $ Right (Gemini.responseText response)
    Left _err  -> do
      putStrLn $ "⚠️ " <> T.unpack (Gemini.modelToText model) <> " failed for image description, trying fallback..."
      let fallbackModel = geminiModelFallback model
      let fallbackReq = req { Gemini.requestModel = fallbackModel }
      fallbackResult <- Gemini.generateContent manager fallbackReq
      case fallbackResult of
        Right response -> pure $ Right (Gemini.responseText response)
        Left err   -> pure $ Left (T.pack (show err))

geminiModelFallback :: Gemini.Model -> Gemini.Model
geminiModelFallback Gemini.Gemini3Flash       = Gemini.Gemini25Flash
geminiModelFallback Gemini.Gemini31FlashLite  = Gemini.Gemini25Flash
geminiModelFallback Gemini.Gemini31FlashImage = Gemini.Gemini25Flash
geminiModelFallback _                         = Gemini.Gemini20Flash

generateImage :: Manager -> ImageProviderConfig -> Text -> IO (Either Text (LBS.ByteString, Text))
generateImage manager config prompt =
  let key = unSecret (ipcApiKey config)
      mdl = ipcModel config
  in case ipcProvider config of
    Cloudflare accountId -> generateWithCloudflare manager key accountId mdl prompt
    HuggingFace          -> generateWithHuggingFace manager key mdl prompt
    Together             -> generateWithTogether manager key mdl prompt
    Pollinations         -> generateWithPollinations manager mdl prompt
    GeminiImage          -> generateImageWithGemini manager key mdl prompt

describeContent :: Manager -> PromptDescriber -> Text -> IO (Either Text Text)
describeContent manager describer =
  describeImageWithGemini manager (unSecret (describerApiKey describer)) (describerModel describer)

resolveImageProviders :: Map Text Text -> [ImageProviderConfig]
resolveImageProviders env =
  let geminiKey = Map.lookup "GEMINI_API_KEY" env
      describerModel = maybe defaultDescriberModel Gemini.modelFromText (Map.lookup "PROMPT_DESCRIBER_MODEL" env)
      describer = fmap (\key -> PromptDescriber (Secret key) describerModel) geminiKey
  in catMaybes
    [ mkCloudflareProvider env describer
    , mkHuggingFaceProvider env describer
    , mkTogetherProvider env describer
    , mkPollinationsProvider env describer
    , mkGeminiProvider env describer
    ]

mkCloudflareProvider :: Map Text Text -> Maybe PromptDescriber -> Maybe ImageProviderConfig
mkCloudflareProvider env describer = do
  cfToken <- Map.lookup "CLOUDFLARE_API_TOKEN" env
  cfAccountId <- Map.lookup "CLOUDFLARE_ACCOUNT_ID" env
  let cfModel = fromMaybe "@cf/black-forest-labs/flux-1-schnell" (Map.lookup "CLOUDFLARE_IMAGE_MODEL" env)
  pure ImageProviderConfig
    { ipcProvider = Cloudflare cfAccountId
    , ipcApiKey = Secret cfToken
    , ipcModel = cfModel
    , ipcDescriber = describer
    }

mkHuggingFaceProvider :: Map Text Text -> Maybe PromptDescriber -> Maybe ImageProviderConfig
mkHuggingFaceProvider env describer = do
  hfToken <- Map.lookup "HUGGINGFACE_API_TOKEN" env
  let hfModel = fromMaybe "black-forest-labs/FLUX.1-schnell" (Map.lookup "HUGGINGFACE_IMAGE_MODEL" env)
  pure ImageProviderConfig
    { ipcProvider = HuggingFace
    , ipcApiKey = Secret hfToken
    , ipcModel = hfModel
    , ipcDescriber = describer
    }

mkTogetherProvider :: Map Text Text -> Maybe PromptDescriber -> Maybe ImageProviderConfig
mkTogetherProvider env describer = do
  togetherKey <- Map.lookup "TOGETHER_API_TOKEN" env
  let togetherModel = fromMaybe "black-forest-labs/FLUX.1-schnell-Free" (Map.lookup "TOGETHER_IMAGE_MODEL" env)
  pure ImageProviderConfig
    { ipcProvider = Together
    , ipcApiKey = Secret togetherKey
    , ipcModel = togetherModel
    , ipcDescriber = describer
    }

mkPollinationsProvider :: Map Text Text -> Maybe PromptDescriber -> Maybe ImageProviderConfig
mkPollinationsProvider env describer =
  case Map.lookup "POLLINATIONS_ENABLED" env of
    Just "true" ->
      let polModel = fromMaybe "flux" (Map.lookup "POLLINATIONS_IMAGE_MODEL" env)
      in Just ImageProviderConfig
        { ipcProvider = Pollinations
        , ipcApiKey = Secret ""
        , ipcModel = polModel
        , ipcDescriber = describer
        }
    _ -> Nothing

mkGeminiProvider :: Map Text Text -> Maybe PromptDescriber -> Maybe ImageProviderConfig
mkGeminiProvider env describer = do
  geminiKey <- Map.lookup "GEMINI_API_KEY" env
  let geminiModel = maybe Gemini.Gemini31FlashImage Gemini.modelFromText (Map.lookup "IMAGE_GEMINI_MODEL" env)
  pure ImageProviderConfig
    { ipcProvider = GeminiImage
    , ipcApiKey = Secret geminiKey
    , ipcModel = Gemini.modelToText geminiModel
    , ipcDescriber = describer
    }

mapLeft :: (a -> b) -> Either a c -> Either b c
mapLeft f (Left a)  = Left (f a)
mapLeft _ (Right c) = Right c
