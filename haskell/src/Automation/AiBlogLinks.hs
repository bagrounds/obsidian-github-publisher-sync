module Automation.AiBlogLinks
  ( NavLinkResult (..)
  , aiBlogNavPrefix
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
import Data.Maybe (mapMaybe)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory)
import System.FilePath ((</>))

import Automation.Frontmatter (parseFrontmatter)

aiBlogNavPrefix :: Text
aiBlogNavPrefix = "[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]"

buildAiBlogBackLink :: Text -> Text
buildAiBlogBackLink prevFilename =
  "[[ai-blog/" <> stripMdExt prevFilename <> "|⏮️]]"

buildAiBlogForwardLink :: Text -> Text
buildAiBlogForwardLink nextFilename =
  "[[ai-blog/" <> stripMdExt nextFilename <> "|⏭️]]"

stripMdExt :: Text -> Text
stripMdExt t = case T.stripSuffix ".md" t of
  Just stripped -> stripped
  Nothing       -> t

buildNavLine :: Maybe Text -> Maybe Text -> Text
buildNavLine prevFilename nextFilename =
  let links = mapMaybe id
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
findIndex p xs = go 0 xs
  where
    go _ []     = Nothing
    go i (y:ys) = if p y then Just i else go (i + 1) ys

navLinksMatch :: Text -> Maybe Text -> Maybe Text -> Bool
navLinksMatch content prevFilename nextFilename =
  let expected = buildNavLine prevFilename nextFilename
  in any (== expected) (T.lines content)

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
  case exists of
    False -> pure []
    True  -> do
      entries <- listDirectory aiBlogDir
      let mdFiles = sort $ filter isPostFile $ fmap T.pack entries
      pure mdFiles

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
  case navLinksMatch content prevFilename nextFilename of
    True -> pure NavLinkResult { nlrFilename = filename, nlrModified = False }
    False ->
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
  case exists of
    False -> pure (stripMdExt filename)
    True  -> do
      content <- TIO.readFile filePath
      let (fm, _) = parseFrontmatter content
      pure $ case Map.lookup "title" fm of
        Just title -> title
        Nothing    -> stripMdExt filename

buildReflectionLinks :: FilePath -> [NavLinkResult] -> IO [(Text, Text, Text)]
buildReflectionLinks aiBlogDir modifiedResults = do
  let modified = filter nlrModified modifiedResults
  entries <- traverse (buildEntry aiBlogDir) modified
  pure $ filter (\(_, _, d) -> not (T.null d)) entries

buildEntry :: FilePath -> NavLinkResult -> IO (Text, Text, Text)
buildEntry aiBlogDir result = do
  title <- extractAiBlogTitle aiBlogDir (nlrFilename result)
  let relPath = "ai-blog/" <> nlrFilename result
      date = case extractPostDate (nlrFilename result) of
        Just d  -> d
        Nothing -> ""
  pure (relPath, title, date)
