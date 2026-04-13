{-# LANGUAGE OverloadedStrings #-}

module Automation.InternalLinking.LinkExtraction
  ( extractLinkedPaths
  , findMostRecentReflection
  , bfsTraversal
  , normalizeFilePath
  , makeRelativeTo
  , splitSlash
  , joinSlash
  , hasSuffix
  ) where

import Automation.Frontmatter (parseFrontmatter)
import Automation.Reflection (selectMostRecentReflection)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory)
import System.FilePath (takeBaseName, (</>))
import Text.Regex.TDFA ((=~))

extractLinkedPaths :: Text -> Text -> FilePath -> [Text]
extractLinkedPaths body noteRelativePath contentDir =
  let noteDir = takeDirectory (contentDir </> T.unpack noteRelativePath)
      seen    = Set.empty :: Set.Set Text
  in snd $ foldl' collectLink (seen, [])
       (markdownLinks body noteDir contentDir <> wikiLinks body noteDir contentDir)

collectLink :: (Set.Set Text, [Text]) -> Text -> (Set.Set Text, [Text])
collectLink (seen, acc) rel
  | T.isPrefixOf ".." rel = (seen, acc)
  | Set.member rel seen   = (seen, acc)
  | otherwise             = (Set.insert rel seen, acc <> [rel])

markdownLinks :: Text -> FilePath -> FilePath -> [Text]
markdownLinks body noteDir contentDir = go (T.unpack body)
  where
    go :: String -> [Text]
    go s = case (s =~ ("\\]\\(([^)]+\\.md)\\)" :: String) :: (String, String, String, [String])) of
      (_, _, after, [target])
        | not ("http://" `isPrefixOfS` target) && not ("https://" `isPrefixOfS` target) ->
            let absTarget  = normalizeFilePath (noteDir </> target)
                relPath    = makeRelativeTo contentDir absTarget
            in T.pack relPath : go after
        | otherwise -> go after
      _ -> []

wikiLinks :: Text -> FilePath -> FilePath -> [Text]
wikiLinks body noteDir contentDir =
  let targets = parseWikiLinks (T.unpack body)
  in fmap (resolveWikiTarget noteDir contentDir) targets

resolveWikiTarget :: FilePath -> FilePath -> String -> Text
resolveWikiTarget noteDir contentDir target =
  let trimmed = strip target
      withMd  = if hasSuffix ".md" trimmed then trimmed else trimmed <> ".md"
  in if '/' `elem` withMd
    then T.pack withMd
    else
      let absTarget = normalizeFilePath (noteDir </> withMd)
      in T.pack (makeRelativeTo contentDir absTarget)

parseWikiLinks :: String -> [String]
parseWikiLinks [] = []
parseWikiLinks ('[':'[':rest) =
  case extractWikiLinkTarget rest of
    Just (target, remaining) -> target : parseWikiLinks remaining
    Nothing -> parseWikiLinks rest
parseWikiLinks (_:rest) = parseWikiLinks rest

extractWikiLinkTarget :: String -> Maybe (String, String)
extractWikiLinkTarget input =
  let (target, after) = span (\c -> c /= ']' && c /= '#' && c /= '|') input
  in case after of
    (']':']':rest) | not (null target) -> Just (target, rest)
    ('#':rest) -> skipToClose target rest
    ('|':rest) -> skipToClose target rest
    _ -> Nothing
  where
    skipToClose _ [] = Nothing
    skipToClose t (']':']':rest) | not (null t) = Just (t, rest)
    skipToClose t (_:rest) = skipToClose t rest

isPrefixOfS :: String -> String -> Bool
isPrefixOfS [] _          = True
isPrefixOfS _ []          = False
isPrefixOfS (x:xs) (y:ys) = x == y && isPrefixOfS xs ys

strip :: String -> String
strip = reverse . dropWhile (== ' ') . reverse . dropWhile (== ' ')

normalizeFilePath :: FilePath -> FilePath
normalizeFilePath = joinSlash . reverse . resolve . splitSlash
  where
    resolve :: [String] -> [String]
    resolve = foldl' step []

    step :: [String] -> String -> [String]
    step acc "."      = acc
    step (_:rest) ".." = rest
    step acc seg       = seg : acc

makeRelativeTo :: FilePath -> FilePath -> FilePath
makeRelativeTo base target =
  let baseParts   = splitSlash base
      targetParts = splitSlash target
      common      = length $ takeWhile id $ zipWith (==) baseParts targetParts
      remaining   = drop common targetParts
  in joinSlash remaining

splitSlash :: FilePath -> [String]
splitSlash = fmap T.unpack . filter (not . T.null) . T.splitOn "/" . T.pack

joinSlash :: [String] -> FilePath
joinSlash []     = ""
joinSlash [x]    = x
joinSlash (x:xs) = x </> joinSlash xs

hasSuffix :: String -> String -> Bool
hasSuffix suf str = drop (length str - length suf) str == suf

takeDirectory :: FilePath -> FilePath
takeDirectory = joinSlash . safeInit . splitSlash
  where
    safeInit [] = []
    safeInit xs = init xs

findMostRecentReflection :: FilePath -> IO (Maybe Text)
findMostRecentReflection contentDir = do
  let reflDir = contentDir </> "reflections"
  exists <- doesDirectoryExist reflDir
  if exists
    then selectMostRecentReflection <$> listDirectory reflDir
    else pure Nothing

bfsTraversal :: FilePath -> IO [Text]
bfsTraversal contentDir = do
  mStart <- findMostRecentReflection contentDir
  case mStart of
    Nothing    -> pure []
    Just start -> do
      visitedRef <- newIORef (Set.singleton start)
      queueRef   <- newIORef [start]
      resultRef  <- newIORef ([] :: [Text])
      bfsLoop contentDir visitedRef queueRef resultRef
      reverse <$> readIORef resultRef

bfsLoop :: FilePath -> IORef (Set.Set Text) -> IORef [Text] -> IORef [Text] -> IO ()
bfsLoop contentDir visitedRef queueRef resultRef = do
  queue <- readIORef queueRef
  case queue of
    [] -> pure ()
    (current : rest) -> do
      modifyIORef' queueRef (const rest)
      let filePath = contentDir </> T.unpack current
      exists <- doesFileExist filePath
      let isIndex = takeBaseName (T.unpack current) == "index"
      if exists && not isIndex
        then do
          modifyIORef' resultRef (current :)
          content <- TIO.readFile filePath
          let (_, body) = parseFrontmatter content
              linked    = extractLinkedPaths body current contentDir
          visited <- readIORef visitedRef
          let newLinks = filter (\l -> not (Set.member l visited)) linked
          modifyIORef' visitedRef (\s -> foldl' (flip Set.insert) s newLinks)
          modifyIORef' queueRef (<> newLinks)
          bfsLoop contentDir visitedRef queueRef resultRef
        else bfsLoop contentDir visitedRef queueRef resultRef
