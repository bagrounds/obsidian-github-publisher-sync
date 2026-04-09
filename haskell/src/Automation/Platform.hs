module Automation.Platform
  ( PlatformLimits (..)
  , updatesSectionHeader
  ) where

import Data.Text (Text)

data PlatformLimits = PlatformLimits
  { platformMaxCharacters :: Int
  , platformUrlCountLength :: Maybe Int
  } deriving (Show, Eq)

updatesSectionHeader :: Text
updatesSectionHeader = "## 🔄 Updates"
