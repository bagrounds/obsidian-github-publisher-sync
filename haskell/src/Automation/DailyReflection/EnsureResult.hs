module Automation.DailyReflection.EnsureResult
  ( EnsureReflectionResult (..)
  ) where

import Data.Text (Text)

data EnsureReflectionResult = EnsureReflectionResult
  { reflectionCreated :: Bool
  , previousDate      :: Maybe Text
  , forwardLinkAdded  :: Bool
  } deriving (Show, Eq)
