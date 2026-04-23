module Automation.DailyUpdates
  ( UpdateDetail (..)
  , UpdateLink (..)
  , addUpdateLinks
  , extractTitleFromFile
  , addUpdateLinksToReflection
  , buildChangesPageContent
  , buildChangesIndexContent
  , addChangesForwardLink
  , parseStatsPageCount
  , resolveRelativePath
  , extractStatsLine
  ) where

import Control.Applicative ((<|>))
import Control.Monad (unless, when)
import Data.Char (isDigit)
import Data.List (find, sort)
import qualified Data.Map.Strict as Map
import Data.Maybe (catMaybes, fromMaybe, mapMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Data.Time (Day)
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, doesFileExist, listDirectory)
import System.FilePath ((</>), dropExtension, takeBaseName)
import Text.Read (readMaybe)

import Automation.DailyReflection (ensureDailyReflection, findFirstSectionIndex, embedSectionHeaders, upsertChangesPreview, ChangesStats (..), renderChangesStats)
import Automation.DailyReflection.EnsureResult (EnsureReflectionResult (..))
import Automation.Frontmatter (parseFrontmatter, quoteYamlValue)
import Automation.PacificTime (formatDay)
import Automation.Platform (Platform (..), updatesSectionHeader)
import Automation.RelativePath (RelativePath, unRelativePath)
import Automation.Title (Title, unTitle)
import Automation.Wikilink (formatWikilink, NavigableDirectory (..), directoryIndexLink, buildNavBackLink, insertForwardNavLink)

-- | Types of updates that can be made to a page
data UpdateDetail
  = ImageAdded
  | InternalLinksAdded Int
  | PostedTo Platform
  deriving (Show, Eq, Ord)

-- | A link to an updated page with its details
data UpdateLink = UpdateLink
  { updateRelativePath :: RelativePath
  , updateTitle        :: Title
  , updateDetails      :: [UpdateDetail]
  } deriving (Show, Eq)

-- | Internal representation of a parsed page entry
data PageEntry = PageEntry
  { entryPath    :: Text
  , entryTitle   :: Text
  , entryDetails :: [UpdateDetail]
  } deriving (Show, Eq)

-- Column identity: two details belong to the same column when their structure matches
sameColumn :: UpdateDetail -> UpdateDetail -> Bool
sameColumn ImageAdded ImageAdded                     = True
sameColumn (InternalLinksAdded _) (InternalLinksAdded _) = True
sameColumn (PostedTo a) (PostedTo b)                 = a == b
sameColumn _ _                                       = False

-- Canonical column ordering determines table layout
canonicalColumns :: [UpdateDetail]
canonicalColumns =
  [ ImageAdded
  , InternalLinksAdded 0
  , PostedTo Bluesky
  , PostedTo Mastodon
  , PostedTo Twitter
  ]

columnEmoji :: UpdateDetail -> Text
columnEmoji ImageAdded            = "🖼️"
columnEmoji (InternalLinksAdded _) = "🔗"
columnEmoji (PostedTo Bluesky)    = "🦋"
columnEmoji (PostedTo Mastodon)   = "🐘"
columnEmoji (PostedTo Twitter)    = "🐦"

cellText :: UpdateDetail -> Text
cellText (InternalLinksAdded n) = T.pack (show n)
cellText detail                 = columnEmoji detail

escapeTablePipe :: Text -> Text
escapeTablePipe = T.replace "|" "\\|"

unescapeTablePipe :: Text -> Text
unescapeTablePipe = T.replace "\\|" "|"

-- Serialization for backward compatibility with bullet format
detailFromText :: Text -> Maybe UpdateDetail
detailFromText text
  | text == "🖼️ added image"       = Just ImageAdded
  | "🔗 added " `T.isPrefixOf` text = parseInternalLinks text
  | text == "🦋 posted to BlueSky"  = Just (PostedTo Bluesky)
  | text == "🐘 posted to Mastodon" = Just (PostedTo Mastodon)
  | text == "🐦 posted to Twitter"  = Just (PostedTo Twitter)
  | otherwise                       = Nothing
  where
    parseInternalLinks source =
      let stripped = T.drop (T.length "🔗 added ") source
          numberText = T.takeWhile (/= ' ') stripped
      in InternalLinksAdded <$> readMaybe (T.unpack numberText)

