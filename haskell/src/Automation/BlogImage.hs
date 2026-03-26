module Automation.BlogImage
  ( ImageProvider (..)
  , BackfillResult (..)
  , processNote
  , backfillImages
  , resolveImageProvider
  , resolveImageProviders
  , syncMarkdownDir
  , syncAttachmentsDir
  ) where

import Data.Text (Text)
import qualified Data.Text as T

data ImageProvider = ImageProvider
  { ipName           :: Text
  , ipApiKey         :: Text
  , ipModel          :: Text
  , ipGenerator      :: Text -> IO (Maybe Text)
  , ipDescribePrompt :: Text -> Text
  }

data BackfillResult = BackfillResult
  { brImagesGenerated :: Int
  , brFilesUpdated    :: Int
  , brFilesSkipped    :: Int
  , brErrors          :: [Text]
  } deriving (Show, Eq)

emptyBackfillResult :: BackfillResult
emptyBackfillResult = BackfillResult 0 0 0 []

processNote :: ImageProvider -> FilePath -> IO (Maybe Text)
processNote _provider _notePath = pure Nothing

backfillImages :: [ImageProvider] -> FilePath -> IO BackfillResult
backfillImages _providers _dir = pure emptyBackfillResult

resolveImageProvider :: Text -> Text -> Maybe ImageProvider
resolveImageProvider _name _apiKey = Nothing

resolveImageProviders :: [(Text, Text)] -> [ImageProvider]
resolveImageProviders = foldr go []
  where
    go (name, key) acc = case resolveImageProvider name key of
      Just p  -> p : acc
      Nothing -> acc

syncMarkdownDir :: FilePath -> FilePath -> IO ()
syncMarkdownDir _src _dst = pure ()

syncAttachmentsDir :: FilePath -> FilePath -> IO ()
syncAttachmentsDir _src _dst = pure ()

_unused :: Text
_unused = T.empty
