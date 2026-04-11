module Automation.Platform
  ( PlatformLimits (..)
  , updatesSectionHeader
  , Platform (..)
  ) where

import Data.Text (Text)

data Platform = Twitter | Bluesky | Mastodon
  deriving (Show, Eq, Ord)

data PlatformLimits = PlatformLimits
  { platformMaxCharacters :: Int
  , platformUrlCountLength :: Maybe Int
  } deriving (Show, Eq)

updatesSectionHeader :: Text
updatesSectionHeader = "## 🔄 Updates"
