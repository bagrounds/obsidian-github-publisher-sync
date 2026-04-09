module Automation.DailyUpdates
  ( updatesSectionHeader
  , UpdateLink (..)
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
import Automation.Types (updatesSectionHeader, RelativePath (..), Title (..))

data UpdateLink = UpdateLink
  { ulRelativePath :: RelativePath
  , ulTitle        :: Title
  , ulDetails      :: [Text]
  } deriving (Show, Eq)

stripMd :: Text -> Text
stripMd path
  | T.isSuffixOf ".md" path = T.dropEnd 3 path
  | otherwise                = path

buildUpdateLink :: Text -> Text -> Text
buildUpdateLink relativePath title =
  "- [[" <> stripMd relativePath <> "|" <> title <> "]]"

buildPageEntry :: Text -> Text -> [Text] -> [Text]
buildPageEntry path title details =
  buildUpdateLink path title : fmap ("  - " <>) details

extractUpdatesText :: Text -> Text
extractUpdatesText content =
  case T.breakOn updatesSectionHeader content of
    (_, "") -> ""
    (_, sectionStart) ->
      let afterHeader = T.drop (T.length updatesSectionHeader) sectionStart
      in case T.breakOn "\n## " afterHeader of
        (section, _) -> section

pagePresent :: Text -> Text -> Bool
pagePresent updatesText path = T.isInfixOf ("[[" <> stripMd path <> "|") updatesText

detailPresent :: Text -> Text -> Bool
detailPresent updatesText detail = T.isInfixOf ("  - " <> detail) updatesText

extractPageBullets :: Text -> Text -> Text
extractPageBullets updatesText path =
  let pageNeedle = "[[" <> stripMd path <> "|"
      allLines = T.splitOn "\n" updatesText
      pageIdx = findLineContaining pageNeedle allLines 0
  in case pageIdx < length allLines of
    False -> ""
    True  ->
      let subLines = takeWhile (\l -> T.isPrefixOf "  - " l) (drop (pageIdx + 1) allLines)
      in T.intercalate "\n" subLines

addUpdateLinks :: Text -> [UpdateLink] -> Text
addUpdateLinks content [] = content
addUpdateLinks content links = foldl addSingleUpdate content links

addSingleUpdate :: Text -> UpdateLink -> Text
addSingleUpdate content (UpdateLink pathNewtype titleNewtype details) =
  let path = unRelativePath pathNewtype
      title = unTitle titleNewtype
      updatesText = extractUpdatesText content
      pageBullets = extractPageBullets updatesText path
      newDetails = filter (not . detailPresent pageBullets) details
  in case newDetails of
    [] -> content
    _  | not (T.isInfixOf updatesSectionHeader content) ->
           appendNewSection content path title newDetails
       | not (pagePresent updatesText path) ->
           appendPageToSection content path title newDetails
       | otherwise ->
           insertDetailsUnderPage content path newDetails

appendNewSection :: Text -> Text -> Text -> [Text] -> Text
appendNewSection content path title details =
  let entryLines = buildPageEntry path title details
      sectionBlock = updatesSectionHeader
        <> "\n" <> T.intercalate "\n" entryLines <> "\n"
  in case findFirstSectionIndex embedSectionHeaders content of
    Just idx ->
      let (before, after) = T.splitAt idx content
      in T.stripEnd before <> "\n\n" <> sectionBlock <> "\n" <> after
    Nothing ->
      T.stripEnd content <> "\n\n" <> sectionBlock

appendPageToSection :: Text -> Text -> Text -> [Text] -> Text
appendPageToSection content path title details =
  let allLines = T.splitOn "\n" content
      updateIdx = findLineIndex updatesSectionHeader allLines 0
      endIdx = findNextH2OrEnd allLines (updateIdx + 1)
      (before, after) = splitAt endIdx allLines
      trimmedBefore = dropTrailingBlanks before
      entryLines = buildPageEntry path title details
  in T.intercalate "\n" (trimmedBefore <> entryLines <> [""] <> after)

insertDetailsUnderPage :: Text -> Text -> [Text] -> Text
insertDetailsUnderPage content path details =
  let allLines = T.splitOn "\n" content
      pageNeedle = "[[" <> stripMd path <> "|"
      pageIdx = findLineContaining pageNeedle allLines 0
      insertIdx = skipSubBullets allLines (pageIdx + 1)
      detailLines = fmap ("  - " <>) details
      (before, after) = splitAt insertIdx allLines
  in T.intercalate "\n" (before <> detailLines <> after)

findLineIndex :: Text -> [Text] -> Int -> Int
findLineIndex _ [] n = n
findLineIndex header (l : rest) n
  | T.isPrefixOf header l = n
  | otherwise              = findLineIndex header rest (n + 1)

findLineContaining :: Text -> [Text] -> Int -> Int
findLineContaining _ [] n = n
findLineContaining needle (l : rest) n
  | T.isInfixOf needle l = n
  | otherwise             = findLineContaining needle rest (n + 1)

findNextH2OrEnd :: [Text] -> Int -> Int
findNextH2OrEnd allLines idx
  | idx >= length allLines = length allLines
  | T.isPrefixOf "## " (safeIdx allLines idx) = idx
  | otherwise = findNextH2OrEnd allLines (idx + 1)

safeIdx :: [Text] -> Int -> Text
safeIdx xs i
  | i >= 0 && i < length xs = xs !! i
  | otherwise                = ""

safeIndex :: [a] -> Int -> Maybe a
safeIndex xs i
  | i < 0 || i >= length xs = Nothing
  | otherwise                = Just (xs !! i)

skipSubBullets :: [Text] -> Int -> Int
skipSubBullets allLines idx =
  case safeIndex allLines idx of
    Just l | T.isPrefixOf "  - " l -> skipSubBullets allLines (idx + 1)
    _                              -> idx

dropTrailingBlanks :: [Text] -> [Text]
dropTrailingBlanks = reverse . dropWhile (\l -> T.strip l == "") . reverse

extractTitleFromFile :: FilePath -> IO Text
extractTitleFromFile filePath = do
  exists <- doesFileExist filePath
  case exists of
    False -> pure (T.pack (takeBaseName filePath))
    True  -> do
      fileContent <- TIO.readFile filePath
      let (frontmatter, _) = parseFrontmatter fileContent
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
  fileContent <- TIO.readFile reflectionPath
  let updated = addUpdateLinks fileContent links
  case updated == fileContent of
    True  -> pure False
    False -> do
      TIO.writeFile reflectionPath updated
      let linkPaths = T.intercalate ", " (fmap (unRelativePath . ulRelativePath) links)
      TIO.putStrLn ("  🔄 Added update link(s) to " <> date <> " reflection: " <> linkPaths)
      pure True
