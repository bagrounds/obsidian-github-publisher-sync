{-# LANGUAGE OverloadedStrings #-}

module Automation.Gemini
  ( Config (..)
  , Request (..)
  , Response (..)
  , GroundingSource (..)
  , GenerationConfig (..)
  , Error (..)
  , ApiStatus (..)
  , Model (..)
  , modelToText
  , modelFromText
  , knownModels
  , defaultModel
  , defaultQuestionModel
  , gemini3Flash
  , flashFallback
  , modelFallback
  , overrideModelChain
  , supportsSystemInstruction
  , generateContent
  , generateContentWithFallback
  , defaultGenerationConfig
  , isRateLimitError
  , isQuotaExhaustedError
  , parseResponseText
  , extractText
  , extractGroundingSources
  , parseApiStatus
  , parseErrorBody
  , buildRequestBody
  , formatGroundingSources
  ) where

import Automation.Json (Value (..), ToValue (..), (.=), object, encode)
import qualified Automation.Json as Json
import Automation.Secret (Secret (..))
import Automation.Url (Url, unUrl, mkUrl)
import Data.List.NonEmpty (NonEmpty ((:|)))
import qualified Data.List.NonEmpty as NE
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Network.HTTP.Client
  ( Manager
  , RequestBody (..)
  , httpLbs
  , parseRequest
  , responseBody
  , responseStatus
  , responseTimeoutMicro
  )
import qualified Network.HTTP.Client as HTTP
import Network.HTTP.Types.Status (statusCode)

import qualified Data.ByteString.Lazy as LBS

-- | Machine-readable API status from the Gemini error response.
-- Parsed from the @error.status@ field documented at
-- https://ai.google.dev/gemini-api/docs/troubleshooting
data ApiStatus
  = ResourceExhausted
  | InvalidArgument
  | PermissionDenied
  | NotFound
  | InternalError
  | Unavailable
  | DeadlineExceeded
  | Unauthenticated
  | FailedPrecondition
  | UnknownStatus Text
  deriving (Show, Eq)

parseApiStatus :: Text -> ApiStatus
parseApiStatus "RESOURCE_EXHAUSTED" = ResourceExhausted
parseApiStatus "INVALID_ARGUMENT"   = InvalidArgument
parseApiStatus "PERMISSION_DENIED"  = PermissionDenied
parseApiStatus "NOT_FOUND"          = NotFound
parseApiStatus "INTERNAL"           = InternalError
parseApiStatus "UNAVAILABLE"        = Unavailable
parseApiStatus "DEADLINE_EXCEEDED"  = DeadlineExceeded
parseApiStatus "UNAUTHENTICATED"    = Unauthenticated
parseApiStatus "FAILED_PRECONDITION" = FailedPrecondition
parseApiStatus other                = UnknownStatus other

-- | Typed representation of Gemini API models.
-- Known models have dedicated constructors; environment variable overrides
-- use @Custom@ to preserve arbitrary model strings from the API.
--
-- Authoritative documentation per model is linked next to its
-- @modelToText@ entry below. Cross-cutting references:
--
--   * Gemini API model index: https://ai.google.dev/gemini-api/docs/models
--   * Gemini API deprecations / shutdown dates: https://ai.google.dev/gemini-api/docs/deprecations
--   * Gemma on the Gemini API:   https://ai.google.dev/gemma/docs/core/gemma_on_gemini_api
--   * Gemma 4 model card:        https://ai.google.dev/gemma/docs/core
data Model
  = Gemma3
  | Gemma4
  | Gemma4MixtureOfExperts
  | Gemini31FlashLite
  | Gemini3Flash
  | Gemini25Flash
  | Gemini25FlashLite
  | Gemini20Flash
  | Gemini31FlashImage
  | Custom Text
  deriving (Show, Eq, Ord)

modelToText :: Model -> Text
-- https://ai.google.dev/gemma/docs/core (Gemma 3 27B IT — open-weight; older Gemma generation).
modelToText Gemma3                  = "gemma-3-27b-it"
-- https://ai.google.dev/gemma/docs/core/gemma_on_gemini_api (Gemma 4 31B IT, dense, served on the Gemini API).
modelToText Gemma4                  = "gemma-4-31b-it"
-- https://ai.google.dev/gemma/docs/core/gemma_on_gemini_api (Gemma 4 26B A4B IT, mixture-of-experts variant).
modelToText Gemma4MixtureOfExperts  = "gemma-4-26b-a4b-it"
-- https://ai.google.dev/gemini-api/docs/models (Gemini 3.1 Flash-Lite preview; preview alias of @gemini-3.1-flash-lite@).
-- Per https://ai.google.dev/gemini-api/docs/deprecations the @-preview@ alias has a published shutdown date — the live test executable surfaces a 404 if it has been turned off.
modelToText Gemini31FlashLite       = "gemini-3.1-flash-lite-preview"
-- https://ai.google.dev/gemini-api/docs/models (Gemini 3 Flash preview).
modelToText Gemini3Flash            = "gemini-3-flash-preview"
-- https://ai.google.dev/gemini-api/docs/models/gemini-2.5-flash (Gemini 2.5 Flash, stable).
modelToText Gemini25Flash           = "gemini-2.5-flash"
-- https://ai.google.dev/gemini-api/docs/models (Gemini 2.5 Flash-Lite, stable).
modelToText Gemini25FlashLite       = "gemini-2.5-flash-lite"
-- https://ai.google.dev/gemini-api/docs/models/gemini-2.0-flash (Gemini 2.0 Flash; see deprecations page for shutdown date).
modelToText Gemini20Flash           = "gemini-2.0-flash"
-- https://ai.google.dev/gemini-api/docs/image-generation (Gemini 3.1 Flash Image preview — image-generation model, not used for fiction).
modelToText Gemini31FlashImage      = "gemini-3.1-flash-image-preview"
modelToText (Custom t)              = t

modelFromText :: Text -> Model
modelFromText "gemma-3-27b-it"                 = Gemma3
modelFromText "gemma-4-31b-it"                 = Gemma4
modelFromText "gemma-4-26b-a4b-it"             = Gemma4MixtureOfExperts
modelFromText "gemini-3.1-flash-lite-preview"  = Gemini31FlashLite
modelFromText "gemini-3-flash-preview"         = Gemini3Flash
modelFromText "gemini-2.5-flash"               = Gemini25Flash
modelFromText "gemini-2.5-flash-lite"          = Gemini25FlashLite
modelFromText "gemini-2.0-flash"               = Gemini20Flash
modelFromText "gemini-3.1-flash-image-preview" = Gemini31FlashImage
modelFromText t                                = Custom t

-- | All known model constructors (excludes @Custom@).
knownModels :: [Model]
knownModels =
  [ Gemma3
  , Gemma4
  , Gemma4MixtureOfExperts
  , Gemini31FlashLite
  , Gemini3Flash
  , Gemini25Flash
  , Gemini25FlashLite
  , Gemini20Flash
  , Gemini31FlashImage
  ]

overrideModelChain :: Maybe Text -> NonEmpty Model -> NonEmpty Model
overrideModelChain envValue defaultChain = case envValue of
  Just raw | not (T.null (T.strip raw)) ->
    let parsed = modelFromText (T.strip raw)
    in parsed :| filter (/= parsed) (NE.toList defaultChain)
  _ -> defaultChain

-- | Whether this model accepts a top-level @systemInstruction@ field on the
-- Gemini @generateContent@ endpoint.
--
-- The Gemma family is treated as not supporting it because the public Gemini
-- API has historically rejected @systemInstruction@ for Gemma (the prompt is
-- folded into the user turn instead). Note that the Gemma 4 model card at
-- https://ai.google.dev/gemma/docs/core advertises native system-prompt
-- support in the underlying weights, and
-- https://ai.google.dev/gemma/docs/core/gemma_on_gemini_api is the place to
-- re-check whether the Gemini API has started exposing it. The conservative
-- @False@ here keeps us safe today; flipping it to @True@ is a one-line
-- change once the API documents support.
supportsSystemInstruction :: Model -> Bool
supportsSystemInstruction Gemma3                 = False
supportsSystemInstruction Gemma4                 = False
supportsSystemInstruction Gemma4MixtureOfExperts = False
supportsSystemInstruction _                      = True

-- | Domain-specific error type for Gemini API operations.
-- Structured constructors preserve error context and enable typed pattern
-- matching. The @HttpError@ constructor carries the parsed @ApiStatus@ from
-- the official error response JSON, so rate-limit and quota detection use
-- constructor matching rather than string inspection.
data Error
  = JsonParseError
  | ExtractionError Text
  | HttpError Int ApiStatus Text
  | AllModelsFailed Model Error
  deriving (Show, Eq)

-- | Parse the structured error JSON returned by the Gemini API.
-- The documented format is:
-- @{ "error": { "code": 429, "status": "RESOURCE_EXHAUSTED", "message": "..." } }@
-- See https://ai.google.dev/gemini-api/docs/troubleshooting for the official error format.
-- Returns the parsed @ApiStatus@ and human-readable message, or a fallback
-- @UnknownStatus@ with the raw body when parsing fails.
parseErrorBody :: LBS.ByteString -> (ApiStatus, Text)
parseErrorBody body =
  let rawText = TE.decodeUtf8 (LBS.toStrict body)
  in case Json.decode body of
    Just (Object topLevel) ->
      case lookup "error" topLevel of
        Just (Object errObj) ->
          let status = case lookup "status" errObj of
                Just (String string) -> parseApiStatus string
                _               -> UnknownStatus rawText
              message = case lookup "message" errObj of
                Just (String m) -> m
                _               -> rawText
          in (status, message)
        _ -> (UnknownStatus rawText, rawText)
    _ -> (UnknownStatus rawText, rawText)

isRateLimitError :: Error -> Bool
isRateLimitError (HttpError _ ResourceExhausted _) = True
isRateLimitError (AllModelsFailed _ inner) = isRateLimitError inner
isRateLimitError _ = False

isQuotaExhaustedError :: Error -> Bool
isQuotaExhaustedError (HttpError _ ResourceExhausted message) =
  T.isInfixOf "daily" message || T.isInfixOf "per day" message || T.isInfixOf "PerDay" message
isQuotaExhaustedError (AllModelsFailed _ inner) = isQuotaExhaustedError inner
isQuotaExhaustedError _ = False

data Config = Config
  { apiKey :: Secret
  , model :: Model
  , questionModel :: Model
  } deriving (Show, Eq)

defaultModel :: Model
defaultModel = Gemma3

defaultQuestionModel :: Model
defaultQuestionModel = Gemini31FlashLite

gemini3Flash :: Model
gemini3Flash = Gemini3Flash

flashFallback :: Model
flashFallback = Gemini25Flash

modelFallback :: Model -> Maybe Model
modelFallback Gemini31FlashLite = Just flashFallback
modelFallback _                 = Nothing

data GenerationConfig = GenerationConfig
  { temperature     :: Double
  , maxOutputTokens :: Int
  , searchGrounding :: Bool
  } deriving (Show, Eq)

instance ToValue GenerationConfig where
  toValue config = object
    [ "temperature" .= temperature config
    , "maxOutputTokens" .= maxOutputTokens config
    ]

defaultGenerationConfig :: GenerationConfig
defaultGenerationConfig = GenerationConfig
  { temperature     = 0.7
  , maxOutputTokens = 1024
  , searchGrounding = False
  }

data Request = Request
  { requestPrompt             :: Text
  , requestSystemInstruction  :: Maybe Text
  , requestModel              :: Model
  , requestApiKey             :: Secret
  , requestGenerationConfig   :: GenerationConfig
  } deriving (Show, Eq)

-- | A single grounded web source returned by the Gemini API when Google Search
-- grounding is enabled.
-- https://ai.google.dev/api/generate-content#v1beta.GroundingChunk
data GroundingSource = GroundingSource
  { groundingSourceUrl   :: Url
  , groundingSourceTitle :: Text
  } deriving (Show, Eq)

data Response = Response
  { responseText             :: Text
  , responseModel            :: Model
  , responseGroundingSources :: [GroundingSource]
  } deriving (Show, Eq)

geminiEndpoint :: Model -> Text
geminiEndpoint model =
  "https://generativelanguage.googleapis.com/v1beta/models/"
    <> modelToText model
    <> ":generateContent"

-- | Surface high-signal warnings for failure modes that usually mean a model
-- has been decommissioned or no longer accepts our request shape, so they are
-- easy to spot in scheduled-job logs without having to inspect the full
-- request/response dump.
--
-- See https://ai.google.dev/gemini-api/docs/deprecations for the official list
-- of shutdown dates and recommended replacements.
logModelHealth :: Model -> Int -> ApiStatus -> Text -> IO ()
logModelHealth model code apiStatus message =
  let modelName = T.unpack (modelToText model)
      messageStr = T.unpack message
  in case (code, apiStatus) of
    (404, _) -> putStrLn $
      "🛑 Gemini model " <> modelName <> " returned 404 NOT_FOUND — it may have been decommissioned. "
      <> "Check https://ai.google.dev/gemini-api/docs/deprecations for the recommended replacement. "
      <> "API message: " <> messageStr
    (_, NotFound) -> putStrLn $
      "🛑 Gemini model " <> modelName <> " reported NOT_FOUND status — it may have been decommissioned. "
      <> "Check https://ai.google.dev/gemini-api/docs/deprecations. API message: " <> messageStr
    (_, InvalidArgument) -> putStrLn $
      "⚠️ Gemini model " <> modelName <> " rejected the request as INVALID_ARGUMENT — the request shape may no longer be supported. "
      <> "Check https://ai.google.dev/gemini-api/docs/models for current capabilities. API message: " <> messageStr
    _ -> pure ()

buildRequestBody :: Maybe Text -> Text -> GenerationConfig -> Value
buildRequestBody systemInstruction prompt config =
  let contentFields =
        [ "contents" .= [ object [ "parts" .= [ object [ "text" .= prompt ] ] ] ]
        , "generationConfig" .= config
        ]
      fieldsWithTools = if searchGrounding config
        then ("tools" .= [ object [ "google_search" .= object [] ] ]) : contentFields
        else contentFields
      fields = case systemInstruction of
        Nothing -> fieldsWithTools
        Just instruction -> ("system_instruction" .= object [ "parts" .= [ object [ "text" .= instruction ] ] ]) : fieldsWithTools
  in object fields

parseResponseText :: LBS.ByteString -> Either Error Text
parseResponseText body =
  case Json.decode body of
    Nothing       -> Left JsonParseError
    Just jsonValue -> extractText jsonValue

extractText :: Value -> Either Error Text
extractText (Object obj) =
  case lookup "candidates" obj of
    Just (Array (Object candidate : _)) ->
      case lookup "content" candidate of
        Just (Object contentObj) ->
          case lookup "parts" contentObj of
            Just (Array (Object partObj : _)) ->
              case lookup "text" partObj of
                Just (String t) -> Right t
                _               -> Left (ExtractionError "no text in part")
            _ -> Left (ExtractionError "no parts in content")
        _ -> Left (ExtractionError "content is not an object")
    _ -> Left (ExtractionError "no candidates in response")
extractText _ = Left (ExtractionError "response is not an object")

-- | Extract grounding sources from a Gemini API response value.
-- https://ai.google.dev/api/generate-content#v1beta.GroundingMetadata
extractGroundingSources :: Value -> [GroundingSource]
extractGroundingSources (Object obj) =
  case lookup "candidates" obj of
    Just (Array (Object candidate : _)) ->
      case lookup "groundingMetadata" candidate of
        Just (Object meta) ->
          case lookup "groundingChunks" meta of
            Just (Array chunks) -> concatMap extractChunkSource chunks
            _                   -> []
        _ -> []
    _ -> []
extractGroundingSources _ = []

extractChunkSource :: Value -> [GroundingSource]
extractChunkSource (Object chunk) =
  case lookup "web" chunk of
    Just (Object web) ->
      let uriText = case lookup "uri" web of
                      Just (String u) -> u
                      _               -> ""
          titleText = case lookup "title" web of
                        Just (String t) -> if T.null t then uriText else t
                        _               -> uriText
      in case mkUrl uriText of
           Right url -> [GroundingSource { groundingSourceUrl = url, groundingSourceTitle = titleText }]
           Left _    -> []
    _ -> []
extractChunkSource _ = []

-- | Format a list of grounding sources as a markdown section.
-- Returns Nothing when the list is empty.
-- Deduplicates by URL, preserving the first occurrence of each.
formatGroundingSources :: [GroundingSource] -> Maybe Text
formatGroundingSources [] = Nothing
formatGroundingSources sources =
  let unique = deduplicateByUrl sources
      items = fmap formatSourceItem unique
  in Just $ "\n\n## 🔍 Sources\n\n" <> T.intercalate "\n" items

deduplicateByUrl :: [GroundingSource] -> [GroundingSource]
deduplicateByUrl = foldl' addIfNew []
  where
    addIfNew accumulated source =
      if any (\existing -> groundingSourceUrl existing == groundingSourceUrl source) accumulated
        then accumulated
        else accumulated <> [source]

formatSourceItem :: GroundingSource -> Text
formatSourceItem source =
  "- 🌐 [" <> groundingSourceTitle source <> "](" <> unUrl (groundingSourceUrl source) <> ")"

generateContent :: Manager -> Request -> IO (Either Error Response)
generateContent manager request = do
  let model = requestModel request
      modelSupport = supportsSystemInstruction model
      effectiveSystemInstruction = if modelSupport then requestSystemInstruction request else Nothing
      effectivePrompt = case (requestSystemInstruction request, modelSupport) of
        (Just systemInstruction, False) -> systemInstruction <> "\n\n" <> requestPrompt request
        _                               -> requestPrompt request
  let url = T.unpack $ geminiEndpoint model <> "?key=" <> unSecret (requestApiKey request)
  parsedRequest <- parseRequest url
  let body = encode $ buildRequestBody effectiveSystemInstruction effectivePrompt (requestGenerationConfig request)
  putStrLn $ "📤 Gemini request (" <> T.unpack (modelToText model) <> "): "
    <> T.unpack (TE.decodeUtf8 (LBS.toStrict body))
  let httpRequest = parsedRequest
        { HTTP.method = "POST"
        , HTTP.requestBody = RequestBodyLBS body
        , HTTP.requestHeaders =
            [ ("Content-Type", "application/json")
            ]
        , HTTP.responseTimeout = responseTimeoutMicro (120 * 1000000)  -- 120 seconds for Gemini API
        }
  response <- httpLbs httpRequest manager
  let status = statusCode $ responseStatus response
  putStrLn $ "📥 Gemini response (" <> T.unpack (modelToText model) <> ", status " <> show status <> "): "
    <> T.unpack (TE.decodeUtf8 (LBS.toStrict (responseBody response)))
  case status of
    200 ->
      case (parseResponseText (responseBody response), Json.decode (responseBody response)) of
        (Left failure, _) -> pure $ Left failure
        (Right text, Nothing) -> pure $ Right Response
          { responseText             = T.strip text
          , responseModel            = model
          , responseGroundingSources = []
          }
        (Right text, Just jsonValue) -> do
          let sources = extractGroundingSources jsonValue
          pure $ Right Response
            { responseText             = T.strip text
            , responseModel            = model
            , responseGroundingSources = sources
            }
    code ->
      let (apiStatus, message) = parseErrorBody (responseBody response)
      in do
        logModelHealth model code apiStatus message
        pure $ Left $ HttpError code apiStatus message

generateContentWithFallback :: Manager -> NonEmpty Model -> Maybe Text -> Text -> Secret -> GenerationConfig -> IO (Either Error Response)
generateContentWithFallback manager (model :| fallbacks) systemInstruction prompt apiKey config = do
  result <- generateContent manager Request
    { requestPrompt            = prompt
    , requestSystemInstruction = systemInstruction
    , requestModel             = model
    , requestApiKey            = apiKey
    , requestGenerationConfig  = config
    }
  case result of
    Right response -> pure $ Right response
    Left failure -> case fallbacks of
      [] -> pure $ Left $ AllModelsFailed model failure
      (next : rest) -> do
        putStrLn $ "⚠️ Model " <> T.unpack (modelToText model) <> " failed (" <> show failure <> "), trying next fallback..."
        generateContentWithFallback manager (next :| rest) systemInstruction prompt apiKey config
