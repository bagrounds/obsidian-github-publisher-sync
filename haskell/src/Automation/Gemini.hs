{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}

module Automation.Gemini
  ( GeminiRequest (..)
  , GeminiResponse (..)
  , GenerationConfig (..)
  , generateContent
  , generateContentWithFallback
  , defaultGenerationConfig
  ) where

import Control.Exception (SomeException, catch, throwIO)
import Data.Aeson
  ( FromJSON (..)
  , ToJSON (..)
  , Value (..)
  , (.:)
  , (.:?)
  , (.=)
  , object
  , withObject
  )
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import GHC.Generics (Generic)
import Network.HTTP.Client
  ( Manager
  , Request (..)
  , RequestBody (..)
  , httpLbs
  , parseRequest
  , responseBody
  , responseStatus
  )
import Network.HTTP.Client.TLS (newTlsManager)
import Network.HTTP.Types.Status (statusCode)

import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as LBS

data GenerationConfig = GenerationConfig
  { gcTemperature    :: Double
  , gcMaxOutputTokens :: Int
  } deriving (Show, Eq, Generic)

instance ToJSON GenerationConfig where
  toJSON gc = object
    [ "temperature" .= gcTemperature gc
    , "maxOutputTokens" .= gcMaxOutputTokens gc
    ]

defaultGenerationConfig :: GenerationConfig
defaultGenerationConfig = GenerationConfig
  { gcTemperature     = 0.7
  , gcMaxOutputTokens = 1024
  }

data GeminiRequest = GeminiRequest
  { grPrompt           :: Text
  , grModel            :: Text
  , grApiKey           :: Text
  , grGenerationConfig :: GenerationConfig
  } deriving (Show, Eq)

data GeminiResponse = GeminiResponse
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
  case Aeson.decode body of
    Nothing -> Left "Failed to parse Gemini response JSON"
    Just val -> extractText val

extractText :: Value -> Either Text Text
extractText = withObjectE "response" $ \obj -> do
  candidates <- obj .:! "candidates"
  case candidates of
    Array arr | not (null arr) ->
      case head (toList arr) of
        Object candidate -> do
          content <- candidate .:! "content"
          case content of
            Object contentObj -> do
              parts <- contentObj .:! "parts"
              case parts of
                Array partsArr | not (null partsArr) ->
                  case head (toList partsArr) of
                    Object partObj -> case Aeson.parseMaybe (.: "text") partObj of
                      Just t  -> Right t
                      Nothing -> Left "No text in part"
                    _ -> Left "Part is not an object"
                _ -> Left "No parts in content"
            _ -> Left "Content is not an object"
        _ -> Left "Candidate is not an object"
    _ -> Left "No candidates in response"
  where
    toList (Array v) = foldr (:) [] v
    toList _         = []
    withObjectE _label f (Object o) = f o
    withObjectE label _ _           = Left $ "Expected object at " <> label
    (.:!) o k = case Aeson.parseMaybe (.: k) o of
      Just v  -> Right v
      Nothing -> Left $ "Missing key: " <> k

generateContent :: Manager -> GeminiRequest -> IO (Either Text GeminiResponse)
generateContent manager req = do
  let url = T.unpack $ geminiEndpoint (grModel req) <> "?key=" <> grApiKey req
  initReq <- parseRequest url
  let body = Aeson.encode $ buildRequestBody (grPrompt req) (grGenerationConfig req)
  let httpReq = initReq
        { method = "POST"
        , requestBody = RequestBodyLBS body
        , requestHeaders =
            [ ("Content-Type", "application/json")
            ]
        }
  response <- httpLbs httpReq manager
  let status = statusCode $ responseStatus response
  case status of
    200 ->
      case parseResponseText (responseBody response) of
        Left err   -> pure $ Left err
        Right text -> pure $ Right GeminiResponse
          { grText  = T.strip text
          , grModel' = grModel req
          }
    code -> pure $ Left $
      "Gemini API returned status " <> T.pack (show code)
        <> ": " <> TE.decodeUtf8 (LBS.toStrict $ responseBody response)

generateContentWithFallback :: Manager -> [Text] -> Text -> Text -> GenerationConfig -> IO (Either Text GeminiResponse)
generateContentWithFallback _ [] _ _ _ = pure $ Left "No models provided for fallback"
generateContentWithFallback manager (model : fallbacks) prompt apiKey config = do
  result <- generateContent manager GeminiRequest
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
