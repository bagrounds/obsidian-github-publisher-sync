module Automation.AiBlogLinks
  ( NavLinkResult (..)
  , aiBlogNavPrefix
  , aiBlogConfig
  , buildNavLine
  , updateNavLinks
  , navLinksMatch
  , extractPostDate
  , readAiBlogPostFiles
  , ensureAllNavLinks
  , extractAiBlogTitle
  , buildReflectionLinks
  ) where

import Data.List (sort)
import Data.Maybe (catMaybes, fromMaybe)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Data.Time.LocalTime (midnight)
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory)
import System.FilePath ((</>))

import Automation.BlogSeriesConfig (BlogSeriesConfig (..))
import Automation.Frontmatter (parseFrontmatter)
import Automation.Title (Title, mkTitle)
import Automation.Wikilink (buildBackLink, buildForwardLink)

aiBlogConfig :: BlogSeriesConfig
aiBlogConfig = BlogSeriesConfig
  { identifier      = "ai-blog"
  , name            = "AI Blog"
  , icon            = "🤖"
  , author          = "[[bryan-grounds]]"
  , baseUrl         = "https://bagrounds.org/ai-blog"
  , priorityUser    = Nothing
  , navLink         = "[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]"
  , scheduleTime    = midnight
  , contextQueries  = []
  }

aiBlogNavPrefix :: Text
aiBlogNavPrefix = "[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]"

buildNavLine :: Maybe Text -> Maybe Text -> Text
buildNavLine prevFilename nextFilename =
  let links = catMaybes
        [ fmap (buildBackLink aiBlogConfig) prevFilename
        , fmap (buildForwardLink aiBlogConfig) nextFilename
        ]
  in case links of
    [] -> aiBlogNavPrefix
    _  -> aiBlogNavPrefix <> " | " <> T.intercalate " " links

updateNavLinks :: Text -> Maybe Text -> Maybe Text -> Text
updateNavLinks content prevFilename nextFilename =
  let navLine = buildNavLine prevFilename nextFilename
      contentLines = T.lines content
      navIndex = findIndex (T.isPrefixOf aiBlogNavPrefix) contentLines
  in case navIndex of
    Nothing -> content
    Just index ->
      let currentLine = contentLines !! index
      in if currentLine == navLine
         then content
         else T.unlines (take index contentLines <> [navLine] <> drop (index + 1) contentLines)

findIndex :: (a -> Bool) -> [a] -> Maybe Int
findIndex predicate = go 0
  where
    go _ []     = Nothing
    go i (y:ys) = if predicate y then Just i else go (i + 1) ys

navLinksMatch :: Text -> Maybe Text -> Maybe Text -> Bool
navLinksMatch content prevFilename nextFilename =
  let expected = buildNavLine prevFilename nextFilename
  in elem expected (T.lines content)

extractPostDate :: Text -> Maybe Text
extractPostDate filename =
  let prefix = T.take 10 filename
  in if T.length prefix == 10
        && T.index prefix 4 == '-'
        && T.index prefix 7 == '-'
     then Just prefix
     else Nothing

data NavLinkResult = NavLinkResult
  { filename :: Text
  , modified :: Bool
  } deriving (Show, Eq)

readAiBlogPostFiles :: FilePath -> IO [Text]
readAiBlogPostFiles aiBlogDir = do
  exists <- doesDirectoryExist aiBlogDir
  if exists
    then do
      entries <- listDirectory aiBlogDir
      let mdFiles = sort $ filter isPostFile $ fmap T.pack entries
      pure mdFiles
    else pure []

isPostFile :: Text -> Bool
isPostFile f =
  T.isSuffixOf ".md" f && f /= "index.md" && f /= "AGENTS.md"

ensureAllNavLinks :: FilePath -> IO [NavLinkResult]
ensureAllNavLinks aiBlogDir = do
  files <- readAiBlogPostFiles aiBlogDir
  let indexed = zip [0..] files
      fileCount = length files
  traverse (processFile aiBlogDir files fileCount) indexed

processFile :: FilePath -> [Text] -> Int -> (Int, Text) -> IO NavLinkResult
processFile aiBlogDir files fileCount (index, filename) = do
  let prevFilename = if index > 0 then Just (files !! (index - 1)) else Nothing
      nextFilename = if index < fileCount - 1 then Just (files !! (index + 1)) else Nothing
      filePath = aiBlogDir </> T.unpack filename
  content <- TIO.readFile filePath
  if navLinksMatch content prevFilename nextFilename
    then pure NavLinkResult { filename = filename, modified = False }
    else
      let updated = updateNavLinks content prevFilename nextFilename
      in if updated == content
         then pure NavLinkResult { filename = filename, modified = False }
         else do
           TIO.writeFile filePath updated
           pure NavLinkResult { filename = filename, modified = True }

extractAiBlogTitle :: FilePath -> Text -> IO Text
extractAiBlogTitle aiBlogDir filename = do
  let filePath = aiBlogDir </> T.unpack filename
  exists <- doesFileExist filePath
  if exists
    then do
      content <- TIO.readFile filePath
      let (frontmatter, _) = parseFrontmatter content
      pure $ case Map.lookup "title" frontmatter of
        Just title -> title
        Nothing    -> fromMaybe filename (T.stripSuffix ".md" filename)
    else pure (fromMaybe filename (T.stripSuffix ".md" filename))

buildReflectionLinks :: FilePath -> [NavLinkResult] -> IO [(Text, Title, Text)]
buildReflectionLinks aiBlogDir results = do
  entries <- traverse (buildEntry aiBlogDir) results
  pure $ catMaybes entries

buildEntry :: FilePath -> NavLinkResult -> IO (Maybe (Text, Title, Text))
buildEntry aiBlogDir result = do
  titleText <- extractAiBlogTitle aiBlogDir (filename result)
  let relPath = "ai-blog/" <> filename result
  pure $ do
    date <- extractPostDate (filename result)
    validTitle <- either (const Nothing) Just (mkTitle titleText)
    Just (relPath, validTitle, date)
