module Automation.BlogPosts
  ( BlogPost (..)
  , readSeriesPosts
  , readAgentsMd
  ) where

import Data.List (sortBy)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe)
import Data.Ord (Down (..), comparing)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory)
import System.FilePath ((</>), dropExtension, takeExtension)

import Automation.Frontmatter (parseFrontmatter)

data BlogPost = BlogPost
  { bpFilename :: Text
  , bpDate     :: Text
  , bpTitle    :: Text
  , bpBody     :: Text
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
parsePostFile seriesDir filename = do
  content <- TIO.readFile (seriesDir </> T.unpack filename)
  let (fm, body) = parseFrontmatter content
      title = fromMaybe (T.pack $ dropExtension $ T.unpack filename) (Map.lookup "title" fm)
  pure BlogPost
    { bpFilename = filename
    , bpDate     = extractDate filename
    , bpTitle    = title
    , bpBody     = body
    }

readSeriesPosts :: FilePath -> IO [BlogPost]
readSeriesPosts seriesDir = do
  exists <- doesDirectoryExist seriesDir
  case exists of
    False -> pure []
    True  -> do
      entries <- listDirectory seriesDir
      let mdFiles = filter isPostFile $ fmap T.pack entries
      posts <- traverse (parsePostFile seriesDir) mdFiles
      pure $ sortBy (comparing (Down . bpFilename)) posts

readAgentsMd :: FilePath -> IO Text
readAgentsMd seriesDir = do
  let agentsPath = seriesDir </> "AGENTS.md"
  exists <- doesFileExist agentsPath
  case exists of
    False -> pure ""
    True  -> do
      raw <- TIO.readFile agentsPath
      let (_, body) = parseFrontmatter raw
      pure $ T.strip body