emojiToColumnRepresentative :: Text -> Maybe UpdateDetail
emojiToColumnRepresentative "🖼️" = Just ImageAdded
emojiToColumnRepresentative "🔗"  = Just (InternalLinksAdded 0)
emojiToColumnRepresentative "🦋"  = Just (PostedTo Bluesky)
emojiToColumnRepresentative "🐘"  = Just (PostedTo Mastodon)
emojiToColumnRepresentative "🐦"  = Just (PostedTo Twitter)
emojiToColumnRepresentative _     = Nothing

parseCellToDetail :: UpdateDetail -> Text -> Maybe UpdateDetail
parseCellToDetail (InternalLinksAdded _) num = InternalLinksAdded <$> readMaybe (T.unpack num)
parseCellToDetail column cell
  | cell == cellText column = Just column
  | cell == "✓"             = Just column
  | otherwise               = Nothing

-- Merging: combine two details of the same column
mergeDetail :: UpdateDetail -> UpdateDetail -> UpdateDetail
mergeDetail (InternalLinksAdded existing) (InternalLinksAdded incoming) = InternalLinksAdded (existing + incoming)
mergeDetail _ incoming = incoming

mergeDetailLists :: [UpdateDetail] -> [UpdateDetail] -> [UpdateDetail]
mergeDetailLists = foldl' mergeOneDetail
  where
    mergeOneDetail existing incoming
      | any (sameColumn incoming) existing =
          fmap (\detail -> if sameColumn detail incoming then mergeDetail detail incoming else detail) existing
      | otherwise = existing <> [incoming]

mergeEntries :: [PageEntry] -> [PageEntry] -> [PageEntry]
mergeEntries = foldl' mergeOneEntry
  where
    mergeOneEntry entries incoming
      | any (\entry -> entryPath entry == entryPath incoming) entries =
          fmap (\entry ->
            if entryPath entry == entryPath incoming
              then entry { entryDetails = mergeDetailLists (entryDetails entry) (entryDetails incoming) }
              else entry) entries
      | otherwise = entries <> [incoming]

-- Parsing existing updates section
stripMd :: Text -> Text
stripMd path
  | T.isSuffixOf ".md" path = T.dropEnd 3 path
  | otherwise                = path

extractSectionText :: Text -> Text
extractSectionText content =
  case T.breakOn updatesSectionHeader content of
    (_, "") -> ""
    (_, sectionStart) ->
      let afterHeader = T.drop (T.length updatesSectionHeader) sectionStart
      in fst (T.breakOn "\n## " afterHeader)

isPageHeaderLine :: Text -> Bool
isPageHeaderLine = ("Page" `elem`) . splitSimpleCells

parseExistingEntries :: Text -> [PageEntry]
parseExistingEntries sectionText
  | T.null sectionText = []
  | any isPageHeaderLine (T.splitOn "\n" sectionText) = parseTableEntries sectionText
  | otherwise = parseBulletEntries sectionText

parseBulletEntries :: Text -> [PageEntry]
parseBulletEntries = mapMaybe parseBulletGroup . groupBullets . T.splitOn "\n"

groupBullets :: [Text] -> [(Text, [Text])]
groupBullets [] = []
groupBullets (line : rest)
  | "- [[" `T.isPrefixOf` line =
      let (subBullets, remaining) = span (T.isPrefixOf "  - ") rest
      in (line, fmap (T.drop 4) subBullets) : groupBullets remaining
  | otherwise = groupBullets rest

parseBulletGroup :: (Text, [Text]) -> Maybe PageEntry
parseBulletGroup (pageLine, detailTexts) = do
  (path, title) <- parseWikiLinkLine pageLine
  let details = mapMaybe detailFromText detailTexts
  pure (PageEntry path title details)

parseWikiLinkLine :: Text -> Maybe (Text, Text)
parseWikiLinkLine line = do
  let afterPrefix = T.drop (T.length "- [[") line
  case T.breakOn "|" afterPrefix of
    (_, "") -> Nothing
    (path, rest) ->
      case T.breakOn "]]" (T.drop 1 rest) of
        (title, suffix) | not (T.null suffix) -> Just (path, title)
        _ -> Nothing

