{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}

module Automation.Gemini
  ( Config (..)
  , Request (..)
  , Response (..)
  , GenerationConfig (..)
  , defaultModel
  , defaultQuestionModel
  , gemini3Flash
  , flashFallback
  , modelFallback
  , generateContent
  , generateContentWithFallback
  , defaultGenerationConfig
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

parseResponseText :: LBS.ByteString -> Either Text Text
parseResponseText body =
  case Json.decode body of
    Nothing  -> Left "Failed to parse Gemini response JSON"
    Just val -> extractText val

extractText :: Value -> Either Text Text
extractText (Object obj) =
  case lookup "candidates" obj of
    Just (Array (Object candidate : _)) ->
      case lookup "content" candidate of
        Just (Object contentObj) ->
          case lookup "parts" contentObj of
            Just (Array (Object partObj : _)) ->
              case lookup "text" partObj of
                Just (String t) -> Right t
                _               -> Left "No text in part"
            _ -> Left "No parts in content"
        _ -> Left "Content is not an object"
    _ -> Left "No candidates in response"
extractText _ = Left "Response is not an object"

generateContent :: Manager -> Request -> IO (Either Text Response)
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
      "Gemini API returned status " <> T.pack (show code)
        <> ": " <> TE.decodeUtf8 (LBS.toStrict $ responseBody response)

generateContentWithFallback :: Manager -> [Text] -> Text -> Secret -> GenerationConfig -> IO (Either Text Response)
generateContentWithFallback _ [] _ _ _ = pure $ Left "No models provided for fallback"
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
      [] -> pure $ Left $ "All models failed. Last error (" <> model <> "): " <> err
      _  -> do
        putStrLn $ "⚠️ Model " <> T.unpack model <> " failed, trying next fallback..."
        generateContentWithFallback manager fallbacks prompt apiKey config
