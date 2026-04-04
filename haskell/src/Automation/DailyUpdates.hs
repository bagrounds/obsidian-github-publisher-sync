module Automation.DailyUpdates
  ( updatesSectionHeader
  , UpdateLink (..)
  , UpdateCategory (..)
  , categorySubHeader
  , buildUpdateLink
  , addUpdateLinks
  , extractTitleFromFile
  , addUpdateLinksToReflection
  ) where

import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Directory (doesFileExist)
import System.FilePath ((</>), takeBaseName)

import Automation.DailyReflection (ensureDailyReflection, EnsureReflectionResult (..), findFirstSectionIndex, embedSectionHeaders)
import Automation.Frontmatter (parseFrontmatter)
import Automation.Types (updatesSectionHeader)

data UpdateCategory
  = ImageUpdate
  | InternalLinkUpdate
  | SocialPostUpdate
  deriving (Show, Eq, Ord)

categorySubHeader :: UpdateCategory -> Text
categorySubHeader ImageUpdate        = "### 🖼️ Images"
categorySubHeader InternalLinkUpdate = "### 🔗 Internal Links"
categorySubHeader SocialPostUpdate   = "### 📢 Social Posts"

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

extractUpdatesSection :: Text -> Text
extractUpdatesSection content
  | not (T.isInfixOf updatesSectionHeader content) = ""
  | otherwise =
      let allLines = T.splitOn "\n" content
          updateIdx = findLineIndex updatesSectionHeader allLines 0
          endIdx = findNextH2OrEnd allLines (updateIdx + 1)
      in T.intercalate "\n" (take (endIdx - updateIdx) (drop updateIdx allLines))

addUpdateLinks :: Text -> UpdateCategory -> [UpdateLink] -> Text
addUpdateLinks content category links =
  let updatesSection = extractUpdatesSection content
      newLinks = filter (not . linkAlreadyPresent updatesSection) links
  in case newLinks of
    [] -> content
    _  ->
      let linkLines = fmap (\ul -> buildUpdateLink (ulRelativePath ul) (ulTitle ul)) newLinks
          subHeader = categorySubHeader category
      in case (T.isInfixOf updatesSectionHeader content, T.isInfixOf subHeader content) of
        (False, _)    -> appendNewCategorizedSection content subHeader linkLines
        (True, False) -> appendSubSection content subHeader linkLines
        (True, True)  -> insertLinksIntoSubSection content subHeader linkLines

appendNewCategorizedSection :: Text -> Text -> [Text] -> Text
appendNewCategorizedSection content subHeader linkLines =
  let sectionBlock = updatesSectionHeader
        <> "\n\n" <> subHeader
        <> "\n\n" <> T.intercalate "\n" linkLines <> "\n"
  in case findFirstSectionIndex embedSectionHeaders content of
    Just idx ->
      let (before, after) = T.splitAt idx content
      in T.stripEnd before <> "\n\n" <> sectionBlock <> "\n" <> after
    Nothing ->
      T.stripEnd content <> "\n\n" <> sectionBlock

insertLinksIntoSubSection :: Text -> Text -> [Text] -> Text
insertLinksIntoSubSection content subHeader linkLines =
  let allLines = T.splitOn "\n" content
      subIdx = findLineIndex subHeader allLines 0
      insertIdx = skipToInsertPoint allLines (subIdx + 1)
      (before, after) = splitAt insertIdx allLines
  in T.intercalate "\n" (before <> linkLines <> after)

appendSubSection :: Text -> Text -> [Text] -> Text
appendSubSection content subHeader linkLines =
  let allLines = T.splitOn "\n" content
      updateIdx = findLineIndex updatesSectionHeader allLines 0
      endIdx = findNextH2OrEnd allLines (updateIdx + 1)
      (before, after) = splitAt endIdx allLines
      trimmedBefore = dropTrailingBlanks before
  in T.intercalate "\n" (trimmedBefore <> ["", subHeader, ""] <> linkLines <> [""] <> after)

findLineIndex :: Text -> [Text] -> Int -> Int
findLineIndex _ [] n = n
findLineIndex header (l : rest) n
  | T.isPrefixOf header l = n
  | otherwise              = findLineIndex header rest (n + 1)

findNextH2OrEnd :: [Text] -> Int -> Int
findNextH2OrEnd allLines idx
  | idx >= length allLines = length allLines
  | T.isPrefixOf "## " (safeIdx allLines idx) = idx
  | otherwise = findNextH2OrEnd allLines (idx + 1)

safeIdx :: [Text] -> Int -> Text
safeIdx xs i
  | i >= 0 && i < length xs = xs !! i
  | otherwise                = ""

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

dropTrailingBlanks :: [Text] -> [Text]
dropTrailingBlanks = reverse . dropWhile (\l -> T.strip l == "") . reverse

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

addUpdateLinksToReflection :: FilePath -> Text -> UpdateCategory -> [UpdateLink] -> IO Bool
addUpdateLinksToReflection _ _ _ [] = pure False
addUpdateLinksToReflection reflectionsDir date category links = do
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
  let updated = addUpdateLinks content category links
  case updated == content of
    True  -> pure False
    False -> do
      TIO.writeFile reflectionPath updated
      let linkPaths = T.intercalate ", " (fmap ulRelativePath links)
      TIO.putStrLn ("  🔄 Added update link(s) to " <> date <> " reflection: " <> linkPaths)
      pure True
