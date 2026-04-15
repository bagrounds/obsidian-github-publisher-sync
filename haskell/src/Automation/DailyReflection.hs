module Automation.DailyReflection
  ( EnsureReflectionResult (..)
  , UpdateReflectionResult (..)
  , buildReflectionContent
  , buildSeriesSectionHeading
  , buildPostLink
  , addForwardLink
  , insertPostLink
  , findPreviousReflectionDate
  , ensureDailyReflection
  , updateDailyReflection
  , findFirstSectionIndex
  , embedSectionHeaders
  ) where

import Control.Monad (when)
import Data.List (sort)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, doesFileExist, listDirectory)
import System.FilePath ((</>), dropExtension)

import Automation.Frontmatter (quoteYamlValue)

import Automation.BlogSeriesConfig (BlogSeriesConfig (..))
import Automation.Title (Title, unTitle)
import Automation.Wikilink (formatWikilink)
import qualified Automation.Platforms.Bluesky as Bluesky
import qualified Automation.Platforms.Mastodon as Mastodon
import qualified Automation.Platforms.Twitter as Twitter
import Automation.Platform (updatesSectionHeader)

embedSectionHeaders :: [Text]
embedSectionHeaders = [Twitter.sectionHeader, Bluesky.sectionHeader, Mastodon.sectionHeader]

trailingSectionHeaders :: [Text]
trailingSectionHeaders = updatesSectionHeader : embedSectionHeaders

data EnsureReflectionResult = EnsureReflectionResult
  { errCreated          :: Bool
  , errPreviousDate     :: Maybe Text
  , errForwardLinkAdded :: Bool
  } deriving (Show, Eq)

data UpdateReflectionResult = UpdateReflectionResult
  { urrReflectionCreated :: Bool
  , urrSectionCreated    :: Bool
  , urrLinkInserted      :: Bool
  , urrForwardLinkAdded  :: Bool
  , urrPreviousDate      :: Maybe Text
  } deriving (Show, Eq)

buildReflectionContent :: Text -> Maybe Text -> Text
buildReflectionContent date previousDate =
  let backLink = maybe "" (\pd -> " | " <> formatWikilink ("reflections/" <> pd) "⏮️") previousDate
  in T.intercalate "\n"
    [ "---"
    , "share: true"
    , "aliases:"
    , "  - " <> quoteYamlValue date
    , "title: " <> quoteYamlValue date
    , "URL: " <> quoteYamlValue ("https://bagrounds.org/reflections/" <> date)
    , "Author: \"[[bryan-grounds]]\""
    , "tags:"
    , "---"
    , formatWikilink "index" "Home" <> " > " <> formatWikilink "reflections/index" "Reflections" <> backLink
    , "# " <> date
    , ""
    ]

buildSeriesSectionHeading :: BlogSeriesConfig -> Text
buildSeriesSectionHeading series =
  "## " <> formatWikilink (bscId series <> "/index") (bscIcon series <> " " <> bscName series)

buildPostLink :: Text -> Text -> Title -> Text
buildPostLink seriesId filenameNoExt displayTitle =
  "- " <> formatWikilink (seriesId <> "/" <> filenameNoExt) (unTitle displayTitle)

addForwardLink :: Text -> Text -> Text
addForwardLink content targetDate =
  let forwardLink = formatWikilink ("reflections/" <> targetDate) "⏭️"
      navMarker = "[[reflections/index|Reflections]]"
  in if T.isInfixOf "⏭️" content
    then content
    else if T.isInfixOf "⏮️]]" content
      then T.replace "⏮️]]" ("⏮️]] " <> forwardLink) content
      else if T.isInfixOf navMarker content
        then T.replace navMarker (navMarker <> " | " <> forwardLink) content
        else content

findFirstSectionIndex :: [Text] -> Text -> Maybe Int
findFirstSectionIndex headers content =
  case filter (`T.isInfixOf` content) headers of
    [] -> Nothing
    found ->
      let positions = fmap (\h -> T.length $ fst $ T.breakOn h content) found
      in Just $ minimum positions

appendLinkToExistingSection :: Text -> Text -> Text -> Text
appendLinkToExistingSection content sectionHeading postLink =
  let ls = T.splitOn "\n" content
      sectionIndex = length $ takeWhile (not . T.isPrefixOf sectionHeading) ls
      (before, after) = splitAt (sectionIndex + 1) ls
      (listItems, rest) = span (T.isPrefixOf "- ") after
  in T.intercalate "\n" (before <> listItems <> [postLink] <> rest)