parseTableEntries :: Text -> [PageEntry]
parseTableEntries sectionText =
  let contentLines = filter (not . T.null) (T.splitOn "\n" sectionText)
      headerLine = find isPageHeaderLine contentLines
      dataRows = case break isPageHeaderLine contentLines of
        (_, _ : rest) -> case rest of
          (_ : rows) -> filter isDataRow rows
          _          -> []
        _ -> []
  in case headerLine of
    Nothing     -> []
    Just header ->
      let columns = parseHeaderColumns header
      in mapMaybe (parseTableRow columns) dataRows

isDataRow :: Text -> Bool
isDataRow line =
  let stripped = T.strip line
  in T.isInfixOf "[[" stripped || T.isInfixOf "](" stripped

parseHeaderColumns :: Text -> [UpdateDetail]
parseHeaderColumns header =
  case splitSimpleCells header of
    (_ : columnCells) -> mapMaybe (emojiToColumnRepresentative . T.strip) columnCells
    _                 -> []

splitSimpleCells :: Text -> [Text]
splitSimpleCells line =
  let trimmed = T.strip line
      stripped = fromMaybe trimmed (T.stripPrefix "|" trimmed >>= T.stripSuffix "|" . T.strip)
  in fmap T.strip (T.splitOn "|" stripped)

parseTableRow :: [UpdateDetail] -> Text -> Maybe PageEntry
parseTableRow columns row = do
  let (pageCell, valueCells) = parseDataRowCells row
  (path, title) <- parseWikiLinkCell pageCell <|> parseMarkdownLinkCell pageCell
  let details = catMaybes (zipWith parseCellToDetail columns valueCells)
  pure (PageEntry path title details)

parseWikiLinkFromRow :: Text -> Maybe (Text, Text)
parseWikiLinkFromRow text =
  case T.breakOn "[[" text of
    (_, "") -> Nothing
    (_, fromOpen) ->
      case T.breakOn "]]" fromOpen of
        (_, "") -> Nothing
        (linkPart, closeAndRest) ->
          let pageCell = linkPart <> "]]"
              remaining = T.drop 2 closeAndRest
          in Just (pageCell, remaining)

parseMarkdownLinkFromRow :: Text -> Maybe (Text, Text)
parseMarkdownLinkFromRow text =
  case T.breakOn "[" text of
    (_, "") -> Nothing
    (_, fromOpen) ->
      case T.breakOn "](" fromOpen of
        (_, "") -> Nothing
        (titlePart, pathStart) ->
          let afterBracketParen = T.drop 2 pathStart
          in case T.breakOn ")" afterBracketParen of
            (_, "") -> Nothing
            (path, closeAndRest) ->
              let pageCell = titlePart <> "](" <> path <> ")"
                  remaining = T.drop 1 closeAndRest
              in Just (pageCell, remaining)

parseDataRowCells :: Text -> (Text, [Text])
parseDataRowCells row =
  let trimmed = T.strip row
      afterLeadingPipe = fromMaybe trimmed (T.stripPrefix "|" trimmed)
  in case parseWikiLinkFromRow afterLeadingPipe of
    Just (pageCell, remaining) -> (T.strip pageCell, parseValueCells remaining)
    Nothing -> case parseMarkdownLinkFromRow afterLeadingPipe of
      Just (pageCell, remaining) -> (T.strip pageCell, parseValueCells remaining)
      Nothing -> ("", [])

parseValueCells :: Text -> [Text]
parseValueCells remaining =
  case T.breakOn "|" remaining of
    (_, "") -> []
    (_, afterFirstPipe) ->
      let content = T.drop 1 afterFirstPipe
          withoutTrailing = fromMaybe content (T.stripSuffix "|" content)
      in fmap T.strip (T.splitOn "|" withoutTrailing)

