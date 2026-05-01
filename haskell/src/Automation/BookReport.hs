{-# LANGUAGE OverloadedStrings #-}

module Automation.BookReport
  ( BookReportResult (..)
  , defaultBookReportModel
  , defaultAmazonSearchModel
  , titleToKebabCase
  , extractAsin
  , buildAffiliateUrl
  , buildBookFrontmatter
  , buildBookBody
  , buildBookFileContent
  , booksSectionHeading
  , insertBookLink
  , run
  ) where

import Automation.BookReport.Gemini
  ( buildReportPrompt
  , findBookMentionsWithGemini
  , generateBookReportWithGemini
  , searchAmazonProductUrl
  )
import Automation.Frontmatter (YamlValue (..), parseFrontmatter, quoteYamlValue, updateFrontmatterFields)
import Automation.InternalLinking (applyReplacements)
import Automation.InternalLinking.CandidateDiscovery (ContentEntry (..), buildContentIndex, findLinkCandidates)
import Automation.InternalLinking.LinkExtraction (bfsTraversal)
import Automation.InternalLinking.Masking (maskProtectedRegions)
import Automation.PacificTime (formatDay, todayPacificDay)
import Automation.RelativePath (mkRelativePath)
import Automation.Secret (Secret)
import Automation.Text (stripEmojis)
import Automation.Title (unTitle)
import qualified Automation.Gemini as Gemini
import qualified Data.Char as Char
import Data.List (find)
import Data.Maybe (fromMaybe, mapMaybe)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Network.HTTP.Client (Manager)
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, doesFileExist)
import System.FilePath ((</>))

data BookReportResult = BookReportResult
  { booksGenerated :: Int
  , booksAttempted :: Int
  , booksSkipped   :: Int
  } deriving (Show, Eq)

defaultBookReportModel :: Gemini.Model
defaultBookReportModel = Gemini.Gemini25Flash

defaultAmazonSearchModel :: Gemini.Model
defaultAmazonSearchModel = Gemini.Gemini25Flash

-- | Convert a book title to a URL-safe kebab-case slug.
-- Follows the same rules as the Obsidian Templater script:
--   lowercase → remove apostrophes → replace non-alphanumeric runs with "-" → trim dashes
titleToKebabCase :: Text -> Text
titleToKebabCase =
  trimDashes
    . T.pack
    . collapseConsecutiveDashes
    . map replaceNonAlphanumeric
    . T.unpack
    . T.filter (/= '\'')
    . T.toLower
  where
    replaceNonAlphanumeric character
      | Char.isAscii character && Char.isAlphaNum character = character
      | otherwise = '-'
    collapseConsecutiveDashes [] = []
    collapseConsecutiveDashes ('-' : '-' : rest) = collapseConsecutiveDashes ('-' : rest)
    collapseConsecutiveDashes (character : rest) = character : collapseConsecutiveDashes rest
    trimDashes = T.dropWhile (== '-') . T.dropWhileEnd (== '-')

-- | Extract an Amazon ASIN from a product URL.
-- Supports the /dp/ASIN and /gp/product/ASIN URL patterns.
extractAsin :: Text -> Maybe Text
extractAsin url
  | T.isInfixOf "/dp/" url =
      let segment = takeAsinSegment . T.drop 4 . snd $ T.breakOn "/dp/" url
      in if isValidAsin segment then Just segment else Nothing
  | T.isInfixOf "/gp/product/" url =
      let segment = takeAsinSegment . T.drop 12 . snd $ T.breakOn "/gp/product/" url
      in if isValidAsin segment then Just segment else Nothing
  | otherwise = Nothing

-- | Extract the ASIN-length segment by stopping at the first non-ASIN character.
takeAsinSegment :: Text -> Text
takeAsinSegment = T.takeWhile (\character -> Char.isAlphaNum character && character /= '?')

isValidAsin :: Text -> Bool
isValidAsin text = T.length text == 10 && T.all Char.isAlphaNum text

-- | Build an Amazon affiliate URL from an ASIN and associate tag.
buildAffiliateUrl :: Text -> Text -> Text
buildAffiliateUrl productAsin associateTag =
  "https://www.amazon.com/dp/" <> productAsin <> "?tag=" <> associateTag

