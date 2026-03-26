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

import Data.Aeson
  ( FromJSON (..)
  , Options
  , ToJSON (..)
  , defaultOptions
  , fieldLabelModifier
  , genericParseJSON
  , genericToJSON
  , omitNothingFields
  )
import Data.Char (toLower)
import Data.Text (Text)
import GHC.Generics (Generic)

aesonOptions :: Int -> Options
aesonOptions prefixLen = defaultOptions
  { fieldLabelModifier = lowercaseFirst . drop prefixLen
  , omitNothingFields = True
  }
  where
    lowercaseFirst []       = []
    lowercaseFirst (c : cs) = toLower c : cs

data ReflectionData = ReflectionData
  { rdDate :: Text
  , rdTitle :: Text
  , rdUrl :: Text
  , rdBody :: Text
  , rdFilePath :: Text
  , rdHasTweetSection :: Bool
  , rdHasBlueskySection :: Bool
  , rdHasMastodonSection :: Bool
  } deriving (Generic, Show, Eq)

instance FromJSON ReflectionData where
  parseJSON = genericParseJSON (aesonOptions 2)

instance ToJSON ReflectionData where
  toJSON = genericToJSON (aesonOptions 2)

data TweetResult = TweetResult
  { trId :: Text
  , trText :: Text
  } deriving (Generic, Show, Eq)

instance FromJSON TweetResult where
  parseJSON = genericParseJSON (aesonOptions 2)

instance ToJSON TweetResult where
  toJSON = genericToJSON (aesonOptions 2)

data BlueskyPostResult = BlueskyPostResult
  { bprUri :: Text
  , bprCid :: Text
  , bprText :: Text
  } deriving (Generic, Show, Eq)

instance FromJSON BlueskyPostResult where
  parseJSON = genericParseJSON (aesonOptions 3)

instance ToJSON BlueskyPostResult where
  toJSON = genericToJSON (aesonOptions 3)

data MastodonPostResult = MastodonPostResult
  { mprId :: Text
  , mprUrl :: Text
  , mprText :: Text
  } deriving (Generic, Show, Eq)

instance FromJSON MastodonPostResult where
  parseJSON = genericParseJSON (aesonOptions 3)

instance ToJSON MastodonPostResult where
  toJSON = genericToJSON (aesonOptions 3)

newtype EmbedResult = EmbedResult
  { erHtml :: Text
  } deriving (Generic, Show, Eq)

instance FromJSON EmbedResult where
  parseJSON = genericParseJSON (aesonOptions 2)

instance ToJSON EmbedResult where
  toJSON = genericToJSON (aesonOptions 2)

data EmbedSection = EmbedSection
  { esHeader :: Text
  , esEmbedHtml :: Text
  , esBuildSection :: Text -> Text -> Text
  }

data OgMetadata = OgMetadata
  { ogTitle :: Maybe Text
  , ogDescription :: Maybe Text
  , ogImageUrl :: Maybe Text
  } deriving (Generic, Show, Eq)

instance FromJSON OgMetadata where
  parseJSON = genericParseJSON (aesonOptions 2)

instance ToJSON OgMetadata where
  toJSON = genericToJSON (aesonOptions 2)

data TwitterCredentials = TwitterCredentials
  { tcApiKey :: Text
  , tcApiSecret :: Text
  , tcAccessToken :: Text
  , tcAccessSecret :: Text
  } deriving (Generic, Show, Eq)

instance FromJSON TwitterCredentials where
  parseJSON = genericParseJSON (aesonOptions 2)

instance ToJSON TwitterCredentials where
  toJSON = genericToJSON (aesonOptions 2)

data BlueskyCredentials = BlueskyCredentials
  { bcIdentifier :: Text
  , bcPassword :: Text
  } deriving (Generic, Show, Eq)

instance FromJSON BlueskyCredentials where
  parseJSON = genericParseJSON (aesonOptions 2)

instance ToJSON BlueskyCredentials where
  toJSON = genericToJSON (aesonOptions 2)

data MastodonCredentials = MastodonCredentials
  { mcInstanceUrl :: Text
  , mcAccessToken :: Text
  } deriving (Generic, Show, Eq)

instance FromJSON MastodonCredentials where
  parseJSON = genericParseJSON (aesonOptions 2)

instance ToJSON MastodonCredentials where
  toJSON = genericToJSON (aesonOptions 2)

data GeminiConfig = GeminiConfig
  { gcApiKey :: Text
  , gcModel :: Text
  , gcQuestionModel :: Text
  } deriving (Generic, Show, Eq)

instance FromJSON GeminiConfig where
  parseJSON = genericParseJSON (aesonOptions 2)

instance ToJSON GeminiConfig where
  toJSON = genericToJSON (aesonOptions 2)

data ObsidianCredentials = ObsidianCredentials
  { ocAuthToken :: Text
  , ocVaultName :: Text
  , ocVaultPassword :: Maybe Text
  } deriving (Generic, Show, Eq)

instance FromJSON ObsidianCredentials where
  parseJSON = genericParseJSON (aesonOptions 2)

instance ToJSON ObsidianCredentials where
  toJSON = genericToJSON (aesonOptions 2)

data EnvironmentConfig = EnvironmentConfig
  { ecTwitter :: Maybe TwitterCredentials
  , ecBluesky :: Maybe BlueskyCredentials
  , ecMastodon :: Maybe MastodonCredentials
  , ecGemini :: GeminiConfig
  , ecObsidian :: ObsidianCredentials
  } deriving (Generic, Show, Eq)

instance FromJSON EnvironmentConfig where
  parseJSON = genericParseJSON (aesonOptions 2)

instance ToJSON EnvironmentConfig where
  toJSON = genericToJSON (aesonOptions 2)

data LinkCard = LinkCard
  { lcUri :: Text
  , lcTitle :: Text
  , lcDescription :: Text
  , lcThumbUrl :: Maybe Text
  } deriving (Generic, Show, Eq)

instance FromJSON LinkCard where
  parseJSON = genericParseJSON (aesonOptions 2)

instance ToJSON LinkCard where
  toJSON = genericToJSON (aesonOptions 2)

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
