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
  , twitterHandle
  , twitterDisplayName
  , blueskyDisplayName
  , mastodonDisplayName
  , tweetSectionHeader
  , blueskySectionHeader
  , mastodonSectionHeader
  , twitterUrlLength
  , twitterMaxLength
  , blueskyMaxLength
  , mastodonMaxLength
  , defaultGeminiModel
  , defaultQuestionModel
  , gemini3Flash
  , geminiFlashFallback
  , geminiModelFallback
  , blueskyOembedInitialDelayMs
  , blueskyOembedRetryDelayMs
  ) where

import Data.Text (Text)

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
  { tcApiKey :: Text
  , tcApiSecret :: Text
  , tcAccessToken :: Text
  , tcAccessSecret :: Text
  } deriving (Show, Eq)

data BlueskyCredentials = BlueskyCredentials
  { bcIdentifier :: Text
  , bcPassword :: Text
  } deriving (Show, Eq)

data MastodonCredentials = MastodonCredentials
  { mcInstanceUrl :: Text
  , mcAccessToken :: Text
  } deriving (Show, Eq)

data GeminiConfig = GeminiConfig
  { gcApiKey :: Text
  , gcModel :: Text
  , gcQuestionModel :: Text
  } deriving (Show, Eq)

data ObsidianCredentials = ObsidianCredentials
  { ocAuthToken :: Text
  , ocVaultName :: Text
  , ocVaultPassword :: Maybe Text
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

twitterUrlLength :: Int
twitterUrlLength = 23

twitterMaxLength :: Int
twitterMaxLength = 280

blueskyMaxLength :: Int
blueskyMaxLength = 300

mastodonMaxLength :: Int
mastodonMaxLength = 500

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
