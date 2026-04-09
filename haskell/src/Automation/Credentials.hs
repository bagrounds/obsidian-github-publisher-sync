module Automation.Credentials
  ( TwitterCredentials (..)
  , BlueskyCredentials (..)
  , MastodonCredentials (..)
  , GeminiConfig (..)
  , ObsidianCredentials (..)
  , EnvironmentConfig (..)
  , defaultGeminiModel
  , defaultQuestionModel
  , gemini3Flash
  , geminiFlashFallback
  , geminiModelFallback
  ) where

import Data.Text (Text)

import Automation.Secret (Secret)
import Automation.Url (Url)

data TwitterCredentials = TwitterCredentials
  { tcApiKey :: Secret
  , tcApiSecret :: Secret
  , tcAccessToken :: Secret
  , tcAccessSecret :: Secret
  } deriving (Show, Eq)

data BlueskyCredentials = BlueskyCredentials
  { bcIdentifier :: Text
  , bcPassword :: Secret
  } deriving (Show, Eq)

data MastodonCredentials = MastodonCredentials
  { mcInstanceUrl :: Url
  , mcAccessToken :: Secret
  } deriving (Show, Eq)

data GeminiConfig = GeminiConfig
  { gcApiKey :: Secret
  , gcModel :: Text
  , gcQuestionModel :: Text
  } deriving (Show, Eq)

data ObsidianCredentials = ObsidianCredentials
  { ocAuthToken :: Secret
  , ocVaultName :: Text
  , ocVaultPassword :: Maybe Secret
  } deriving (Show, Eq)

data EnvironmentConfig = EnvironmentConfig
  { ecTwitter :: Maybe TwitterCredentials
  , ecBluesky :: Maybe BlueskyCredentials
  , ecMastodon :: Maybe MastodonCredentials
  , ecGemini :: GeminiConfig
  , ecObsidian :: ObsidianCredentials
  } deriving (Show, Eq)

defaultGeminiModel :: Text
defaultGeminiModel = "gemma-3-27b-it"

defaultQuestionModel :: Text
defaultQuestionModel = "gemini-3.1-flash-lite-preview"

gemini3Flash :: Text
gemini3Flash = "gemini-3-flash-preview"

geminiFlashFallback :: Text
geminiFlashFallback = "gemini-2.5-flash"

geminiModelFallback :: Text -> Maybe Text
geminiModelFallback model
  | model == "gemini-3.1-flash-lite-preview" = Just geminiFlashFallback
  | otherwise = Nothing
