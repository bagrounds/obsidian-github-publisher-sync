{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}

module Automation.Gemini
  ( Config (..)
  , Request (..)
  , Response (..)
  , GenerationConfig (..)
  , Error (..)
  , defaultModel
  , defaultQuestionModel
  , gemini3Flash
  , flashFallback
  , modelFallback
  , generateContent
  , generateContentWithFallback
  , defaultGenerationConfig
  , renderError
  , isRateLimitError
  , isQuotaExhaustedError
  , parseResponseText
  , extractText
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

-- | Domain-specific error type for Gemini API operations.
-- Replaces raw @Either Text@ with structured constructors that preserve
-- error context and enable typed pattern matching (e.g. rate-limit detection).
data Error
  = JsonParseError
  | ExtractionError Text
  | HttpError Int Text
  | NoModelsProvided
  | AllModelsFailed Text Error
  deriving (Show, Eq)

renderError :: Error -> Text
renderError JsonParseError =
  "Failed to parse Gemini response JSON"
renderError (ExtractionError detail) =
  "Gemini response extraction failed: " <> detail
renderError (HttpError status body) =
  "Gemini API returned status " <> T.pack (show status) <> ": " <> body
renderError NoModelsProvided =
  "No models provided for fallback"
renderError (AllModelsFailed model innerError) =
  "All models failed. Last error (" <> model <> "): " <> renderError innerError

isRateLimitError :: Error -> Bool
isRateLimitError (HttpError 429 _) = True
isRateLimitError (HttpError _ body) =
  T.isInfixOf "RESOURCE_EXHAUSTED" body || T.isInfixOf "quota" body
isRateLimitError (AllModelsFailed _ inner) = isRateLimitError inner
isRateLimitError _ = False

isQuotaExhaustedError :: Error -> Bool
isQuotaExhaustedError (HttpError _ body) =
  T.isInfixOf "quota" body
    && (T.isInfixOf "daily" body || T.isInfixOf "per day" body || T.isInfixOf "PerDay" body)
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
    code -> pure $ Left $
      HttpError code (TE.decodeUtf8 (LBS.toStrict $ responseBody response))

generateContentWithFallback :: Manager -> [Text] -> Text -> Secret -> GenerationConfig -> IO (Either Error Response)
generateContentWithFallback _ [] _ _ _ = pure $ Left NoModelsProvided
generateContentWithFallback manager (model : fallbacks) prompt apiKey config = do
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
      _  -> do
        putStrLn $ "⚠️ Model " <> T.unpack model <> " failed, trying next fallback..."
        generateContentWithFallback manager fallbacks prompt apiKey config