parseWikiLinkCell :: Text -> Maybe (Text, Text)
parseWikiLinkCell cell =
  case T.breakOn "[[" cell of
    (_, "") -> Nothing
    (_, rest) ->
      let linkContent = T.drop 2 rest
      in case T.breakOn "]]" linkContent of
        (_, "") -> Nothing
        (inner, _) ->
          case T.breakOn "\\|" inner of
            (path, titleRest) | not (T.null titleRest) ->
              Just (unescapeTablePipe path, unescapeTablePipe (T.drop 2 titleRest))
            _ ->
              case T.breakOn "|" inner of
                (_, "")    -> Nothing
                (path, titleRest) -> Just (path, T.drop 1 titleRest)

parseMarkdownLinkCell :: Text -> Maybe (Text, Text)
parseMarkdownLinkCell cell =
  case T.breakOn "[" cell of
    (_, "") -> Nothing
    (_, rest) ->
      let afterOpen = T.drop 1 rest
      in case T.breakOn "](" afterOpen of
        (_, "") -> Nothing
        (rawTitle, pathStart) ->
          let afterBracketParen = T.drop 2 pathStart
          in case T.breakOn ")" afterBracketParen of
            (_, "") -> Nothing
            (rawPath, _) ->
              let title = unescapeTablePipe rawTitle
                  path = resolveRelativePath (stripMd (T.strip rawPath))
              in Just (path, title)

resolveRelativePath :: Text -> Text
resolveRelativePath path
  | T.isPrefixOf "./" path = "reflections/" <> T.drop 2 path
  | T.isPrefixOf "../" path = T.drop 3 path
  | otherwise = "reflections/" <> path

-- Rendering
activeColumns :: [PageEntry] -> [UpdateDetail]
activeColumns entries =
  let allDetails = concatMap entryDetails entries
  in filter (\column -> any (sameColumn column) allDetails) canonicalColumns

computeColumnCount :: [PageEntry] -> UpdateDetail -> Int
computeColumnCount entries (InternalLinksAdded _) =
  sum [n | entry <- entries, InternalLinksAdded n <- entryDetails entry]
computeColumnCount entries column =
  length (filter (any (sameColumn column) . entryDetails) entries)

buildStatsLine :: [PageEntry] -> ChangesStats
buildStatsLine entries = ChangesStats
  { statsPageCount     = length entries
  , statsImageCount    = computeColumnCount entries ImageAdded
  , statsLinkCount     = computeColumnCount entries (InternalLinksAdded 0)
  , statsBlueskyCount  = computeColumnCount entries (PostedTo Bluesky)
  , statsMastodonCount = computeColumnCount entries (PostedTo Mastodon)
  , statsTwitterCount  = computeColumnCount entries (PostedTo Twitter)
  }

buildTable :: [PageEntry] -> Text
buildTable entries =
  let columns = activeColumns entries
  in if null columns
    then ""
    else
      let headerRow = "| Page | " <> T.intercalate " | " (fmap columnEmoji columns) <> " |"
          separatorRow = "|---|" <> T.concat (replicate (length columns) "---|")
          dataRows = fmap (buildTableRow columns) entries
      in T.intercalate "\n" (headerRow : separatorRow : dataRows)

buildTableRow :: [UpdateDetail] -> PageEntry -> Text
buildTableRow columns entry =
  let pageLink = "[[" <> escapeTablePipe (entryPath entry) <> "\\|" <> escapeTablePipe (entryTitle entry) <> "]]"
      cells = fmap (cellForColumn entry) columns
  in "| " <> pageLink <> " | " <> T.intercalate " | " cells <> " |"

cellForColumn :: PageEntry -> UpdateDetail -> Text
cellForColumn entry column =
  maybe "" cellText (find (sameColumn column) (entryDetails entry))

renderUpdatesSection :: [PageEntry] -> Text
renderUpdatesSection [] = ""
renderUpdatesSection entries =
  let stats = buildStatsLine entries
      table = buildTable entries
  in updatesSectionHeader <> "\n" <> renderChangesStats stats <> "\n\n" <> table <> "\n"

parseStatsPageCount :: Text -> Int
parseStatsPageCount sectionText =
  case T.breakOn "📊 " sectionText of
    (_, "") -> 0
    (_, rest) ->
      let afterEmoji = T.drop (T.length "📊 ") rest
          numberStr = T.takeWhile isDigit afterEmoji
      in fromMaybe 0 (readMaybe (T.unpack numberStr))