insertNewSection :: Text -> Text -> Text -> Text
insertNewSection content sectionHeading postLink =
  let sectionBlock = sectionHeading <> "\n" <> postLink
  in case findFirstSectionIndex trailingSectionHeaders content of
    Just idx ->
      let (before, after) = T.splitAt idx content
      in T.stripEnd before <> "\n\n" <> sectionBlock <> "\n\n" <> after
    Nothing ->
      T.stripEnd content <> "\n\n" <> sectionBlock <> "\n"

insertPostLink :: Text -> BlogSeriesConfig -> Text -> Title -> Maybe Text -> Text
insertPostLink content series filenameNoExt displayTitle replacingFilenameNoExt =
  let linkTarget = "[[" <> bscId series <> "/" <> filenameNoExt <> "|"
  in if T.isInfixOf linkTarget content
    then content
    else
      let postLink = buildPostLink (bscId series) filenameNoExt displayTitle
          replacedContent = case replacingFilenameNoExt of
            Just oldName ->
              let oldLinkTarget = "- [[" <> bscId series <> "/" <> oldName <> "|"
              in if T.isInfixOf oldLinkTarget content
                then
                  let ls = T.splitOn "\n" content
                  in T.intercalate "\n" $ fmap (\l -> if T.isPrefixOf oldLinkTarget l then postLink else l) ls
                else content
            Nothing -> content
          sectionHeading = buildSeriesSectionHeading series
      in if T.isInfixOf sectionHeading replacedContent
        then appendLinkToExistingSection replacedContent sectionHeading postLink
        else insertNewSection replacedContent sectionHeading postLink

isDateFile :: Text -> Text -> Bool
isDateFile today f =
  T.length f >= 13
    && T.isSuffixOf ".md" f
    && T.index f 4 == '-'
    && T.index f 7 == '-'
    && f < (today <> ".md")

findPreviousReflectionDate :: FilePath -> Text -> IO (Maybe Text)
findPreviousReflectionDate reflectionsDir today = do
  exists <- doesDirectoryExist reflectionsDir
  if exists
    then do
      entries <- listDirectory reflectionsDir
      let candidates = sort $ filter (isDateFile today) $ fmap T.pack entries
      pure $ case candidates of
        [] -> Nothing
        _  -> Just $ T.pack $ dropExtension $ T.unpack $ last candidates
    else pure Nothing

ensureDailyReflection :: FilePath -> Text -> IO EnsureReflectionResult
ensureDailyReflection reflectionsDir today = do
  let reflectionPath = reflectionsDir </> T.unpack today <> ".md"
  exists <- doesFileExist reflectionPath
  if exists
    then pure EnsureReflectionResult
      { errCreated = False, errPreviousDate = Nothing, errForwardLinkAdded = False }
    else do
      previousDate <- findPreviousReflectionDate reflectionsDir today
      let content = buildReflectionContent today previousDate
      createDirectoryIfMissing True reflectionsDir
      TIO.writeFile reflectionPath content
      forwardLinkAdded <- case previousDate of
        Nothing -> pure False
        Just pd -> do
          let prevPath = reflectionsDir </> T.unpack pd <> ".md"
          prevExists <- doesFileExist prevPath
          if prevExists
            then do
              prevContent <- TIO.readFile prevPath
              let updated = addForwardLink prevContent today
              if updated == prevContent
                then pure False
                else TIO.writeFile prevPath updated >> pure True
            else pure False
      pure EnsureReflectionResult
        { errCreated = True, errPreviousDate = previousDate, errForwardLinkAdded = forwardLinkAdded }

updateDailyReflection :: FilePath -> Text -> BlogSeriesConfig -> Text -> Title -> Maybe Text -> IO UpdateReflectionResult
updateDailyReflection vaultDir today series postFilename postTitle replacingFilename = do
  let reflectionsDir = vaultDir </> "reflections"
  EnsureReflectionResult{..} <- ensureDailyReflection reflectionsDir today
  let reflectionPath = reflectionsDir </> T.unpack today <> ".md"
  content <- TIO.readFile reflectionPath
  let filenameNoExt = T.pack $ dropExtension $ T.unpack postFilename
      replacingFilenameNoExt = fmap (T.pack . dropExtension . T.unpack) replacingFilename
      hadSection = T.isInfixOf (buildSeriesSectionHeading series) content
      updated = insertPostLink content series filenameNoExt postTitle replacingFilenameNoExt
      linkInserted = updated /= content
  when linkInserted $
    TIO.writeFile reflectionPath updated
  pure UpdateReflectionResult
    { urrReflectionCreated = errCreated
    , urrSectionCreated    = not hadSection && linkInserted
    , urrLinkInserted      = linkInserted
    , urrForwardLinkAdded  = errForwardLinkAdded
    , urrPreviousDate      = errPreviousDate
    }
