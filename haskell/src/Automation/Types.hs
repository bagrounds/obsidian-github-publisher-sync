module Automation.Types
  ( -- Re-exported from Automation.Reflection
    ReflectionData (..)
    -- Re-exported from Automation.Platforms.Twitter
  , TweetResult (..)
    -- Re-exported from Automation.Platforms.Bluesky
  , BlueskyPostResult (..)
    -- Re-exported from Automation.Platforms.Mastodon
  , MastodonPostResult (..)
    -- Re-exported from Automation.Embed
  , EmbedResult (..)
  , EmbedSection (..)
  , OgMetadata (..)
  , LinkCard (..)
    -- Re-exported from Automation.Credentials
  , TwitterCredentials (..)
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
    -- Re-exported from Automation.Platform
  , PlatformLimits (..)
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
    -- Re-exported from Automation.Secret
  , Secret (..)
  , mkSecret
    -- Re-exported from Automation.Url
  , Url
  , unUrl
  , mkUrl
    -- Re-exported from Automation.Title
  , Title
  , unTitle
  , mkTitle
    -- Re-exported from Automation.RelativePath
  , RelativePath
  , unRelativePath
  , mkRelativePath
  ) where

import Automation.Credentials
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
  )
import Automation.Embed (EmbedResult (..), EmbedSection (..), OgMetadata (..), LinkCard (..))
import Automation.Platform
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
  )
import Automation.Platforms.Bluesky (BlueskyPostResult (..))
import Automation.Platforms.Mastodon (MastodonPostResult (..))
import Automation.Platforms.Twitter (TweetResult (..))
import Automation.Reflection (ReflectionData (..))
import Automation.RelativePath (RelativePath, unRelativePath, mkRelativePath)
import Automation.Secret (Secret (..), mkSecret)
import Automation.Title (Title, unTitle, mkTitle)
import Automation.Url (Url, unUrl, mkUrl)