extractStatsLine :: Text -> Maybe Text
extractStatsLine content =
  find (T.isPrefixOf "📊 ") (T.splitOn "\n" content)

-- Core logic: parse existing → merge new → render
convertToEntry :: UpdateLink -> PageEntry
convertToEntry (UpdateLink pathNewtype titleNewtype details) =
  PageEntry (stripMd (unRelativePath pathNewtype)) (unTitle titleNewtype) details

addUpdateLinks :: Text -> [UpdateLink] -> Text
addUpdateLinks content [] = content
addUpdateLinks content links =
  let existingText = extractSectionText content
      existingEntries = parseExistingEntries existingText
      expectedCount = parseStatsPageCount existingText
      newEntries = fmap convertToEntry links
  in if null existingEntries && expectedCount > 0
    then content
    else
      let mergedEntries = mergeEntries existingEntries newEntries
          updatedSection = renderUpdatesSection mergedEntries
      in replaceUpdatesSection content updatedSection

replaceUpdatesSection :: Text -> Text -> Text
replaceUpdatesSection content newSection =
  case T.breakOn updatesSectionHeader content of
    (_, "") ->
      case findFirstSectionIndex embedSectionHeaders content of
        Just idx ->
          let (before, after) = T.splitAt idx content
          in T.stripEnd before <> "\n\n" <> newSection <> "\n" <> after
        Nothing ->
          T.stripEnd content <> "\n\n" <> newSection
    (before, sectionStart) ->
      let afterHeader = T.drop (T.length updatesSectionHeader) sectionStart
          after = case T.breakOn "\n## " afterHeader of
            (_, rest) | not (T.null rest) -> T.drop 1 rest
            _                             -> ""
      in if T.null after
        then T.stripEnd before <> "\n\n" <> newSection
        else T.stripEnd before <> "\n\n" <> newSection <> "\n" <> after

buildChangesPageContent :: Day -> Maybe Text -> Text
buildChangesPageContent date previousDate =
  let dateText = formatDay date
      backLink = maybe "" (\pd -> " | " <> buildNavBackLink Changes pd) previousDate
  in T.intercalate "\n"
    [ "---"
    , "share: true"
    , "aliases:"
    , "  - " <> quoteYamlValue dateText
    , "title: " <> quoteYamlValue dateText
    , "URL: " <> quoteYamlValue ("https://bagrounds.org/changes/" <> dateText)
    , "---"
    , formatWikilink "index" "Home" <> " > " <> directoryIndexLink Changes <> " | " <> formatWikilink ("reflections/" <> dateText) ("\129694 " <> dateText) <> backLink
    , "# " <> dateText
    , ""
    ]

buildChangesIndexContent :: Text
buildChangesIndexContent =
  T.intercalate "\n"
    [ "---"
    , "share: true"
    , "aliases:"
    , "  - " <> quoteYamlValue "\128260 Changes"
    , "title: " <> quoteYamlValue "\128260 Changes"
    , "URL: " <> quoteYamlValue "https://bagrounds.org/changes"
    , "---"
    , formatWikilink "index" "Home"
    , "# \128260 Changes"
    , ""
    , "```dataview"
    , "LIST WITHOUT ID link(file.path, file.frontmatter.title)"
    , "FROM \"changes\""
    , "WHERE file.name != this.file.name"
    , "SORT file.name DESC"
    , "```"
    ]

addChangesForwardLink :: Text -> Text -> Text
addChangesForwardLink = insertForwardNavLink Changes

findPreviousChangesDate :: FilePath -> Text -> IO (Maybe Text)
findPreviousChangesDate changesDir today = do
  exists <- doesDirectoryExist changesDir
  if exists
    then do
      entries <- listDirectory changesDir
      let candidates = sort $ filter (isChangesDateFile today) $ fmap T.pack entries
      pure $ case candidates of
        [] -> Nothing
        _  -> Just $ T.pack $ dropExtension $ T.unpack $ last candidates
    else pure Nothing

