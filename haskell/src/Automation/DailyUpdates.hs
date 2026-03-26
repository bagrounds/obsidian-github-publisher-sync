module Automation.DailyUpdates
  ( updatesSectionHeader
  , UpdateLink (..)
  , buildUpdateLink
  , addUpdateLinks
  , extractTitleFromFile
  , addUpdateLinksToReflection
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Directory (doesFileExist)
import System.FilePath ((</>), takeBaseName)

import Automation.DailyReflection (ensureDailyReflection, EnsureReflectionResult (..))
import Automation.Frontmatter (parseFrontmatter)

updatesSectionHeader :: Text
updatesSectionHeader = "## 🔄 Updates"

data UpdateLink = UpdateLink
  { ulRelativePath :: Text
  , ulTitle        :: Text
  } deriving (Show, Eq)

stripMd :: Text -> Text
stripMd path
  | T.isSuffixOf ".md" path = T.dropEnd 3 path
  | otherwise                = path

buildUpdateLink :: Text -> Text -> Text
buildUpdateLink relativePath title =
  "- [[" <> stripMd relativePath <> "|" <> title <> "]]"

linkAlreadyPresent :: Text -> UpdateLink -> Bool
linkAlreadyPresent content ul =
  T.isInfixOf ("[[" <> stripMd (ulRelativePath ul) <> "|") content

addUpdateLinks :: Text -> [UpdateLink] -> Text
addUpdateLinks content links =
  let newLinks = filter (not . linkAlreadyPresent content) links
  in case newLinks of
    [] -> content
    _  ->
      let linkLines = fmap (\ul -> buildUpdateLink (ulRelativePath ul) (ulTitle ul)) newLinks
      in case T.isInfixOf updatesSectionHeader content of
        True  -> insertLinksIntoSection content linkLines
        False -> appendNewSection content linkLines

insertLinksIntoSection :: Text -> [Text] -> Text
insertLinksIntoSection content linkLines =
  let allLines = T.splitOn "\n" content
      sectionIdx = findSectionIndex allLines 0
      insertIdx = skipToInsertPoint allLines (sectionIdx + 1)
      (before, after) = splitAt insertIdx allLines
  in T.intercalate "\n" (before <> linkLines <> after)

findSectionIndex :: [Text] -> Int -> Int
findSectionIndex [] n = n
findSectionIndex (l : rest) n
  | T.isPrefixOf updatesSectionHeader l = n
  | otherwise                           = findSectionIndex rest (n + 1)

skipToInsertPoint :: [Text] -> Int -> Int
skipToInsertPoint allLines idx =
  let atIdx = safeIndex allLines idx
      skippedBlank = case atIdx of
        Just l | T.strip l == "" -> idx + 1
        _                       -> idx
      skippedItems = skipListItems allLines skippedBlank
  in skippedItems

safeIndex :: [a] -> Int -> Maybe a
safeIndex xs i
  | i < 0 || i >= length xs = Nothing
  | otherwise                = Just (xs !! i)

skipListItems :: [Text] -> Int -> Int
skipListItems allLines idx =
  case safeIndex allLines idx of
    Just l | T.isPrefixOf "- " l -> skipListItems allLines (idx + 1)
    _                            -> idx

appendNewSection :: Text -> [Text] -> Text
appendNewSection content linkLines =
  T.stripEnd content <> "\n\n" <> updatesSectionHeader <> "\n\n" <> T.intercalate "\n" linkLines <> "\n"

extractTitleFromFile :: FilePath -> IO Text
extractTitleFromFile filePath = do
  exists <- doesFileExist filePath
  case exists of
    False -> pure (T.pack (takeBaseName filePath))
    True  -> do
      content <- TIO.readFile filePath
      let (frontmatter, _) = parseFrontmatter content
          fallback = T.pack (takeBaseName filePath)
      pure (maybe fallback (\t -> if T.null t then fallback else t) (Map.lookup "title" frontmatter))

addUpdateLinksToReflection :: FilePath -> Text -> [UpdateLink] -> IO Bool
addUpdateLinksToReflection _ _ [] = pure False
addUpdateLinksToReflection reflectionsDir date links = do
  let reflectionPath = reflectionsDir </> T.unpack date <> ".md"
  exists <- doesFileExist reflectionPath
  case exists of
    False -> do
      result <- ensureDailyReflection reflectionsDir date
      case errCreated result of
        True  -> TIO.putStrLn ("  📝 Created daily reflection for " <> date)
        False -> pure ()
    True -> pure ()
  content <- TIO.readFile reflectionPath
  let updated = addUpdateLinks content links
  case updated == content of
    True  -> pure False
    False -> do
      TIO.writeFile reflectionPath updated
      let linkPaths = T.intercalate ", " (fmap ulRelativePath links)
      TIO.putStrLn ("  🔄 Added update link(s) to " <> date <> " reflection: " <> linkPaths)
      pure True
