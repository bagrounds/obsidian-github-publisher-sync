module Automation.SocialPosting.LinkExtraction
  ( extractMarkdownLinks
  , parseWikiLinks
  , normalizeFilePath
  , reconstructPath
  ) where

import Data.Char (isSpace)
import Data.List (dropWhileEnd, isPrefixOf, isSuffixOf)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import System.FilePath (takeDirectory, (</>))
import Text.Regex.TDFA ((=~))

extractMarkdownLinks :: Text -> Text -> FilePath -> [Text]
extractMarkdownLinks body noteRelativePath contentDir =
  let noteDir = takeDirectory (contentDir </> T.unpack noteRelativePath)
      seen    = Set.empty :: Set Text
  in snd $ foldl collectLink (seen, [])
       (mdLinks body noteDir contentDir <> wikiLinksFromBody body noteDir contentDir)

collectLink :: (Set Text, [Text]) -> Text -> (Set Text, [Text])
collectLink (seen, acc) rel
  | T.isPrefixOf ".." rel = (seen, acc)
  | Set.member rel seen   = (seen, acc)
  | otherwise             = (Set.insert rel seen, acc <> [rel])

mdLinks :: Text -> FilePath -> FilePath -> [Text]
mdLinks body noteDir contentDir = go (T.unpack body)
  where
    go :: String -> [Text]
    go s = case (s =~ ("\\]\\(([^)]+\\.md)\\)" :: String) :: (String, String, String, [String])) of
      (_, _, after, [target])
        | not ("http://" `isPrefixOf` target) && not ("https://" `isPrefixOf` target) ->
            let absTarget  = normalizeFilePath (noteDir </> target)
                relPath    = makeRelativeTo contentDir absTarget
            in T.pack relPath : go after
        | otherwise -> go after
      _ -> []

wikiLinksFromBody :: Text -> FilePath -> FilePath -> [Text]
wikiLinksFromBody body noteDir contentDir =
  let targets = parseWikiLinks (T.unpack body)
  in fmap (resolveWikiLinkTarget noteDir contentDir) targets

resolveWikiLinkTarget :: FilePath -> FilePath -> String -> Text
resolveWikiLinkTarget noteDir contentDir target =
  let trimmed = dropWhile isSpace (dropWhileEnd isSpace target)
      withMd  = if ".md" `isSuffixOf` trimmed then trimmed else trimmed <> ".md"
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

normalizeFilePath :: FilePath -> FilePath
normalizeFilePath = joinSlash . reverse . resolve . splitSlash
  where
    resolve :: [String] -> [String]
    resolve = foldl step []

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

reconstructPath :: Map Text Text -> Text -> Text -> [Text]
reconstructPath parentMap start target = reverse $ go target
  where
    go current
      | current == start = [current]
      | otherwise = case Map.lookup current parentMap of
          Just parent -> current : go parent
          Nothing     -> [current]
