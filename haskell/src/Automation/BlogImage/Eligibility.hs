module Automation.BlogImage.Eligibility
  ( CandidateEligibility (..)
  , IneligibilityReason (..)
  , BackfillCandidate (..)
  , hasEmbeddedImage
  , shouldRegenerateImage
  , shouldHaveImage
  , isPostFile
  , hasDatePrefix
  , parseDateFromFilename
  , isDateOnlyTitle
  , checkCandidateEligibility
  ) where

import Data.Char (isDigit)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (Day, defaultTimeLocale, formatTime)
import Data.Time.Format (parseTimeM)
import Text.Regex.TDFA ((=~))

import Automation.BlogImage.ContentDirectory (ContentDirectory (..))
import Automation.BlogImage.TitleExtraction (extractTitle)
import Automation.Frontmatter (parseFrontmatter)

data CandidateEligibility
  = Eligible { needsRegeneration :: Bool }
  | Ineligible IneligibilityReason
  deriving (Show, Eq)

data IneligibilityReason
  = FutureReflection
  | AlreadyHasImage
  | UntitledReflection
  deriving (Show, Eq)

data BackfillCandidate = BackfillCandidate
  { bcFilePath          :: FilePath
  , bcDirectory         :: ContentDirectory
  , bcFilename          :: Text
  , bcDate              :: Day
  , bcNeedsRegeneration :: Bool
  }

excludedFiles :: [Text]
excludedFiles = ["index.md", "AGENTS.md", "IDEAS.md"]

hasEmbeddedImage :: Text -> Bool
hasEmbeddedImage content =
  let s = T.unpack content
      obsidianMatch = s =~ ("!\\[\\[([^]]*/)?" <> "[^]]+\\.(jpg|jpeg|png|gif|webp)\\]\\]" :: String) :: Bool
      markdownMatch = s =~ ("!\\[[^]]*\\]\\([^)]+\\.(jpg|jpeg|png|gif|webp)\\)" :: String) :: Bool
  in obsidianMatch || markdownMatch

shouldRegenerateImage :: Text -> Bool
shouldRegenerateImage content =
  let (fm, _) = parseFrontmatter content
  in case Map.lookup "regenerate_image" fm of
    Just v  -> T.strip (T.toLower v) `elem` ["true", "yes"]
    Nothing -> False

shouldHaveImage :: Text -> Bool
shouldHaveImage filename =
  T.isSuffixOf ".md" filename
    && notElem filename excludedFiles

isPostFile :: Text -> Bool
isPostFile filename =
  T.isSuffixOf ".md" filename
    && notElem filename excludedFiles
    && hasDatePrefix filename

hasDatePrefix :: Text -> Bool
hasDatePrefix t =
  T.length t >= 10
    && T.all isDigit (T.take 4 t)
    && T.index t 4 == '-'
    && T.all isDigit (T.take 2 (T.drop 5 t))
    && T.index t 7 == '-'
    && T.all isDigit (T.take 2 (T.drop 8 t))

parseDateFromFilename :: Text -> Maybe Day
parseDateFromFilename filename =
  if hasDatePrefix filename
    then parseTimeM True defaultTimeLocale "%Y-%m-%d" (T.unpack (T.take 10 filename))
    else Nothing

isDateOnlyTitle :: Text -> Day -> Bool
isDateOnlyTitle content date =
  let title = extractTitle content
      dateText = T.pack (formatTime defaultTimeLocale "%Y-%m-%d" date)
  in title == dateText

checkCandidateEligibility :: ContentDirectory -> Day -> Text -> Text -> CandidateEligibility
checkCandidateEligibility directory today filename content =
  case parseDateFromFilename filename of
    Just fileDate
      | directory == Reflections && fileDate > today -> Ineligible FutureReflection
    fileDate ->
      let requiresRegeneration = shouldRegenerateImage content
          untitledReflection = directory == Reflections
            && maybe False (isDateOnlyTitle content) fileDate
      in if untitledReflection
         then Ineligible UntitledReflection
         else if hasEmbeddedImage content && not requiresRegeneration
              then Ineligible AlreadyHasImage
              else Eligible requiresRegeneration
