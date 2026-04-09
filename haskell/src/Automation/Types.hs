module Automation.Types
  ( ReflectionData (..)
  , TweetResult (..)
  , BlueskyPostResult (..)
  , MastodonPostResult (..)
  , EmbedResult (..)
  , EmbedSection (..)
  , OgMetadata (..)
  , TwitterCredentials (..)
  , BlueskyCredentials (..)
  , MastodonCredentials (..)
  , GeminiConfig (..)
  , ObsidianCredentials (..)
  , EnvironmentConfig (..)
  , LinkCard (..)
  , PlatformLimits (..)
  , Secret (..)
  , mkSecret
  , twitterLimits
  , blueskyLimits
  , mastodonLimits
  , twitterHandle
  , twitterDisplayName
  , blueskyDisplayName
  , mastodonDisplayName
  , tweetSectionHeader
  , blueskySectionHeader
  , mastodonSectionHeader
  , updatesSectionHeader
  , defaultGeminiModel
  , defaultQuestionModel
  , gemini3Flash
  , geminiFlashFallback
  , geminiModelFallback
  , blueskyOembedInitialDelayMs
  , blueskyOembedRetryDelayMs
  ) where

import Data.Text (Text)

import Automation.Secret (Secret (..), mkSecret)

--------------------------------------------------------------------------------
-- Domain newtypes
--------------------------------------------------------------------------------

data PlatformLimits = PlatformLimits
  { platformMaxCharacters :: Int
  , platformUrlCountLength :: Maybe Int
  } deriving (Show, Eq)

twitterLimits :: PlatformLimits
twitterLimits = PlatformLimits
  { platformMaxCharacters = 280
  , platformUrlCountLength = Just 23
  }

blueskyLimits :: PlatformLimits
blueskyLimits = PlatformLimits
  { platformMaxCharacters = 300
  , platformUrlCountLength = Nothing
  }

mastodonLimits :: PlatformLimits
mastodonLimits = PlatformLimits
  { platformMaxCharacters = 500
  , platformUrlCountLength = Nothing
  }

--------------------------------------------------------------------------------
-- Data types
--------------------------------------------------------------------------------

data ReflectionData = ReflectionData
  { rdDate :: Text
  , rdTitle :: Text
  , rdUrl :: Text
  , rdBody :: Text
  , rdFilePath :: Text
  , rdHasTweetSection :: Bool
  , rdHasBlueskySection :: Bool
  , rdHasMastodonSection :: Bool
  } deriving (Show, Eq)

data TweetResult = TweetResult
  { trId :: Text
  , trText :: Text
  } deriving (Show, Eq)

data BlueskyPostResult = BlueskyPostResult
  { bprUri :: Text
  , bprCid :: Text
  , bprText :: Text
  } deriving (Show, Eq)

data MastodonPostResult = MastodonPostResult
  { mprId :: Text
  , mprUrl :: Text
  , mprText :: Text
  } deriving (Show, Eq)

newtype EmbedResult = EmbedResult
  { erHtml :: Text
  } deriving (Show, Eq)

data EmbedSection = EmbedSection
  { esHeader :: Text
  , esEmbedHtml :: Text
  , esBuildSection :: Text -> Text -> Text
  }

data OgMetadata = OgMetadata
  { ogTitle :: Maybe Text
  , ogDescription :: Maybe Text
  , ogImageUrl :: Maybe Text
  } deriving (Show, Eq)

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
  { mcInstanceUrl :: Text
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

data LinkCard = LinkCard
  { lcUri :: Text
  , lcTitle :: Text
  , lcDescription :: Text
  , lcThumbUrl :: Maybe Text
  } deriving (Show, Eq)

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

twitterHandle :: Text
twitterHandle = "bagrounds"

twitterDisplayName :: Text
twitterDisplayName = "Bryan Grounds"

blueskyDisplayName :: Text
blueskyDisplayName = "Bryan Grounds"

mastodonDisplayName :: Text
mastodonDisplayName = "Bryan Grounds"

tweetSectionHeader :: Text
tweetSectionHeader = "## 🐦 Tweet"

blueskySectionHeader :: Text
blueskySectionHeader = "## 🦋 Bluesky"

mastodonSectionHeader :: Text
mastodonSectionHeader = "## 🐘 Mastodon"

updatesSectionHeader :: Text
updatesSectionHeader = "## 🔄 Updates"

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

blueskyOembedInitialDelayMs :: Int
blueskyOembedInitialDelayMs = 0

blueskyOembedRetryDelayMs :: Int
blueskyOembedRetryDelayMs = 2000