-- | Build the YAML frontmatter block for a new book file.
-- Uses the emojified title (if provided) for the title and aliases fields.
buildBookFrontmatter :: Text -> Text -> Maybe Text -> Maybe Text -> Text
buildBookFrontmatter originalTitle slug mAffiliateLink mEmojifiedTitle =
  let displayTitle = fromMaybe originalTitle mEmojifiedTitle
      affiliateLines = case mAffiliateLink of
        Just link -> ["affiliate link: " <> link]
        Nothing   -> []
      baseLines =
        [ "---"
        , "share: true"
        , "aliases:"
        , "  - " <> quoteYamlValue displayTitle
        , "title: " <> quoteYamlValue displayTitle
        , "URL: " <> quoteYamlValue ("https://bagrounds.org/books/" <> slug)
        , "Author:"
        , "tags:"
        ]
  in T.intercalate "\n" (baseLines <> affiliateLines <> ["---"])

-- | Build the body of a book file, combining nav links, emojified title H1,
-- optional affiliate link, the generated report body, and the Gemini prompt attribution.
buildBookBody :: Text -> Text -> Maybe Text -> Maybe Text -> Gemini.Model -> Text
buildBookBody originalTitle reportBody mAffiliateLink mEmojifiedTitle model =
  let displayTitle = fromMaybe originalTitle mEmojifiedTitle
      plainTitle = T.strip (stripEmojis originalTitle)
      affiliateLinkLine = case mAffiliateLink of
        Just link -> "[🛒 " <> plainTitle <> ". As an Amazon Associate I earn from qualifying purchases.](" <> link <> ")\n\n"
        Nothing   -> ""
      prompt = buildReportPrompt originalTitle
  in T.intercalate "\n"
    [ "[[index|🏡 Home]] > [[/books/index|📚 Books]]"
    , "# " <> displayTitle
    , affiliateLinkLine
    , reportBody
    , ""
    , "## 💬 [Gemini](https://gemini.google.com) Prompt (" <> Gemini.modelToText model <> ")"
    , "> " <> prompt
    ]

-- | Assemble the complete book file content (frontmatter + body).
-- Parses the emojified title from the first non-empty line of the Gemini response.
buildBookFileContent :: Text -> Text -> Maybe Text -> Gemini.Model -> Text
buildBookFileContent originalTitle fullResponse mAffiliateLink model =
  let slug = titleToKebabCase originalTitle
      (mEmojifiedTitle, reportBody) = parseEmojifiedTitle fullResponse
      frontmatter = buildBookFrontmatter originalTitle slug mAffiliateLink mEmojifiedTitle
      body = buildBookBody originalTitle reportBody mAffiliateLink mEmojifiedTitle model
  in frontmatter <> "\n" <> body <> "\n"

-- | Parse the first non-empty line of a Gemini report response as the emojified title.
-- Returns (Just emojifiedTitle, remainingBody) if the first line looks like an emojified title,
-- otherwise returns (Nothing, fullResponse).
parseEmojifiedTitle :: Text -> (Maybe Text, Text)
parseEmojifiedTitle response =
  let allLines = T.lines response
      (_, rest) = span T.null allLines
  in case rest of
    (firstLine : remaining)
      | looksLikeEmojifiedTitle firstLine ->
          let bodyLines = dropWhile T.null remaining
          in (Just (T.strip firstLine), T.unlines bodyLines)
    _ -> (Nothing, response)
  where
    looksLikeEmojifiedTitle line =
      let stripped = T.strip line
      in not (T.isPrefixOf "#" stripped)
           && not (T.isPrefixOf "-" stripped)
           && not (T.null stripped)
           && T.length stripped < 200
           && hasLeadingEmoji stripped

    hasLeadingEmoji line =
      not (T.null line) && Char.ord (T.head line) > 127

-- | The section heading used in daily reflections for the book links section.
booksSectionHeading :: Text
booksSectionHeading = "## [[/books/index|📚 Books]]"

-- | Auto-generated book link marker used to distinguish automation-inserted links.
autoGeneratedMarker :: Text
autoGeneratedMarker = " 🤖"

-- | Build the wikilink list item for a newly generated book in the reflection.
buildBookReflectionLink :: Text -> Text -> Text
buildBookReflectionLink bookSlug bookTitle =
  "- [[books/" <> bookSlug <> "|" <> bookTitle <> "]]" <> autoGeneratedMarker

-- | Insert a wikilink to a newly generated book into today's reflection content.
-- Creates a new "Books" section if one does not already exist, inserting it
-- before any trailing sections (social embeds, blog series sections, or changes).
-- Idempotent: no-op if the slug is already linked.
insertBookLink :: Text -> Text -> Text -> Text
insertBookLink reflectionContent bookSlug bookTitle =
  let bookLink = buildBookReflectionLink bookSlug bookTitle
  in if T.isInfixOf ("[[books/" <> bookSlug <> "|") reflectionContent
     then reflectionContent
     else if T.isInfixOf booksSectionHeading reflectionContent
       then appendToBookSection reflectionContent bookLink
       else insertBooksSection reflectionContent bookLink

