module Automation.BlogPosts
  ( BlogPost (..)
  , readSeriesPosts
  , readAgentsMd
  ) where

import Data.List (sortOn)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe)
import Data.Ord (Down (..))
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory)
import System.FilePath ((</>), dropExtension)

import Automation.Frontmatter (parseFrontmatter)

data BlogPost = BlogPost
  { filename :: Text
  , date     :: Text
  , title    :: Text
  , body     :: Text
  } deriving (Show, Eq)

excludedFiles :: [Text]
excludedFiles = ["index.md", "AGENTS.md"]

isPostFile :: Text -> Bool
isPostFile filename =
  T.isSuffixOf ".md" filename && notElem filename excludedFiles

extractDate :: Text -> Text
extractDate filename =
  let prefix = T.take 10 filename
  in if T.length prefix == 10
        && T.index prefix 4 == '-'
        && T.index prefix 7 == '-'
     then prefix
     else ""

parsePostFile :: FilePath -> Text -> IO BlogPost
parsePostFile seriesDirectory filename = do
  content <- TIO.readFile (seriesDirectory </> T.unpack filename)
  let (frontmatter, body) = parseFrontmatter content
      title = fromMaybe (T.pack $ dropExtension $ T.unpack filename) (Map.lookup "title" frontmatter)
  pure BlogPost
    { filename = filename
    , date     = extractDate filename
    , title    = title
    , body     = body
    }

readSeriesPosts :: FilePath -> IO [BlogPost]
readSeriesPosts seriesDirectory = do
  exists <- doesDirectoryExist seriesDirectory
  if exists
    then do
      entries <- listDirectory seriesDirectory
      let mdFiles = filter isPostFile $ fmap T.pack entries
      posts <- traverse (parsePostFile seriesDirectory) mdFiles
      pure $ sortOn (Down . filename) posts
    else pure []

readAgentsMd :: FilePath -> IO Text
readAgentsMd seriesDirectory = do
  let agentsPath = seriesDirectory </> "AGENTS.md"
  exists <- doesFileExist agentsPath
  if exists
    then do
      raw <- TIO.readFile agentsPath
      let (_, body) = parseFrontmatter raw
      pure $ T.strip body
    else pure ""
