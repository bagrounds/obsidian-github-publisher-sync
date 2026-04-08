module Automation.Reflection
  ( selectMostRecentReflection
  , findMostRecentReflection
  ) where

import Data.List (sortBy)
import Data.Text (Text)
import qualified Data.Text as T
import System.Directory (doesDirectoryExist, listDirectory)
import System.FilePath ((</>))
import Text.Regex.TDFA ((=~))

selectMostRecentReflection :: [String] -> Maybe Text
selectMostRecentReflection files =
  let datePattern = "^[0-9]{4}-[0-9]{2}-[0-9]{2}\\.md$" :: String
      dateFiles   = filter (\f -> (f :: String) =~ datePattern) files
      sorted      = sortBy (flip compare) dateFiles
  in case sorted of
    (f : _) -> Just ("reflections/" <> T.pack f)
    []      -> Nothing

findMostRecentReflection :: FilePath -> IO (Maybe Text)
findMostRecentReflection contentDir = do
  let reflDir = contentDir </> "reflections"
  exists <- doesDirectoryExist reflDir
  case exists of
    False -> pure Nothing
    True  -> selectMostRecentReflection <$> listDirectory reflDir
