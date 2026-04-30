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
import Automation.Frontmatter (parseFrontmatter, quoteYamlValue)
import Automation.InternalLinking.CandidateDiscovery (ContentEntry (..), buildContentIndex)
import Automation.InternalLinking.LinkExtraction (bfsTraversal)
import Automation.PacificTime (formatDay, todayPacificDay)
import Automation.Secret (Secret)
import Automation.Text (stripEmojis)
import Automation.Title (unTitle)
import qualified Automation.Gemini as Gemini
import qualified Data.Char as Char
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

-- | Maximum number of files to scan per run when looking for book mentions.
maxFilesScanned :: Int
maxFilesScanned = 5

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
buildBookFrontmatter :: Text -> Text -> Maybe Text -> Text
buildBookFrontmatter title slug mAffiliateLink =
  let affiliateLines = case mAffiliateLink of
        Just link -> ["affiliate link: " <> link]
        Nothing   -> []
      baseLines =
        [ "---"
        , "share: true"
        , "aliases:"
        , "  - " <> quoteYamlValue title
        , "title: " <> quoteYamlValue title
        , "URL: " <> quoteYamlValue ("https://bagrounds.org/books/" <> slug)
        , "Author:"
        , "tags:"
        ]
  in T.intercalate "\n" (baseLines <> affiliateLines <> ["---"])

-- | Build the body of a book file, combining nav links, title, optional affiliate
-- link, the generated report, and the Gemini prompt attribution footer.
buildBookBody :: Text -> Text -> Maybe Text -> Gemini.Model -> Text
buildBookBody title reportContent mAffiliateLink model =
  let plainTitle = T.strip (stripEmojis title)
      affiliateLinkLine = case mAffiliateLink of
        Just link -> "[🛒 " <> plainTitle <> ". As an Amazon Associate I earn from qualifying purchases.](" <> link <> ")\n\n"
        Nothing   -> ""
      prompt = buildReportPrompt title
  in T.intercalate "\n"
    [ "[[index|🏡 Home]] > [[/books/index|📚 Books]]"
    , "# " <> title
    , affiliateLinkLine
    , reportContent
    , ""
    , "## 💬 [Gemini](https://gemini.google.com) Prompt (" <> Gemini.modelToText model <> ")"
    , "> " <> prompt
    ]

-- | Assemble the complete book file content (frontmatter + body).
buildBookFileContent :: Text -> Text -> Maybe Text -> Gemini.Model -> Text
buildBookFileContent title reportContent mAffiliateLink model =
  let slug = titleToKebabCase title
      frontmatter = buildBookFrontmatter title slug mAffiliateLink
      body = buildBookBody title reportContent mAffiliateLink model
  in frontmatter <> "\n" <> body <> "\n"

-- | The section heading used in daily reflections for the book links section.
booksSectionHeading :: Text
booksSectionHeading = "## [[/books/index|📚 Books]]"

-- | Insert a wikilink to a newly generated book into today's reflection content.
-- Creates a new "Books" section if one does not already exist, inserting it
-- before any trailing social-embed sections.
insertBookLink :: Text -> Text -> Text -> Text
insertBookLink reflectionContent bookSlug bookTitle =
  let bookLink = "- [[books/" <> bookSlug <> "|" <> bookTitle <> "]]"
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

trailingReflectionSections :: [Text]
trailingReflectionSections =
  [ "## 📢 Updates"
  , "## [[changes/"
  , "## 🐦 Twitter"
  , "## 🦋 Bluesky"
  , "## 🐘 Mastodon"
  ]

insertBooksSection :: Text -> Text -> Text
insertBooksSection content bookLink =
  let sectionBlock = booksSectionHeading <> "\n" <> bookLink
      trailingSectionsFound = filter (`T.isInfixOf` content) trailingReflectionSections
  in case trailingSectionsFound of
    [] ->
      T.stripEnd content <> "\n\n" <> sectionBlock <> "\n"
    (header : _) ->
      let idx = T.length (fst (T.breakOn header content))
          (before, after) = T.splitAt idx content
      in T.stripEnd before <> "\n\n" <> sectionBlock <> "\n\n" <> after

-- | Main entry point. BFS-scans content for unlinked book mentions, searches
-- Amazon for product links, generates reports with Gemini, and writes book files
-- and reflection links to the vault.
run :: Manager -> Secret -> Text -> FilePath -> IO BookReportResult
run manager apiKey associateTag vaultDir = do
  let contentDir = vaultDir
  existingBooks <- buildContentIndex contentDir
  let existingNormalizedTitles = Set.fromList
        (map (normalizeTitleForComparison . unTitle . plainTitle) existingBooks)
  putStrLn $ "  📚 Existing books: " <> show (length existingBooks)

  allFiles <- bfsTraversal contentDir
  putStrLn $ "  🔍 BFS: " <> show (length allFiles) <> " files reachable"

  let booksDir = contentDir </> "books"
  booksDirExists <- doesDirectoryExist booksDir
  if not booksDirExists
    then do
      putStrLn "  ⚠️  Books directory not found — skipping"
      pure BookReportResult { booksGenerated = 0, booksAttempted = 0, booksSkipped = 1 }
    else do
      mCandidates <- findFirstCandidates manager apiKey contentDir allFiles existingNormalizedTitles
      case mCandidates of
        [] -> do
          putStrLn "  📭 No new book candidates found in scanned files"
          pure BookReportResult { booksGenerated = 0, booksAttempted = 0, booksSkipped = 0 }
        candidates -> do
          putStrLn $ T.unpack
            (  "  📋 Found " <> T.pack (show (length candidates)) <> " book candidate(s): "
            <> T.intercalate ", " (map fst (take 3 candidates))
            )
          tryGenerateReport manager apiKey associateTag contentDir candidates 0

