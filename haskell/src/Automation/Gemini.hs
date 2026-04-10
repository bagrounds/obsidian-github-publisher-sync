{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}

module Automation.Gemini
  ( Config (..)
  , Request (..)
  , Response (..)
  , GenerationConfig (..)
  , Error (..)
  , ApiStatus (..)
  , defaultModel
  , defaultQuestionModel
  , gemini3Flash
  , flashFallback
  , modelFallback
  , generateContent
  , generateContentWithFallback
  , defaultGenerationConfig
  , isRateLimitError
  , isQuotaExhaustedError
  , parseResponseText
  , extractText
  , parseApiStatus
  , parseErrorBody
  ) where

import Automation.Json (Value (..), ToValue (..), (.=), object, encode)
import qualified Automation.Json as Json
import Automation.Secret (Secret (..))
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

-- | Domain-specific error type for Gemini API operations.
-- Structured constructors preserve error context and enable typed pattern
-- matching. The @HttpError@ constructor carries the parsed @ApiStatus@ from
-- the official error response JSON, so rate-limit and quota detection use
-- constructor matching rather than string inspection.
data Error
  = JsonParseError
  | ExtractionError Text
  | HttpError Int ApiStatus Text
  | AllModelsFailed Text Error
  deriving (Show, Eq)

-- | Parse the structured error JSON returned by the Gemini API.
-- The documented format is:
-- @{ "error": { "code": 429, "status": "RESOURCE_EXHAUSTED", "message": "..." } }@
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
                Just (String s) -> parseApiStatus s
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
  { gcApiKey :: Secret
  , gcModel :: Text
  , gcQuestionModel :: Text
  } deriving (Show, Eq)

defaultModel :: Text
defaultModel = "gemma-3-27b-it"

defaultQuestionModel :: Text
defaultQuestionModel = "gemini-3.1-flash-lite-preview"

gemini3Flash :: Text
gemini3Flash = "gemini-3-flash-preview"

flashFallback :: Text
flashFallback = "gemini-2.5-flash"

modelFallback :: Text -> Maybe Text
modelFallback model
  | model == "gemini-3.1-flash-lite-preview" = Just flashFallback
  | otherwise = Nothing

data GenerationConfig = GenerationConfig
  { gcTemperature    :: Double
  , gcMaxOutputTokens :: Int
  } deriving (Show, Eq)

instance ToValue GenerationConfig where
  toValue gc = object
    [ "temperature" .= gcTemperature gc
    , "maxOutputTokens" .= gcMaxOutputTokens gc
    ]

defaultGenerationConfig :: GenerationConfig
defaultGenerationConfig = GenerationConfig
  { gcTemperature     = 0.7
  , gcMaxOutputTokens = 1024
  }

data Request = Request
  { grPrompt           :: Text
  , grModel            :: Text
  , grApiKey           :: Secret
  , grGenerationConfig :: GenerationConfig
  } deriving (Show, Eq)

data Response = Response
  { grText  :: Text
  , grModel' :: Text
  } deriving (Show, Eq)

geminiEndpoint :: Text -> Text
geminiEndpoint model =
  "https://generativelanguage.googleapis.com/v1beta/models/"
    <> model
    <> ":generateContent"

buildRequestBody :: Text -> GenerationConfig -> Value
buildRequestBody prompt config = object
  [ "contents" .= [ object [ "parts" .= [ object [ "text" .= prompt ] ] ] ]
  , "generationConfig" .= config
  ]

parseResponseText :: LBS.ByteString -> Either Error Text
parseResponseText body =
  case Json.decode body of
    Nothing  -> Left JsonParseError
    Just val -> extractText val

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

generateContent :: Manager -> Request -> IO (Either Error Response)
generateContent manager req = do
  let url = T.unpack $ geminiEndpoint (grModel req) <> "?key=" <> unSecret (grApiKey req)
  initReq <- parseRequest url
  let body = encode $ buildRequestBody (grPrompt req) (grGenerationConfig req)
  let httpReq = initReq
        { HTTP.method = "POST"
        , HTTP.requestBody = RequestBodyLBS body
        , HTTP.requestHeaders =
            [ ("Content-Type", "application/json")
            ]
        , HTTP.responseTimeout = responseTimeoutMicro (120 * 1000000)  -- 120 seconds for Gemini API
        }
  response <- httpLbs httpReq manager
  let status = statusCode $ responseStatus response
  case status of
    200 ->
      case parseResponseText (responseBody response) of
        Left err   -> pure $ Left err
        Right text -> pure $ Right Response
          { grText  = T.strip text
          , grModel' = grModel req
          }
    code ->
      let (apiStatus, message) = parseErrorBody (responseBody response)
      in pure $ Left $ HttpError code apiStatus message

generateContentWithFallback :: Manager -> Text -> [Text] -> Text -> Secret -> GenerationConfig -> IO (Either Error Response)
generateContentWithFallback manager model fallbacks prompt apiKey config = do
  result <- generateContent manager Request
    { grPrompt = prompt
    , grModel = model
    , grApiKey = apiKey
    , grGenerationConfig = config
    }
  case result of
    Right resp -> pure $ Right resp
    Left err -> case fallbacks of
      [] -> pure $ Left $ AllModelsFailed model err
      (next : rest) -> do
        putStrLn $ "⚠️ Model " <> T.unpack model <> " failed, trying next fallback..."
        generateContentWithFallback manager next rest prompt apiKey config
