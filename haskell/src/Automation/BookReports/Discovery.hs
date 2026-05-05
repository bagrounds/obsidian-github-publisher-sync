module Automation.BookReports.Discovery
  ( BookCandidate (..)
  , listExistingBookSlugs
  , listRecentReflectionFiles
  , extractBookCandidatesFromReflection
  , recentReflectionWindow
  , isReflectionFileName
  ) where

import Data.Char (isDigit)
import Data.List (sortOn)
import qualified Data.Maybe
import Data.Maybe (mapMaybe)
import Data.Ord (Down (..))
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import System.Directory (doesDirectoryExist, listDirectory)
import System.FilePath (takeBaseName, (</>))

import Automation.BookReports.Types (BookSlug, BookTitle, mkBookSlug, mkBookTitle)

data BookCandidate = BookCandidate
  { candidateSlug       :: BookSlug
  , candidateTitle      :: BookTitle
  , candidateSourceLine :: Text
  , candidateSourceFile :: FilePath
  } deriving (Eq, Show)

recentReflectionWindow :: Int
recentReflectionWindow = 7

isReflectionFileName :: FilePath -> Bool
isReflectionFileName path =
  let base = takeBaseName path
  in length base == 10
     && all isExpectedChar (zip [0 :: Int ..] base)
  where
    isExpectedChar (idx, character)
      | idx == 4 || idx == 7 = character == '-'
      | otherwise            = isDigit character

listRecentReflectionFiles :: FilePath -> IO [FilePath]
listRecentReflectionFiles reflectionsDir = do
  exists <- doesDirectoryExist reflectionsDir
  if not exists
    then pure []
    else do
      entries <- listDirectory reflectionsDir
      let dateNamedReflections = filter isReflectionFileName entries
          mostRecentFirst      = sortOn (Down . takeBaseName) dateNamedReflections
          recent               = take recentReflectionWindow mostRecentFirst
      pure (fmap (reflectionsDir </>) recent)

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
        Nothing                  -> Nothing
        Just "index"             -> Nothing
        Just stem                -> rightToMaybe (mkBookSlug (T.toLower stem))

extractBookCandidatesFromReflection
  :: Set.Set BookSlug
  -> FilePath
  -> Text
  -> [BookCandidate]
extractBookCandidatesFromReflection knownSlugs sourcePath body =
  let allLinks = concatMap parseBookLinksOnLine (T.lines body)
      missing  = filter (\link -> not (Set.member (linkSlug link) knownSlugs)) allLinks
  in fmap toCandidate missing
  where
    toCandidate parsed =
      BookCandidate
        { candidateSlug       = linkSlug parsed
        , candidateTitle      = linkTitle parsed
        , candidateSourceLine = T.strip (linkRawLine parsed)
        , candidateSourceFile = sourcePath
        }

data ParsedLink = ParsedLink
  { linkSlug    :: BookSlug
  , linkTitle   :: BookTitle
  , linkRawLine :: Text
  } deriving (Eq, Show)

parseBookLinksOnLine :: Text -> [ParsedLink]
parseBookLinksOnLine line =
     parseMarkdownBookLinksOnLine line
  <> parseWikiBookLinksOnLine line

parseMarkdownBookLinksOnLine :: Text -> [ParsedLink]
parseMarkdownBookLinksOnLine line =
  mapMaybe extractFromOpenBracket (segmentsAfter '[' line)
  where
    extractFromOpenBracket segment = do
      (titleText, afterTitle) <- splitOnFirst "](" segment
      (urlText, _)            <- splitOnFirst ")"  afterTitle
      slugText                <- extractBookSlugFromUrlPath urlText
      slug                    <- rightToMaybe (mkBookSlug slugText)
      title                   <- rightToMaybe (mkBookTitle titleText)
      pure ParsedLink { linkSlug = slug, linkTitle = title, linkRawLine = line }

parseWikiBookLinksOnLine :: Text -> [ParsedLink]
parseWikiBookLinksOnLine line =
  mapMaybe extractFromDoubleBracket (segmentsAfterDoubleBracket line)
  where
    extractFromDoubleBracket segment = do
      (target, _) <- splitOnFirst "]]" segment
      let (rawTarget, alias) = case splitOnFirst "|" target of
            Just (lhs, rhs) -> (lhs, rhs)
            Nothing         -> (target, target)
      slugText <- extractBookSlugFromTarget rawTarget
      slug     <- rightToMaybe (mkBookSlug slugText)
      title    <- rightToMaybe (mkBookTitle alias)
      pure ParsedLink { linkSlug = slug, linkTitle = title, linkRawLine = line }

segmentsAfter :: Char -> Text -> [Text]
segmentsAfter delimiter input =
  drop 1 (T.split (== delimiter) input)

segmentsAfterDoubleBracket :: Text -> [Text]
segmentsAfterDoubleBracket input =
  drop 1 (T.splitOn "[[" input)

splitOnFirst :: Text -> Text -> Maybe (Text, Text)
splitOnFirst needle haystack =
  case T.breakOn needle haystack of
    (_, "")    -> Nothing
    (lhs, rhs) -> Just (lhs, T.drop (T.length needle) rhs)

extractBookSlugFromUrlPath :: Text -> Maybe Text
extractBookSlugFromUrlPath rawUrl =
  let cleaned = T.takeWhile (\c -> c /= '#' && c /= '?') (T.strip rawUrl)
  in slugFromBooksPath (T.splitOn "/" cleaned) >>= dropMdSuffix

extractBookSlugFromTarget :: Text -> Maybe Text
extractBookSlugFromTarget rawTarget =
  let cleaned = T.strip rawTarget
  in slugFromBooksPath (T.splitOn "/" cleaned) >>= dropOptionalMdSuffix

slugFromBooksPath :: [Text] -> Maybe Text
slugFromBooksPath segments =
  case dropWhile (\s -> T.toLower s /= "books") segments of
    [] -> Nothing
    (_ : afterBooks) ->
      case afterBooks of
        []                 -> Nothing
        ("" : _)           -> Nothing
        (slugSegment : _)  -> Just slugSegment

dropMdSuffix :: Text -> Maybe Text
dropMdSuffix raw = do
  withoutMd <- T.stripSuffix ".md" raw
  if T.null withoutMd || withoutMd == "index"
    then Nothing
    else Just (T.toLower withoutMd)

dropOptionalMdSuffix :: Text -> Maybe Text
dropOptionalMdSuffix raw =
  let withoutMd = Data.Maybe.fromMaybe raw (T.stripSuffix ".md" raw)
  in if T.null withoutMd || withoutMd == "index"
       then Nothing
       else Just (T.toLower withoutMd)

rightToMaybe :: Either e a -> Maybe a
rightToMaybe = either (const Nothing) Just