appendToBookSection :: Text -> Text -> Text
appendToBookSection content bookLink =
  let contentLines = T.splitOn "\n" content
      sectionIndex = length (takeWhile (not . T.isPrefixOf booksSectionHeading) contentLines)
      (before, after) = splitAt (sectionIndex + 1) contentLines
      (listItems, rest) = span (T.isPrefixOf "- ") after
  in T.intercalate "\n" (before <> listItems <> [bookLink] <> rest)

-- | Static trailing section prefixes that the Books section should be inserted before.
trailingReflectionSectionPrefixes :: [Text]
trailingReflectionSectionPrefixes =
  [ "## 🔄 Updates"
  , "## [[changes/"
  , "## 🐦"
  , "## 🦋"
  , "## 🐘"
  ]

-- | Find the character index of the earliest trailing or auto-generated section
-- in the content, so the Books section can be inserted before it.
-- Trailing sections include social embeds, the changes section, and any
-- blog-series section headings (which look like "## [[<id>/index|...]]").
findEarliestInsertionPoint :: Text -> Maybe Int
findEarliestInsertionPoint content =
  let staticMatches =
        [ T.length (fst (T.breakOn prefix content))
        | prefix <- trailingReflectionSectionPrefixes
        , T.isInfixOf prefix content
        ]
      dynamicHeaders = filter isDynamicSeriesHeading (T.lines content)
      dynamicMatches =
        [ T.length (fst (T.breakOn header content))
        | header <- dynamicHeaders
        , T.isInfixOf header content
        ]
      allPositions = staticMatches <> dynamicMatches
  in case allPositions of
    [] -> Nothing
    _  -> Just (minimum allPositions)
  where
    isDynamicSeriesHeading line =
      T.isPrefixOf "## [[" line
        && T.isInfixOf "/index|" line
        && not (T.isPrefixOf booksSectionHeading line)

insertBooksSection :: Text -> Text -> Text
insertBooksSection content bookLink =
  let sectionBlock = booksSectionHeading <> "\n" <> bookLink
  in case findEarliestInsertionPoint content of
    Nothing ->
      T.stripEnd content <> "\n\n" <> sectionBlock <> "\n"
    Just insertionIndex ->
      let (before, after) = T.splitAt insertionIndex content
      in T.stripEnd before <> "\n\n" <> sectionBlock <> "\n\n" <> after

-- | Main entry point. Checks for a pending book from a previous partial run,
-- then BFS-scans content for unlinked book mentions if no pending title is found.
-- Refuses to run if AMAZON_ASSOCIATE_TAG is not set to prevent generating
-- book pages without affiliate links.
run :: Manager -> Secret -> Text -> FilePath -> IO BookReportResult
run manager apiKey associateTag vaultDir
  | T.null associateTag = do
      putStrLn "  🚫 AMAZON_ASSOCIATE_TAG not set — refusing to generate book reports without affiliate links"
      pure BookReportResult { booksGenerated = 0, booksAttempted = 0, booksSkipped = 1 }
  | otherwise = do
      today <- todayPacificDay
      let todayText = formatDay today
          reflectionPath = vaultDir </> "reflections" </> T.unpack todayText <> ".md"

      reflectionExists <- doesFileExist reflectionPath
      mReflectionContent <-
        if reflectionExists
          then Just <$> TIO.readFile reflectionPath
          else pure Nothing

      let reflectionFrontmatter = maybe Map.empty (fst . parseFrontmatter) mReflectionContent

      -- Idempotency: skip if already ran today
      case Map.lookup "book-reports-run" reflectionFrontmatter of
        Just runDate | runDate == todayText -> do
          putStrLn $ "  ⏭️  Already generated a book report for " <> T.unpack todayText <> " — skipping"
          pure BookReportResult { booksGenerated = 0, booksAttempted = 0, booksSkipped = 1 }
        _ -> do
          let booksDir = vaultDir </> "books"
          booksDirExists <- doesDirectoryExist booksDir
          if not booksDirExists
            then do
              putStrLn "  ⚠️  Books directory not found — skipping"
              pure BookReportResult { booksGenerated = 0, booksAttempted = 0, booksSkipped = 1 }
            else do
              existingBooks <- buildContentIndex vaultDir
              let existingNormalizedTitles = Set.fromList
                    (map (normalizeTitleForComparison . unTitle . plainTitle) existingBooks)
              putStrLn $ "  📚 Existing books: " <> show (length existingBooks)

              -- Resume from a pending title if the previous run was interrupted
              mPendingTitle <- resolvePendingTitle reflectionFrontmatter vaultDir

              candidates <- case mPendingTitle of
                Just pendingTitle -> do
                  putStrLn $ "  📌 Resuming with pending book: " <> T.unpack pendingTitle
                  pure [(pendingTitle, "<pending>")]
                Nothing -> do
                  allFiles <- bfsTraversal vaultDir
                  putStrLn $ "  🔍 BFS: " <> show (length allFiles) <> " files reachable"
                  findFirstCandidates manager apiKey vaultDir existingBooks allFiles existingNormalizedTitles

              case candidates of
                [] -> do
                  putStrLn "  📭 No new book candidates found"
                  pure BookReportResult { booksGenerated = 0, booksAttempted = 0, booksSkipped = 0 }
                _ -> do
                  putStrLn $ T.unpack
                    (  "  📋 Found " <> T.pack (show (length candidates)) <> " book candidate(s): "
                    <> T.intercalate ", " (map fst (take 3 candidates))
                    )
                  tryGenerateReport manager apiKey associateTag vaultDir reflectionPath todayText candidates 0

