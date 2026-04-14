{-# LANGUAGE OverloadedStrings #-}

module Automation.InternalLinking.CandidateDiscovery
  ( ContentEntry (..)
  , LinkCandidate (..)
  , linkableDirs
  , escapeRegex
  , formatContentEntryWikilink
  , extractContext
  , extractMainTitle
  , contentAlreadyLinksTo
  , buildContentIndex
  , findLinkCandidates
  ) where

import Automation.Frontmatter (parseFrontmatter)
import Automation.InternalLinking.LinkExtraction (hasSuffix)
import Automation.Text (stripEmojis)
import Automation.Types (RelativePath, unRelativePath, mkRelativePath, Title, unTitle, mkTitle)
import Automation.Wikilink (formatWikilink)
import Control.Applicative ((<|>))
import Data.List (sortBy)
import qualified Data.Map.Strict as Map
import Data.Maybe (catMaybes, fromMaybe, maybeToList)
import Data.Ord (Down (..))
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Directory (doesDirectoryExist, listDirectory)
import System.FilePath ((</>))
import Text.Regex.TDFA ((=~))

minTitleLength :: Int
minTitleLength = 8

linkableDirs :: [Text]
linkableDirs = ["books"]

data ContentEntry = ContentEntry
  { relativePath :: RelativePath
  , title        :: Title
  , plainTitle   :: Title
  } deriving (Show, Eq)

data LinkCandidate = LinkCandidate
  { entry       :: ContentEntry
  , matchedText :: Text
  , position    :: Int
  , context     :: Text
  } deriving (Show, Eq)

escapeRegex :: Text -> Text
escapeRegex = T.concatMap escChar
  where
    specials :: Set.Set Char
    specials = Set.fromList ".*+?^${}()|[]\\"
    escChar c
      | Set.member c specials = "\\" <> T.singleton c
      | otherwise             = T.singleton c

formatContentEntryWikilink :: ContentEntry -> Text
formatContentEntryWikilink contentEntry =
  let path = unRelativePath (relativePath contentEntry)
      target = fromMaybe path (T.stripSuffix ".md" path)
  in formatWikilink target (unTitle (title contentEntry))

extractContext :: Text -> Int -> Int -> Text
extractContext content pos matchLen =
  let radius = 100
      start  = max 0 (pos - radius)
      end    = min (T.length content) (pos + matchLen + radius)
      prefix = if start > 0 then "..." else ""
      suffix = if end < T.length content then "..." else ""
      slice  = T.take (end - start) (T.drop start content)
  in prefix <> slice <> suffix

extractMainTitle :: Text -> Maybe Text
extractMainTitle title =
  splitOnColonSpace title <|> splitOnSurroundedDash title
  where
    splitOnColonSpace :: Text -> Maybe Text
    splitOnColonSpace t =
      case T.breakOn ": " t of
        (main, rest)
          | T.null rest                  -> Nothing
          | T.length main < minTitleLength -> Nothing
          | otherwise                     -> Just main
    splitOnSurroundedDash :: Text -> Maybe Text
    splitOnSurroundedDash t =
      case T.breakOn " - " t of
        (main, rest)
          | T.null rest                  -> Nothing
          | T.length main < minTitleLength -> Nothing
          | otherwise                     -> Just main

contentAlreadyLinksTo :: Text -> ContentEntry -> Bool
contentAlreadyLinksTo content contentEntry =
  let path = unRelativePath (relativePath contentEntry)
      pathNoMd = fromMaybe path (T.stripSuffix ".md" path)
  in T.isInfixOf (pathNoMd <> "]") content
  || T.isInfixOf (pathNoMd <> "|") content
  || T.isInfixOf (pathNoMd <> "#") content
  || T.isInfixOf (pathNoMd <> ".") content

buildContentIndex :: FilePath -> IO [ContentEntry]
buildContentIndex contentDir =
  concat <$> traverse (scanDir contentDir) linkableDirs

scanDir :: FilePath -> Text -> IO [ContentEntry]
scanDir contentDir dirName = do
  let dirPath = contentDir </> T.unpack dirName
  exists <- doesDirectoryExist dirPath
  if exists
    then do
      files <- listDirectory dirPath
      let mdFiles = filter (\f -> hasSuffix ".md" f && f /= "index.md") files
      catMaybes <$> traverse (readEntry contentDir dirName) mdFiles
    else pure []

readEntry :: FilePath -> Text -> FilePath -> IO (Maybe ContentEntry)
readEntry contentDir dirName file = do
  let entryRelativePath = dirName <> "/" <> T.pack file
      filePath           = contentDir </> T.unpack entryRelativePath
  content <- TIO.readFile filePath
  let (fm, _) = parseFrontmatter content
  pure $ do
    titleText <- Map.lookup "title" fm
    let plain = stripEmojis titleText
    if T.length plain < minTitleLength
      then Nothing
      else do
        entryPath <- either (const Nothing) Just (mkRelativePath entryRelativePath)
        entryTitle <- either (const Nothing) Just (mkTitle titleText)
        entryPlainTitle <- either (const Nothing) Just (mkTitle plain)
        pure ContentEntry
          { relativePath = entryPath
          , title        = entryTitle
          , plainTitle   = entryPlainTitle
          }

findLinkCandidates :: [ContentEntry] -> Text -> Text -> RelativePath -> [LinkCandidate]
findLinkCandidates index content masked selfPath =
  let sortedIndex = sortBy (\a b -> compare (Down (T.length (unTitle (plainTitle a))))
                                            (Down (T.length (unTitle (plainTitle b))))) index
      (_, candidates) = foldl' findForEntry ([], []) sortedIndex
  in sortBy (\a b -> compare (position a) (position b)) candidates
  where
    findForEntry :: ([(Int, Int)], [LinkCandidate]) -> ContentEntry -> ([(Int, Int)], [LinkCandidate])
    findForEntry (ranges, cands) contentEntry
      | relativePath contentEntry == selfPath = (ranges, cands)
      | contentAlreadyLinksTo content contentEntry = (ranges, cands)
      | any (\c -> relativePath (entry c) == relativePath contentEntry) cands = (ranges, cands)
      | otherwise =
          let titleTexts = unTitle (plainTitle contentEntry) : maybeToList (extractMainTitle (unTitle (plainTitle contentEntry)))
          in tryPatterns ranges cands contentEntry titleTexts

    tryPatterns :: [(Int, Int)] -> [LinkCandidate] -> ContentEntry -> [Text] -> ([(Int, Int)], [LinkCandidate])
    tryPatterns ranges cands _ [] = (ranges, cands)
    tryPatterns ranges cands contentEntry (titleText : rest) =
      let pat     = "\\b" <> T.unpack (escapeRegex titleText) <> "\\b"
          matches = findAllMatches pat (T.unpack masked)
      in case filter (\(p, len) -> not (overlaps ranges p (p + len))) matches of
        []             -> tryPatterns ranges cands contentEntry rest
        ((pos, len):_) ->
          let matched = T.take len (T.drop pos content)
              ctx     = extractContext content pos len
              candidate = LinkCandidate
                { entry       = contentEntry
                , matchedText = matched
                , position    = pos
                , context     = ctx
                }
          in ((pos, pos + len) : ranges, cands <> [candidate])

    overlaps :: [(Int, Int)] -> Int -> Int -> Bool
    overlaps ranges start end =
      any (\(rStart, rEnd) -> start < rEnd && end > rStart) ranges

findAllMatches :: String -> String -> [(Int, Int)]
findAllMatches pat = go 0
  where
    go :: Int -> String -> [(Int, Int)]
    go _offset [] = []
    go offset s =
      case (s =~ pat :: (String, String, String)) of
        (_, "", _)      -> []
        (before, match, after) ->
          let pos = offset + length before
              len = length match
          in (pos, len) : go (pos + len) after
