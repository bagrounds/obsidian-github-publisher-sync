module Automation.DailyReflection
  ( UpdateReflectionResult (..)
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
  , changesLink
  , ChangesStats (..)
  , renderChangesStats
  , buildChangesStatsPreview
  , upsertChangesPreview
  ) where

import Control.Monad (when)
import Data.List (sort)
import Data.Maybe (catMaybes)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Data.Time (Day)
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, doesFileExist, listDirectory)
import System.FilePath ((</>), dropExtension)

import Automation.Frontmatter (quoteYamlValue)
import Automation.PacificTime (formatDay)

import Automation.BlogSeriesConfig (BlogSeriesConfig (..))
import Automation.Title (Title, unTitle)
import Automation.Wikilink (formatWikilink, NavigableDirectory (..), directoryIndexLink, buildNavBackLink, insertForwardNavLink)
import qualified Automation.Platforms.Bluesky as Bluesky
import qualified Automation.Platforms.Mastodon as Mastodon
import qualified Automation.Platforms.Twitter as Twitter
import Automation.Platform (updatesSectionHeader)
import qualified Automation.DailyReflection.EnsureResult as EnsureResult

embedSectionHeaders :: [Text]
embedSectionHeaders = [Twitter.sectionHeader, Bluesky.sectionHeader, Mastodon.sectionHeader]

changesLink :: Text
changesLink = "## " <> formatWikilink "changes/index" "\128260 Changes"

-- | Statistics for a day's changes page. Using structured integer fields rather than
-- pre-rendered text ensures these values are constructed at the source (from live PageEntry
-- data) and rendered only through 'renderChangesStats', keeping presentation separate from data.
data ChangesStats = ChangesStats
  { statsPageCount     :: Int
  , statsImageCount    :: Int
  , statsLinkCount     :: Int
  , statsBlueskyCount  :: Int
  , statsMastodonCount :: Int
  , statsTwitterCount  :: Int
  } deriving (Show, Eq)

renderChangesStats :: ChangesStats -> Text
renderChangesStats stats =
  let pageWord = if statsPageCount stats == 1 then "page" else "pages"
      counts = catMaybes
        [ renderStatCount (statsImageCount stats) "🖼️" "images"
        , renderStatCount (statsLinkCount stats) "🔗" "links"
        , renderStatCount (statsBlueskyCount stats) "🦋" "Bluesky"
        , renderStatCount (statsMastodonCount stats) "🐘" "Mastodon"
        , renderStatCount (statsTwitterCount stats) "🐦" "Twitter"
        ]
      parts = (T.pack (show (statsPageCount stats)) <> " " <> pageWord) : counts
  in "📊 " <> T.intercalate " · " parts

renderStatCount :: Int -> Text -> Text -> Maybe Text
renderStatCount count emoji label
  | count > 0 = Just (T.pack (show count) <> " " <> emoji <> " " <> label)
  | otherwise = Nothing

changesStatsPreviewLinePrefix :: Text
changesStatsPreviewLinePrefix = "[[changes/"

buildChangesStatsPreview :: Day -> ChangesStats -> Text
buildChangesStatsPreview date stats =
  formatWikilink ("changes/" <> formatDay date) (formatDay date) <> " | " <> renderChangesStats stats

upsertChangesPreview :: Text -> Day -> ChangesStats -> Text
upsertChangesPreview content date stats =
  let preview = buildChangesStatsPreview date stats
  in if T.isInfixOf changesLink content
    then replaceChangesSection content preview
    else T.stripEnd content <> "\n\n" <> changesLink <> "\n" <> preview <> "\n"

replaceChangesSection :: Text -> Text -> Text
replaceChangesSection content preview =
  let contentLines = T.splitOn "\n" content
      (before, fromChanges) = break (== changesLink) contentLines
  in case fromChanges of
    [] -> content
    (_ : rest) ->
      let afterOld = case rest of
            (nextLine : remaining)
              | T.isPrefixOf changesStatsPreviewLinePrefix nextLine -> remaining
            _ -> rest
      in T.intercalate "\n" (before <> [changesLink, preview] <> afterOld)

trailingSectionHeaders :: [Text]
trailingSectionHeaders = updatesSectionHeader : changesLink : embedSectionHeaders

data UpdateReflectionResult = UpdateReflectionResult
  { reflectionCreated :: Bool
  , sectionCreated    :: Bool
  , linkInserted      :: Bool
  , forwardLinkAdded  :: Bool
  , previousDate      :: Maybe Text
  } deriving (Show, Eq)

