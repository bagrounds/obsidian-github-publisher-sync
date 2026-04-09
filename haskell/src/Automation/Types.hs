module Automation.Types
  ( -- Re-exported from Automation.Reflection
    ReflectionData (..)
    -- Re-exported from Automation.Platforms.Twitter
  , TwitterCredentials (..)
  , TweetResult (..)
  , twitterLimits
  , twitterHandle
  , twitterDisplayName
  , tweetSectionHeader
    -- Re-exported from Automation.Platforms.Bluesky
  , BlueskyCredentials (..)
  , BlueskyPostResult (..)
  , EmbedResult (..)
  , LinkCard (..)
  , blueskyLimits
  , blueskyDisplayName
  , blueskySectionHeader
  , blueskyOembedInitialDelayMs
  , blueskyOembedRetryDelayMs
    -- Re-exported from Automation.Platforms.Mastodon
  , MastodonCredentials (..)
  , MastodonPostResult (..)
  , mastodonLimits
  , mastodonDisplayName
  , mastodonSectionHeader
    -- Re-exported from Automation.Platforms.OgMetadata
  , OgMetadata (..)
    -- Re-exported from Automation.EmbedSection
  , EmbedSection (..)
    -- Re-exported from Automation.Gemini
  , GeminiConfig (..)
  , defaultGeminiModel
  , defaultQuestionModel
  , gemini3Flash
  , geminiFlashFallback
  , geminiModelFallback
    -- Re-exported from Automation.Env
  , EnvironmentConfig (..)
    -- Re-exported from Automation.ObsidianSync
  , ObsidianCredentials (..)
    -- Re-exported from Automation.Platform
  , PlatformLimits (..)
  , updatesSectionHeader
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

import Automation.EmbedSection (EmbedSection (..))
import Automation.Env (EnvironmentConfig (..))
import Automation.Gemini
  ( GeminiConfig (..)
  , defaultGeminiModel
  , defaultQuestionModel
  , gemini3Flash
  , geminiFlashFallback
  , geminiModelFallback
  )
import Automation.ObsidianSync (ObsidianCredentials (..))
import Automation.Platform (PlatformLimits (..), updatesSectionHeader)
import Automation.Platforms.Bluesky
  ( BlueskyCredentials (..)
  , BlueskyPostResult (..)
  , EmbedResult (..)
  , LinkCard (..)
  , blueskyLimits
  , blueskyDisplayName
  , blueskySectionHeader
  , blueskyOembedInitialDelayMs
  , blueskyOembedRetryDelayMs
  )
import Automation.Platforms.Mastodon
  ( MastodonCredentials (..)
  , MastodonPostResult (..)
  , mastodonLimits
  , mastodonDisplayName
  , mastodonSectionHeader
  )
import Automation.Platforms.OgMetadata (OgMetadata (..))
import Automation.Platforms.Twitter
  ( TwitterCredentials (..)
  , TweetResult (..)
  , twitterLimits
  , twitterHandle
  , twitterDisplayName
  , tweetSectionHeader
  )
import Automation.Reflection (ReflectionData (..))
import Automation.RelativePath (RelativePath, unRelativePath, mkRelativePath)
import Automation.Secret (Secret (..), mkSecret)
import Automation.Title (Title, unTitle, mkTitle)
import Automation.Url (Url, unUrl, mkUrl)
