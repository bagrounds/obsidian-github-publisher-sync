module Automation.InternalLinking
  ( LinkingResult (..)
  , FileResult (..)
  , run
  , defaultLinkingModel
  ) where

import Data.Text (Text)
import qualified Data.Text as T

data FileResult = FileResult
  { frRelativePath :: Text
  , frModified     :: Bool
  , frLinksAdded   :: Int
  } deriving (Show, Eq)

data LinkingResult = LinkingResult
  { lrFilesVisited  :: Int
  , lrFilesModified :: Int
  , lrTotalLinksAdded :: Int
  , lrFilesSkipped  :: Int
  , lrFileResults   :: [FileResult]
  } deriving (Show, Eq)

defaultLinkingModel :: Text
defaultLinkingModel = "gemini-2.5-flash"

run :: Text -> FilePath -> IO LinkingResult
run _model _dir = pure LinkingResult
  { lrFilesVisited = 0
  , lrFilesModified = 0
  , lrTotalLinksAdded = 0
  , lrFilesSkipped = 0
  , lrFileResults = []
  }

_unused :: Text
_unused = T.empty
