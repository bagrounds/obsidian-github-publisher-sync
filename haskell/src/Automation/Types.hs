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
  , ApiKey (..)
  , DateStr (..)
  , mkApiKey
  , mkDateStr
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
import qualified Data.Text as T

import Data.Maybe (fromMaybe)

--------------------------------------------------------------------------------
-- Domain newtypes
--------------------------------------------------------------------------------

newtype ApiKey = ApiKey { unApiKey :: Text }
  deriving (Eq)

instance Show ApiKey where
  show _ = "ApiKey <redacted>"

mkApiKey :: Text -> Either Text ApiKey
mkApiKey value
  | T.null (T.strip value) = Left "API key must not be empty"
  | otherwise = Right (ApiKey value)

newtype DateStr = DateStr { unDateStr :: Text } deriving (Eq)

instance Show DateStr where
  show (DateStr value) = "DateStr " <> show value

mkDateStr :: Text -> Either Text DateStr
mkDateStr value
  | T.length value /= 10 = Left ("Invalid date length: " <> value)
  | T.index value 4 /= '-' || T.index value 7 /= '-' = Left ("Invalid date separators: " <> value)
  | otherwise = Right (DateStr value)

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

twitterUrlLength :: Int
twitterUrlLength = fromMaybe 0 (platformUrlCountLength twitterLimits)

twitterMaxLength :: Int
twitterMaxLength = platformMaxCharacters twitterLimits

blueskyMaxLength :: Int
blueskyMaxLength = platformMaxCharacters blueskyLimits

mastodonMaxLength :: Int
mastodonMaxLength = platformMaxCharacters mastodonLimits

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
  { tcApiKey :: ApiKey
  , tcApiSecret :: Text
  , tcAccessToken :: Text
  , tcAccessSecret :: Text
  } deriving (Eq)

instance Show TwitterCredentials where
  show tc = "TwitterCredentials {tcApiKey = " <> show (tcApiKey tc)
    <> ", tcApiSecret = <redacted>, tcAccessToken = <redacted>, tcAccessSecret = <redacted>}"

data BlueskyCredentials = BlueskyCredentials
  { bcIdentifier :: Text
  , bcPassword :: Text
  } deriving (Eq)

instance Show BlueskyCredentials where
  show bc = "BlueskyCredentials {bcIdentifier = " <> show (bcIdentifier bc)
    <> ", bcPassword = <redacted>}"

data MastodonCredentials = MastodonCredentials
  { mcInstanceUrl :: Text
  , mcAccessToken :: Text
  } deriving (Eq)

instance Show MastodonCredentials where
  show mc = "MastodonCredentials {mcInstanceUrl = " <> show (mcInstanceUrl mc)
    <> ", mcAccessToken = <redacted>}"

data GeminiConfig = GeminiConfig
  { gcApiKey :: ApiKey
  , gcModel :: Text
  , gcQuestionModel :: Text
  } deriving (Eq)

instance Show GeminiConfig where
  show gc = "GeminiConfig {gcApiKey = " <> show (gcApiKey gc)
    <> ", gcModel = " <> show (gcModel gc)
    <> ", gcQuestionModel = " <> show (gcQuestionModel gc) <> "}"

data ObsidianCredentials = ObsidianCredentials
  { ocAuthToken :: Text
  , ocVaultName :: Text
  , ocVaultPassword :: Maybe Text
  } deriving (Eq)

instance Show ObsidianCredentials where
  show oc = "ObsidianCredentials {ocAuthToken = <redacted>, ocVaultName = "
    <> show (ocVaultName oc) <> ", ocVaultPassword = "
    <> (case ocVaultPassword oc of Nothing -> "Nothing"; Just _ -> "Just <redacted>") <> "}"

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
