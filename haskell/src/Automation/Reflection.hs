module Automation.Reflection
  ( ReflectionData (..)
  , selectMostRecentReflection
  , findMostRecentReflection
  , eligibleReflectionDays
  ) where

import Data.List (sortBy)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (Day, LocalTime, addDays, localDay)
import System.Directory (doesDirectoryExist, listDirectory)
import System.FilePath ((</>))
import Text.Regex.TDFA ((=~))

import Automation.Title (Title)
import Automation.Url (Url)

data ReflectionData = ReflectionData
  { date :: Text
  , title :: Title
  , url :: Url
  , body :: Text
  , filePath :: Text
  , hasTweetSection :: Bool
  , hasBlueskySection :: Bool
  , hasMastodonSection :: Bool
  } deriving (Show, Eq)

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
  if exists
    then selectMostRecentReflection <$> listDirectory reflDir
    else pure Nothing

eligibleReflectionDays :: LocalTime -> (Day -> LocalTime) -> [Day]
eligibleReflectionDays localNow eligibilityCutoff =
  let today = localDay localNow
      candidateDays = map (\offset -> addDays (-offset) today) [0..4]
  in filter (\day -> localNow >= eligibilityCutoff day) candidateDays
