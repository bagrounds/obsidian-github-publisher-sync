module Automation.Platform
  ( PlatformLimits (..)
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
  , blueskyOembedInitialDelayMs
  , blueskyOembedRetryDelayMs
  ) where

import Data.Text (Text)

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

blueskyOembedInitialDelayMs :: Int
blueskyOembedInitialDelayMs = 0

blueskyOembedRetryDelayMs :: Int
blueskyOembedRetryDelayMs = 2000