-- | Check if there is a non-empty pending title in frontmatter that hasn't
-- already been generated (i.e., the book file doesn't exist yet).
resolvePendingTitle :: Map.Map Text Text -> FilePath -> IO (Maybe Text)
resolvePendingTitle frontmatter vaultDir =
  case Map.lookup "book-report-pending" frontmatter of
    Nothing -> pure Nothing
    Just pending | T.null (T.strip pending) -> pure Nothing
    Just pendingTitle -> do
      let slug = titleToKebabCase pendingTitle
          bookFilePath = vaultDir </> "books" </> T.unpack slug <> ".md"
      alreadyExists <- doesFileExist bookFilePath
      if alreadyExists
        then pure Nothing
        else pure (Just (T.strip pendingTitle))

-- | BFS through content files, scanning ONE file for plain-text book mentions.
-- Also inserts wikilinks for books that are mentioned but already have pages.
findFirstCandidates :: Manager -> Secret -> FilePath -> [ContentEntry] -> [Text] -> Set.Set Text -> IO [(Text, Text)]
findFirstCandidates manager apiKey vaultDir existingBooks allFiles existingNormalizedTitles =
  go allFiles []
  where
    go [] accumulator = pure accumulator
    go (relPath : rest) accumulator = do
      let filePath = vaultDir </> T.unpack relPath
      exists <- doesFileExist filePath
      if not exists
        then go rest accumulator
        else do
          content <- TIO.readFile filePath
          let (_, body) = parseFrontmatter content
          putStrLn $ "  🔎 Scanning for book mentions: " <> T.unpack relPath
          result <- findBookMentionsWithGemini manager apiKey defaultBookReportModel body
          case result of
            Left err -> do
              putStrLn $ "  ⚠️  Gemini error scanning " <> T.unpack relPath <> ": " <> T.unpack err
              go rest accumulator
            Right mentions -> do
              let newBooks = filter (\t -> not (Set.member (normalizeTitleForComparison t) existingNormalizedTitles)) mentions
                  existingMentioned = filter (\t -> Set.member (normalizeTitleForComparison t) existingNormalizedTitles) mentions
              putStrLn $ "  📖 " <> T.unpack relPath <> ": " <> show (length mentions) <> " mention(s), "
                <> show (length newBooks) <> " new, " <> show (length existingMentioned) <> " already have pages"
              insertWikilinksForExistingMentions relPath filePath existingBooks existingMentioned
              let candidates = map (, relPath) newBooks
              if null candidates
                then go rest accumulator
                else pure (accumulator <> candidates)

-- | Insert wikilinks for books that are mentioned in plain text but already have pages.
-- Reuses the existing InternalLinking infrastructure (findLinkCandidates + applyReplacements).
insertWikilinksForExistingMentions :: Text -> FilePath -> [ContentEntry] -> [Text] -> IO ()
insertWikilinksForExistingMentions relPath filePath existingBooks mentionedTitles =
  case mkRelativePath relPath of
    Left _ -> pure ()
    Right selfRelPath -> do
      let matchingEntries = mapMaybe (`findEntryForTitle` existingBooks) mentionedTitles
      case matchingEntries of
        [] -> pure ()
        _ -> do
          content <- TIO.readFile filePath
          let masked = maskProtectedRegions content
              candidates = findLinkCandidates matchingEntries content masked selfRelPath
          case candidates of
            [] -> pure ()
            _ -> do
              let updated = applyReplacements content candidates (replicate (length candidates) True)
              TIO.writeFile filePath updated
              putStrLn $ "  🔗 " <> T.unpack relPath <> ": inserted "
                <> show (length candidates) <> " wikilink(s) for existing book(s)"

findEntryForTitle :: Text -> [ContentEntry] -> Maybe ContentEntry
findEntryForTitle mentionedTitle =
  find (\e -> normalizeTitleForComparison (unTitle (plainTitle e)) == normalizeTitleForComparison mentionedTitle)

normalizeTitleForComparison :: Text -> Text
normalizeTitleForComparison = T.toLower . T.strip . stripEmojis

-- | Try to generate a book report for the first candidate that successfully
-- passes Amazon search.
tryGenerateReport :: Manager -> Secret -> Text -> FilePath -> FilePath -> Text -> [(Text, Text)] -> Int -> IO BookReportResult
tryGenerateReport _ _ _ _ _ _ [] attempted =
  pure BookReportResult { booksGenerated = 0, booksAttempted = attempted, booksSkipped = 0 }
tryGenerateReport manager apiKey associateTag vaultDir reflectionPath todayText ((bookTitle, _) : rest) attempted = do
  -- Persist the candidate title before expensive API calls so a failed run can resume
  updateFrontmatterFields reflectionPath [("book-report-pending", YamlText bookTitle)]

  putStrLn $ "  🔍 Searching Amazon for: " <> T.unpack bookTitle
  mAmazonUrl <- searchAmazonProductUrl manager apiKey defaultAmazonSearchModel bookTitle
  case mAmazonUrl of
    Nothing -> do
      putStrLn $ "  ⏭️  Amazon URL not found for: " <> T.unpack bookTitle <> " — trying next"
      tryGenerateReport manager apiKey associateTag vaultDir reflectionPath todayText rest (attempted + 1)
    Just amazonUrl -> do
      putStrLn $ "  🛒 Amazon URL: " <> T.unpack amazonUrl
      let mAsin = extractAsin amazonUrl
          mAffiliateLink = buildAffiliateUrl <$> mAsin <*> pure associateTag
      case mAffiliateLink of
        Nothing -> putStrLn "  ⚠️  Could not extract ASIN — book page will have no affiliate link"
        Just link -> putStrLn $ "  💰 Affiliate URL: " <> T.unpack link

      putStrLn $ "  📝 Generating book report for: " <> T.unpack bookTitle
      reportResult <- generateBookReportWithGemini manager apiKey defaultBookReportModel bookTitle
      case reportResult of
        Left err -> do
          putStrLn $ "  ❌ Report generation failed for " <> T.unpack bookTitle <> ": " <> T.unpack err
          tryGenerateReport manager apiKey associateTag vaultDir reflectionPath todayText rest (attempted + 1)
        Right fullResponse -> do
          let slug = titleToKebabCase bookTitle
              bookFilename = slug <> ".md"
              booksDir = vaultDir </> "books"
              bookFilePath = booksDir </> T.unpack bookFilename
          alreadyExists <- doesFileExist bookFilePath
          if alreadyExists
            then do
              putStrLn $ "  ⏭️  Book file already exists: " <> T.unpack bookFilename
              pure BookReportResult { booksGenerated = 0, booksAttempted = attempted + 1, booksSkipped = 1 }
            else do
              createDirectoryIfMissing True booksDir
              let fileContent = buildBookFileContent bookTitle fullResponse mAffiliateLink defaultBookReportModel
              TIO.writeFile bookFilePath fileContent
              putStrLn $ "  ✅ Created: books/" <> T.unpack bookFilename

              -- Add book link to today's reflection
              reflectionExists <- doesFileExist reflectionPath
              if reflectionExists
                then do
                  reflectionContent <- TIO.readFile reflectionPath
                  let updatedReflection = insertBookLink reflectionContent slug bookTitle
                  TIO.writeFile reflectionPath updatedReflection
                  putStrLn $ "  📓 Added book link to reflection: " <> T.unpack todayText
                else
                  putStrLn $ "  ⚠️  No reflection found for today (" <> T.unpack todayText <> ") — skipping reflection link"

              -- Mark as done for today and clear the pending title
              updateFrontmatterFields reflectionPath
                [ ("book-reports-run", YamlText todayText)
                , ("book-report-pending", YamlText "")
                ]
              putStrLn $ "  📌 Marked book-reports-run: " <> T.unpack todayText

              pure BookReportResult { booksGenerated = 1, booksAttempted = attempted + 1, booksSkipped = 0 }