isChangesDateFile :: Text -> Text -> Bool
isChangesDateFile today fileName =
  T.length fileName >= 13
    && T.isSuffixOf ".md" fileName
    && T.index fileName 4 == '-'
    && T.index fileName 7 == '-'
    && fileName /= "index.md"
    && fileName < (today <> ".md")

ensureChangesDirectory :: FilePath -> IO ()
ensureChangesDirectory changesDir = do
  createDirectoryIfMissing True changesDir
  let indexPath = changesDir </> "index.md"
  indexExists <- doesFileExist indexPath
  unless indexExists $ do
    TIO.writeFile indexPath buildChangesIndexContent
    TIO.putStrLn "  \128193 Created changes directory index"

ensureChangesPage :: FilePath -> Day -> IO ()
ensureChangesPage changesDir date = do
  let dateText = formatDay date
      changesPath = changesDir </> T.unpack dateText <> ".md"
  pageExists <- doesFileExist changesPath
  unless pageExists $ do
    previousDate <- findPreviousChangesDate changesDir dateText
    TIO.writeFile changesPath (buildChangesPageContent date previousDate)
    TIO.putStrLn ("  \128221 Created changes page for " <> dateText)
    case previousDate of
      Nothing -> pure ()
      Just pd -> do
        let prevPath = changesDir </> T.unpack pd <> ".md"
        prevExists <- doesFileExist prevPath
        when prevExists $ do
          prevContent <- TIO.readFile prevPath
          let updated = addChangesForwardLink prevContent dateText
          when (updated /= prevContent) $
            TIO.writeFile prevPath updated

updateChangesPreviewInReflection :: FilePath -> Day -> ChangesStats -> IO ()
updateChangesPreviewInReflection reflectionPath date stats = do
  reflectionExists <- doesFileExist reflectionPath
  when reflectionExists $ do
    content <- TIO.readFile reflectionPath
    let updated = upsertChangesPreview content date stats
    when (updated /= content) $
      TIO.writeFile reflectionPath updated

extractTitleFromFile :: FilePath -> IO Text
extractTitleFromFile filePath = do
  exists <- doesFileExist filePath
  if exists
    then do
      fileContent <- TIO.readFile filePath
      let (frontmatter, _) = parseFrontmatter fileContent
          fallback = T.pack (takeBaseName filePath)
      pure (maybe fallback (\title -> if T.null title then fallback else title) (Map.lookup "title" frontmatter))
    else pure (T.pack (takeBaseName filePath))

addUpdateLinksToReflection :: FilePath -> Day -> [UpdateLink] -> IO Bool
addUpdateLinksToReflection _ _ [] = pure False
addUpdateLinksToReflection vaultDir date links = do
  let dateText = formatDay date
      reflectionsDir = vaultDir </> "reflections"
      changesDir = vaultDir </> "changes"
      reflectionPath = reflectionsDir </> T.unpack dateText <> ".md"
      changesPath = changesDir </> T.unpack dateText <> ".md"
  reflectionExists <- doesFileExist reflectionPath
  unless reflectionExists $ do
    result <- ensureDailyReflection reflectionsDir date
    when (reflectionCreated result) $
      TIO.putStrLn ("  \128221 Created daily reflection for " <> dateText)
  ensureChangesDirectory changesDir
  ensureChangesPage changesDir date
  changesContent <- TIO.readFile changesPath

  let existingText = extractSectionText changesContent
      existingEntries = parseExistingEntries existingText
      expectedCount = parseStatsPageCount existingText
      newEntries = fmap convertToEntry links
      mergedEntries = mergeEntries existingEntries newEntries

  when (null existingEntries && expectedCount > 0) $
    TIO.putStrLn $ "  \9888\65039  Data loss prevented: parsed 0 entries but stats indicate "
      <> T.pack (show expectedCount) <> " expected for " <> dateText

  let updated = addUpdateLinks changesContent links
  if updated == changesContent
    then pure False
    else do
      TIO.writeFile changesPath updated
      updateChangesPreviewInReflection reflectionPath date (buildStatsLine mergedEntries)
      let linkPaths = T.intercalate ", " (fmap (unRelativePath . updateRelativePath) links)
      TIO.putStrLn ("  \128260 Added update link(s) to " <> dateText <> " changes: " <> linkPaths)
      pure True