buildReflectionContent :: Day -> Maybe Text -> Text
buildReflectionContent date previousDate =
  let dateText = formatDay date
      backLink = maybe "" (\pd -> " | " <> buildNavBackLink Reflections pd) previousDate
  in T.intercalate "\n"
    [ "---"
    , "share: true"
    , "aliases:"
    , "  - " <> quoteYamlValue dateText
    , "title: " <> quoteYamlValue dateText
    , "URL: " <> quoteYamlValue ("https://bagrounds.org/reflections/" <> dateText)
    , "Author: \"[[bryan-grounds]]\""
    , "tags:"
    , "---"
    , formatWikilink "index" "Home" <> " > " <> directoryIndexLink Reflections <> backLink
    , "# " <> dateText
    , ""
    , changesLink
    , ""
    ]

buildSeriesSectionHeading :: BlogSeriesConfig -> Text
buildSeriesSectionHeading series =
  "## " <> formatWikilink (seriesId series <> "/index") (icon series <> " " <> name series)

buildPostLink :: Text -> Text -> Title -> Text
buildPostLink seriesId filenameNoExt displayTitle =
  "- " <> formatWikilink (seriesId <> "/" <> filenameNoExt) (unTitle displayTitle)

addForwardLink :: Text -> Text -> Text
addForwardLink = insertForwardNavLink Reflections

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
  let linkTarget = "[[" <> seriesId series <> "/" <> filenameNoExt <> "|"
  in if T.isInfixOf linkTarget content
    then content
    else
      let postLink = buildPostLink (seriesId series) filenameNoExt displayTitle
          replacedContent = case replacingFilenameNoExt of
            Just oldName ->
              let oldLinkTarget = "- [[" <> seriesId series <> "/" <> oldName <> "|"
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

ensureDailyReflection :: FilePath -> Day -> IO EnsureResult.EnsureReflectionResult
ensureDailyReflection reflectionsDir today = do
  let todayText = formatDay today
      reflectionPath = reflectionsDir </> T.unpack todayText <> ".md"
  exists <- doesFileExist reflectionPath
  if exists
    then pure EnsureResult.EnsureReflectionResult
      { EnsureResult.reflectionCreated = False, EnsureResult.previousDate = Nothing, EnsureResult.forwardLinkAdded = False }
    else do
      maybePreviousDate <- findPreviousReflectionDate reflectionsDir todayText
      let content = buildReflectionContent today maybePreviousDate
      createDirectoryIfMissing True reflectionsDir
      TIO.writeFile reflectionPath content
      didAddForwardLink <- case maybePreviousDate of
        Nothing -> pure False
        Just pd -> do
          let prevPath = reflectionsDir </> T.unpack pd <> ".md"
          prevExists <- doesFileExist prevPath
          if prevExists
            then do
              prevContent <- TIO.readFile prevPath
              let updated = addForwardLink prevContent todayText
              if updated == prevContent
                then pure False
                else TIO.writeFile prevPath updated >> pure True
            else pure False
      pure EnsureResult.EnsureReflectionResult
        { EnsureResult.reflectionCreated = True, EnsureResult.previousDate = maybePreviousDate, EnsureResult.forwardLinkAdded = didAddForwardLink }

updateDailyReflection :: FilePath -> Day -> BlogSeriesConfig -> Text -> Title -> Maybe Text -> IO UpdateReflectionResult
updateDailyReflection vaultDir today series postFilename postTitle replacingFilename = do
  let todayText = formatDay today
      reflectionsDir = vaultDir </> "reflections"
  EnsureResult.EnsureReflectionResult{..} <- ensureDailyReflection reflectionsDir today
  let reflectionPath = reflectionsDir </> T.unpack todayText <> ".md"
  content <- TIO.readFile reflectionPath
  let filenameNoExt = T.pack $ dropExtension $ T.unpack postFilename
      replacingFilenameNoExt = fmap (T.pack . dropExtension . T.unpack) replacingFilename
      hadSection = T.isInfixOf (buildSeriesSectionHeading series) content
      updated = insertPostLink content series filenameNoExt postTitle replacingFilenameNoExt
      linkInserted' = updated /= content
  when linkInserted' $
    TIO.writeFile reflectionPath updated
  pure UpdateReflectionResult
    { reflectionCreated = reflectionCreated
    , sectionCreated    = not hadSection && linkInserted'
    , linkInserted      = linkInserted'
    , forwardLinkAdded  = forwardLinkAdded
    , previousDate      = previousDate
    }