-- | BFS through content files, scanning up to 'maxFilesScanned' files for
-- plain-text book mentions not already in the existing index.
findFirstCandidates :: Manager -> Secret -> FilePath -> [Text] -> Set.Set Text -> IO [(Text, Text)]
findFirstCandidates manager apiKey contentDir allFiles existingNormalizedTitles =
  go (take maxFilesScanned allFiles) []
  where
    go [] accumulator = pure accumulator
    go (relPath : rest) accumulator = do
      let filePath = contentDir </> T.unpack relPath
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
              let newBooks = filter (\title -> not (Set.member (normalizeTitleForComparison title) existingNormalizedTitles)) mentions
              putStrLn $ "  📖 " <> T.unpack relPath <> ": " <> show (length mentions) <> " mention(s), "
                <> show (length newBooks) <> " new"
              let candidates = map (, relPath) newBooks
              if null candidates
                then go rest accumulator
                else pure (accumulator <> candidates)

normalizeTitleForComparison :: Text -> Text
normalizeTitleForComparison = T.toLower . T.strip . stripEmojis

-- | Try to generate a book report for the first candidate that successfully
-- passes Amazon search. Limits the number of attempts to avoid excessive API usage.
tryGenerateReport :: Manager -> Secret -> Text -> FilePath -> [(Text, Text)] -> Int -> IO BookReportResult
tryGenerateReport _ _ _ _ [] attempted =
  pure BookReportResult { booksGenerated = 0, booksAttempted = attempted, booksSkipped = 0 }
tryGenerateReport manager apiKey associateTag contentDir ((bookTitle, sourceFile) : rest) attempted = do
  putStrLn $ "  🔍 Searching Amazon for: " <> T.unpack bookTitle
  mAmazonUrl <- searchAmazonProductUrl manager apiKey defaultAmazonSearchModel bookTitle
  case mAmazonUrl of
    Nothing -> do
      putStrLn $ "  ⏭️  Amazon URL not found for: " <> T.unpack bookTitle <> " — trying next"
      tryGenerateReport manager apiKey associateTag contentDir rest (attempted + 1)
    Just amazonUrl -> do
      putStrLn $ "  🛒 Amazon URL: " <> T.unpack amazonUrl
      let mAsin = extractAsin amazonUrl
          mAffiliateLink = if T.null associateTag
            then Nothing
            else buildAffiliateUrl <$> mAsin <*> pure associateTag
      case mAffiliateLink of
        Nothing -> putStrLn "  ⚠️  Could not extract ASIN or no associate tag — book page will have no affiliate link"
        Just link -> putStrLn $ "  💰 Affiliate URL: " <> T.unpack link

      putStrLn $ "  📝 Generating book report for: " <> T.unpack bookTitle
      reportResult <- generateBookReportWithGemini manager apiKey defaultBookReportModel bookTitle
      case reportResult of
        Left err -> do
          putStrLn $ "  ❌ Report generation failed for " <> T.unpack bookTitle <> ": " <> T.unpack err
          tryGenerateReport manager apiKey associateTag contentDir rest (attempted + 1)
        Right reportContent -> do
          let slug = titleToKebabCase bookTitle
              bookFilename = slug <> ".md"
              booksDir = contentDir </> "books"
              bookFilePath = booksDir </> T.unpack bookFilename
          alreadyExists <- doesFileExist bookFilePath
          if alreadyExists
            then do
              putStrLn $ "  ⏭️  Book file already exists: " <> T.unpack bookFilename
              pure BookReportResult { booksGenerated = 0, booksAttempted = attempted + 1, booksSkipped = 1 }
            else do
              createDirectoryIfMissing True booksDir
              let fileContent = buildBookFileContent bookTitle reportContent mAffiliateLink defaultBookReportModel
              TIO.writeFile bookFilePath fileContent
              putStrLn $ "  ✅ Created: books/" <> T.unpack bookFilename <> " (from " <> T.unpack sourceFile <> ")"

              today <- todayPacificDay
              let reflectionsDir = contentDir </> "reflections"
                  reflectionPath = reflectionsDir </> T.unpack (formatDay today) <> ".md"
              reflectionExists <- doesFileExist reflectionPath
              if reflectionExists
                then do
                  reflectionContent <- TIO.readFile reflectionPath
                  let updatedReflection = insertBookLink reflectionContent slug bookTitle
                  if updatedReflection /= reflectionContent
                    then do
                      TIO.writeFile reflectionPath updatedReflection
                      putStrLn $ "  📓 Added book link to reflection: " <> T.unpack (formatDay today)
                    else
                      putStrLn "  ⏭️  Book link already present in reflection"
                else
                  putStrLn $ "  ⚠️  No reflection found for today (" <> T.unpack (formatDay today) <> ") — skipping reflection link"

              pure BookReportResult { booksGenerated = 1, booksAttempted = attempted + 1, booksSkipped = 0 }
