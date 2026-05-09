module Automation.BookReports.Discovery
  ( BookCandidate (..)
  , listExistingBookSlugs
  , listExistingBookReportFiles
  , extractCandidatesFromBookReport
  ) where

import Control.Applicative ((<|>))
import Data.List (sort)
import qualified Data.Maybe
import Data.Maybe (mapMaybe)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import System.Directory (doesDirectoryExist, listDirectory)
import System.FilePath ((</>))

import Automation.Text (isEmojiOrSpace)
import Automation.BookReports.Types
  ( BookAuthor
  , BookSlug
  , BookTitle
  , mkBookAuthor
  , mkBookSlug
  , mkBookTitle
  , slugFromTitle
  )

-- | Reject extracted titles shorter than this to avoid trivial false matches
--   like "Hi by X" or "It by Y" that are almost never real book references.
minPlainTitleLength :: Int
minPlainTitleLength = 4

-- | Authors longer than this are almost certainly the prose tail of a
--   malformed bullet rather than a real author attribution; we'd rather
--   miss the candidate than feed a paragraph into Gemini as the author.
maxAuthorLength :: Int
maxAuthorLength = 100

data BookCandidate = BookCandidate
  { candidateSlug       :: BookSlug
  , candidateTitle      :: BookTitle
  , candidateAuthor     :: Maybe BookAuthor
  , candidateSourceLine :: Text
  , candidateSourceFile :: FilePath
  } deriving (Eq, Show)

listExistingBookReportFiles :: FilePath -> IO [FilePath]
listExistingBookReportFiles booksDir = do
  exists <- doesDirectoryExist booksDir
  if not exists
    then pure []
    else do
      entries <- listDirectory booksDir
      let reports = filter isBookReportFileName entries
      pure (fmap (booksDir </>) (sort reports))
  where
    isBookReportFileName filename =
      T.isSuffixOf ".md" (T.pack filename) && filename /= "index.md"

listExistingBookSlugs :: FilePath -> IO (Set.Set BookSlug)
listExistingBookSlugs booksDir = do
  exists <- doesDirectoryExist booksDir
  if not exists
    then pure Set.empty
    else do
      entries <- listDirectory booksDir
      pure (Set.fromList (mapMaybe filenameToBookSlug entries))
  where
    filenameToBookSlug filename =
      case T.stripSuffix ".md" (T.pack filename) of
        Nothing      -> Nothing
        Just "index" -> Nothing
        Just stem    -> rightToMaybe (mkBookSlug (T.toLower stem))

extractCandidatesFromBookReport
  :: Set.Set BookSlug
  -> FilePath
  -> Text
  -> [BookCandidate]
extractCandidatesFromBookReport knownSlugs sourcePath body =
  let lineCandidates = mapMaybe (candidateFromBulletLine sourcePath) (T.lines body)
      notKnown       = filter (\c -> not (Set.member (candidateSlug c) knownSlugs)) lineCandidates
  in notKnown

candidateFromBulletLine :: FilePath -> Text -> Maybe BookCandidate
candidateFromBulletLine sourcePath rawLine = do
  bulletBody <- stripBulletMarker rawLine
  let withoutLeadingDecoration = dropLeadingDecoration bulletBody
  () <- guard' (not (lineAlreadyContainsLink withoutLeadingDecoration))
  (titleText, afterTitle) <- extractTitleAndRemainder withoutLeadingDecoration
  authorText              <- extractAuthor afterTitle
  let cleanedTitleText = stripEmojisAndPunctuation titleText
  () <- guard' (T.length cleanedTitleText >= minPlainTitleLength)
  bookTitle  <- rightToMaybe (mkBookTitle cleanedTitleText)
  bookAuthor <- rightToMaybe (mkBookAuthor authorText)
  let slug = slugFromTitle bookTitle
  pure BookCandidate
    { candidateSlug       = slug
    , candidateTitle      = bookTitle
    , candidateAuthor     = Just bookAuthor
    , candidateSourceLine = T.strip rawLine
    , candidateSourceFile = sourcePath
    }

stripBulletMarker :: Text -> Maybe Text
stripBulletMarker line =
  let leftTrimmed = T.stripStart line
  in T.stripPrefix "* " leftTrimmed
     <|> T.stripPrefix "- " leftTrimmed
     <|> T.stripPrefix "+ " leftTrimmed

dropLeadingDecoration :: Text -> Text
dropLeadingDecoration =
  T.dropWhile isEmojiOrSpace

lineAlreadyContainsLink :: Text -> Bool
lineAlreadyContainsLink line =
  T.isInfixOf "](" line || T.isInfixOf "[[" line

extractTitleAndRemainder :: Text -> Maybe (Text, Text)
extractTitleAndRemainder line =
  extractBoldThenBy line <|> extractPlainThenBy line

extractBoldThenBy :: Text -> Maybe (Text, Text)
extractBoldThenBy line = do
  afterOpen <- T.stripPrefix "**" line
  let (boldTitle, afterClose) = T.breakOn "**" afterOpen
  () <- guard' (not (T.null afterClose))
  let remainderAfterBold = T.drop (T.length ("**" :: Text)) afterClose
  authorPart <- T.stripPrefix " by " (T.stripStart remainderAfterBold)
  pure (T.strip boldTitle, authorPart)

extractPlainThenBy :: Text -> Maybe (Text, Text)
extractPlainThenBy line =
  let (titleRaw, after) = T.breakOn " by " line
  in if T.null after
       then Nothing
       else Just (T.strip titleRaw, T.drop (T.length (" by " :: Text)) after)

extractAuthor :: Text -> Maybe Text
extractAuthor remainder =
  let (authorRaw, _) = T.breakOn ": " remainder
      cleaned        = T.strip (stripTrailingMarkdown authorRaw)
  in if T.null cleaned || T.length cleaned > maxAuthorLength
       then Nothing
       else Just cleaned

stripTrailingMarkdown :: Text -> Text
stripTrailingMarkdown raw =
  let trimmed = T.stripEnd raw
      withoutBoldClose = Data.Maybe.fromMaybe trimmed (T.stripSuffix "**" trimmed)
  in T.stripEnd withoutBoldClose

stripEmojisAndPunctuation :: Text -> Text
stripEmojisAndPunctuation =
  T.strip
    . T.dropAround isFringeChar
    . T.filter (not . isStripChar)
  where
    isStripChar c = c == '*' || c == '_'
    isFringeChar c = isEmojiOrSpace c || c == ':' || c == '–' || c == '—' || c == '-'

guard' :: Bool -> Maybe ()
guard' True  = Just ()
guard' False = Nothing

rightToMaybe :: Either e a -> Maybe a
rightToMaybe = either (const Nothing) Just
