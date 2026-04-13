module Automation.AiBlogLinks
  ( NavLinkResult (..)
  , aiBlogNavPrefix
  , aiBlogConfig
  , buildAiBlogBackLink
  , buildAiBlogForwardLink
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

aiBlogConfig :: BlogSeriesConfig
aiBlogConfig = BlogSeriesConfig
  { bscId           = "ai-blog"
  , bscName         = "AI Blog"
  , bscIcon         = "🤖"
  , bscAuthor       = "[[bryan-grounds]]"
  , bscBaseUrl      = "https://bagrounds.org/ai-blog"
  , bscPriorityUser = Nothing
  , bscNavLink      = "[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]"
  , bscScheduleTime = midnight
  }

aiBlogNavPrefix :: Text
aiBlogNavPrefix = "[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]"

buildAiBlogBackLink :: Text -> Text
buildAiBlogBackLink prevFilename =
  "[[ai-blog/" <> stripMdExt prevFilename <> "|⏮️]]"

buildAiBlogForwardLink :: Text -> Text
buildAiBlogForwardLink nextFilename =
  "[[ai-blog/" <> stripMdExt nextFilename <> "|⏭️]]"

stripMdExt :: Text -> Text
stripMdExt t = fromMaybe t (T.stripSuffix ".md" t)

buildNavLine :: Maybe Text -> Maybe Text -> Text
buildNavLine prevFilename nextFilename =
  let links = catMaybes
        [ fmap buildAiBlogBackLink prevFilename
        , fmap buildAiBlogForwardLink nextFilename
        ]
  in case links of
    [] -> aiBlogNavPrefix
    _  -> aiBlogNavPrefix <> " | " <> T.intercalate " " links

updateNavLinks :: Text -> Maybe Text -> Maybe Text -> Text
updateNavLinks content prevFilename nextFilename =
  let navLine = buildNavLine prevFilename nextFilename
      ls = T.lines content
      navIndex = findIndex (T.isPrefixOf aiBlogNavPrefix) ls
  in case navIndex of
    Nothing -> content
    Just idx ->
      let currentLine = ls !! idx
      in if currentLine == navLine
         then content
         else T.unlines (take idx ls <> [navLine] <> drop (idx + 1) ls)

findIndex :: (a -> Bool) -> [a] -> Maybe Int
findIndex p = go 0
  where
    go _ []     = Nothing
    go i (y:ys) = if p y then Just i else go (i + 1) ys

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
  { nlrFilename :: Text
  , nlrModified :: Bool
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
processFile aiBlogDir files fileCount (idx, filename) = do
  let prevFilename = if idx > 0 then Just (files !! (idx - 1)) else Nothing
      nextFilename = if idx < fileCount - 1 then Just (files !! (idx + 1)) else Nothing
      filePath = aiBlogDir </> T.unpack filename
  content <- TIO.readFile filePath
  if navLinksMatch content prevFilename nextFilename
    then pure NavLinkResult { nlrFilename = filename, nlrModified = False }
    else
      let updated = updateNavLinks content prevFilename nextFilename
      in if updated == content
         then pure NavLinkResult { nlrFilename = filename, nlrModified = False }
         else do
           TIO.writeFile filePath updated
           pure NavLinkResult { nlrFilename = filename, nlrModified = True }

extractAiBlogTitle :: FilePath -> Text -> IO Text
extractAiBlogTitle aiBlogDir filename = do
  let filePath = aiBlogDir </> T.unpack filename
  exists <- doesFileExist filePath
  if exists
    then do
      content <- TIO.readFile filePath
      let (fm, _) = parseFrontmatter content
      pure $ case Map.lookup "title" fm of
        Just title -> title
        Nothing    -> stripMdExt filename
    else pure (stripMdExt filename)

buildReflectionLinks :: FilePath -> [NavLinkResult] -> IO [(Text, Text, Text)]
buildReflectionLinks aiBlogDir results = do
  entries <- traverse (buildEntry aiBlogDir) results
  pure $ filter (\(_, _, d) -> not (T.null d)) entries

buildEntry :: FilePath -> NavLinkResult -> IO (Text, Text, Text)
buildEntry aiBlogDir result = do
  title <- extractAiBlogTitle aiBlogDir (nlrFilename result)
  let relPath = "ai-blog/" <> nlrFilename result
      date = fromMaybe "" (extractPostDate (nlrFilename result))
  pure (relPath, title, date)
