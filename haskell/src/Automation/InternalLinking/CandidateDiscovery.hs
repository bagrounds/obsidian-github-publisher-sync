{-# LANGUAGE OverloadedStrings #-}

module Automation.InternalLinking.CandidateDiscovery
  ( ContentEntry (..)
  , LinkCandidate (..)
  , linkableDirs
  , stripEmojis
  , escapeRegex
  , formatWikilink
  , extractContext
  , extractMainTitle
  , contentAlreadyLinksTo
  , buildContentIndex
  , findLinkCandidates
  ) where

import Automation.Frontmatter (parseFrontmatter)
import Automation.InternalLinking.LinkExtraction (hasSuffix)
import Automation.Text (isEmoji)
import Automation.Types (RelativePath, unRelativePath, mkRelativePath, Title, unTitle, mkTitle)
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
  { ceRelativePath :: RelativePath
  , ceTitle        :: Title
  , cePlainTitle   :: Title
  } deriving (Show, Eq)

data LinkCandidate = LinkCandidate
  { lcEntry       :: ContentEntry
  , lcMatchedText :: Text
  , lcPosition    :: Int
  , lcContext     :: Text
  } deriving (Show, Eq)

stripEmojis :: Text -> Text
stripEmojis =
  T.intercalate " "
    . filter (not . T.null)
    . T.split (== ' ')
    . T.map (\c -> if isEmoji c then ' ' else c)

escapeRegex :: Text -> Text
escapeRegex = T.concatMap escChar
  where
    specials :: Set.Set Char
    specials = Set.fromList ".*+?^${}()|[]\\"
    escChar c
      | Set.member c specials = "\\" <> T.singleton c
      | otherwise             = T.singleton c

formatWikilink :: ContentEntry -> Text
formatWikilink entry =
  let path = unRelativePath (ceRelativePath entry)
      target = fromMaybe path (T.stripSuffix ".md" path)
  in "[[" <> target <> "|" <> unTitle (ceTitle entry) <> "]]"

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
extractMainTitle plainTitle =
  case T.breakOn ": " plainTitle of
    (main, rest)
      | T.null rest        -> Nothing
      | T.length main < minTitleLength -> Nothing
      | countWordsT main < 2 -> Nothing
      | otherwise           -> Just main
  where
    countWordsT :: Text -> Int
    countWordsT t = length $ filter (not . T.null) $ T.split (\c -> c == ' ' || c == '-') t

contentAlreadyLinksTo :: Text -> ContentEntry -> Bool
contentAlreadyLinksTo content entry =
  let path = unRelativePath (ceRelativePath entry)
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
  let relativePath = dirName <> "/" <> T.pack file
      filePath     = contentDir </> T.unpack relativePath
  content <- TIO.readFile filePath
  let (fm, _) = parseFrontmatter content
  pure $ do
    titleText <- Map.lookup "title" fm
    let plain = stripEmojis titleText
    if T.length plain < minTitleLength
      then Nothing
      else do
        path <- either (const Nothing) Just (mkRelativePath relativePath)
        title <- either (const Nothing) Just (mkTitle titleText)
        plainTitle <- either (const Nothing) Just (mkTitle plain)
        pure ContentEntry
          { ceRelativePath = path
          , ceTitle        = title
          , cePlainTitle   = plainTitle
          }

findLinkCandidates :: [ContentEntry] -> Text -> Text -> RelativePath -> [LinkCandidate]
findLinkCandidates index content masked selfPath =
  let sortedIndex = sortBy (\a b -> compare (Down (T.length (unTitle (cePlainTitle a))))
                                            (Down (T.length (unTitle (cePlainTitle b))))) index
      (_, candidates) = foldl' findForEntry ([], []) sortedIndex
  in sortBy (\a b -> compare (lcPosition a) (lcPosition b)) candidates
  where
    findForEntry :: ([(Int, Int)], [LinkCandidate]) -> ContentEntry -> ([(Int, Int)], [LinkCandidate])
    findForEntry (ranges, cands) entry
      | ceRelativePath entry == selfPath = (ranges, cands)
      | contentAlreadyLinksTo content entry = (ranges, cands)
      | any (\c -> ceRelativePath (lcEntry c) == ceRelativePath entry) cands = (ranges, cands)
      | otherwise =
          let titleTexts = unTitle (cePlainTitle entry) : maybeToList (extractMainTitle (unTitle (cePlainTitle entry)))
          in tryPatterns ranges cands entry titleTexts

    tryPatterns :: [(Int, Int)] -> [LinkCandidate] -> ContentEntry -> [Text] -> ([(Int, Int)], [LinkCandidate])
    tryPatterns ranges cands _ [] = (ranges, cands)
    tryPatterns ranges cands entry (titleText : rest) =
      let pat     = "\\b" <> T.unpack (escapeRegex titleText) <> "\\b"
          matches = findAllMatches pat (T.unpack masked)
      in case filter (\(p, len) -> not (overlaps ranges p (p + len))) matches of
        []             -> tryPatterns ranges cands entry rest
        ((pos, len):_) ->
          let matchedText = T.take len (T.drop pos content)
              ctx         = extractContext content pos len
              candidate   = LinkCandidate
                { lcEntry       = entry
                , lcMatchedText = matchedText
                , lcPosition    = pos
                , lcContext     = ctx
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
