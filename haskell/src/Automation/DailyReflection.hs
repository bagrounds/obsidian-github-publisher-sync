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
  ) where

import Data.List (sort)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, doesFileExist, listDirectory)
import System.FilePath ((</>), dropExtension)

import Automation.BlogSeriesConfig (BlogSeriesConfig (..))
import Automation.Types
  ( blueskySectionHeader
  , mastodonSectionHeader
  , tweetSectionHeader
  )

embedSectionHeaders :: [Text]
embedSectionHeaders = [tweetSectionHeader, blueskySectionHeader, mastodonSectionHeader]

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
  let backLink = maybe "" (\pd -> " | [[reflections/" <> pd <> "|⏮️]]") previousDate
  in T.intercalate "\n"
    [ "---"
    , "share: true"
    , "aliases:"
    , "  - " <> date
    , "title: " <> date
    , "URL: https://bagrounds.org/reflections/" <> date
    , "Author: \"[[bryan-grounds]]\""
    , "tags:"
    , "---"
    , "[[index|Home]] > [[reflections/index|Reflections]]" <> backLink
    , "# " <> date
    , ""
    ]

buildSeriesSectionHeading :: BlogSeriesConfig -> Text
buildSeriesSectionHeading series =
  "## [[" <> bscId series <> "/index|" <> bscIcon series <> " " <> bscName series <> "]]"

buildPostLink :: Text -> Text -> Text -> Text
buildPostLink seriesId filenameNoExt displayTitle =
  "- [[" <> seriesId <> "/" <> filenameNoExt <> "|" <> displayTitle <> "]]"

addForwardLink :: Text -> Text -> Text
addForwardLink content targetDate =
  let forwardLink = "[[reflections/" <> targetDate <> "|⏭️]]"
  in case T.isInfixOf "⏭️" content of
    True  -> content
    False -> T.replace "⏮️]]" ("⏮️]] " <> forwardLink) content

findFirstEmbedSectionIndex :: Text -> Maybe Int
findFirstEmbedSectionIndex content =
  let indices = filter (>= 0) $ fmap (\h -> fromIntegral $ T.length $ fst $ T.breakOn h content) embedSectionHeaders
      validIndices = filter (\i -> i < T.length content) $ fmap fromIntegral indices
  in case filter (\h -> T.isInfixOf h content) embedSectionHeaders of
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
  in case findFirstEmbedSectionIndex content of
    Just idx ->
      let (before, after) = T.splitAt idx content
      in T.stripEnd before <> "\n\n" <> sectionBlock <> "\n\n" <> after
    Nothing ->
      T.stripEnd content <> "\n\n" <> sectionBlock <> "\n"

insertPostLink :: Text -> BlogSeriesConfig -> Text -> Text -> Maybe Text -> Text
insertPostLink content series filenameNoExt displayTitle replacingFilenameNoExt =
  let linkTarget = "[[" <> bscId series <> "/" <> filenameNoExt <> "|"
  in case T.isInfixOf linkTarget content of
    True -> content
    False ->
      let postLink = buildPostLink (bscId series) filenameNoExt displayTitle
          replacedContent = case replacingFilenameNoExt of
            Just oldName ->
              let oldLinkTarget = "- [[" <> bscId series <> "/" <> oldName <> "|"
              in case T.isInfixOf oldLinkTarget content of
                True ->
                  let ls = T.splitOn "\n" content
                  in T.intercalate "\n" $ fmap (\l -> if T.isPrefixOf oldLinkTarget l then postLink else l) ls
                False -> content
            Nothing -> content
          sectionHeading = buildSeriesSectionHeading series
      in case T.isInfixOf sectionHeading replacedContent of
        True  -> appendLinkToExistingSection replacedContent sectionHeading postLink
        False -> insertNewSection replacedContent sectionHeading postLink

isDateFile :: Text -> Text -> Bool
isDateFile today f =
  T.length f >= 14
    && T.isSuffixOf ".md" f
    && T.index f 4 == '-'
    && T.index f 7 == '-'
    && f < (today <> ".md")

findPreviousReflectionDate :: FilePath -> Text -> IO (Maybe Text)
findPreviousReflectionDate reflectionsDir today = do
  exists <- doesDirectoryExist reflectionsDir
  case exists of
    False -> pure Nothing
    True  -> do
      entries <- listDirectory reflectionsDir
      let candidates = sort $ filter (isDateFile today) $ fmap T.pack entries
      pure $ case candidates of
        [] -> Nothing
        _  -> Just $ T.pack $ dropExtension $ T.unpack $ last candidates

ensureDailyReflection :: FilePath -> Text -> IO EnsureReflectionResult
ensureDailyReflection reflectionsDir today = do
  let reflectionPath = reflectionsDir </> T.unpack today <> ".md"
  exists <- doesFileExist reflectionPath
  case exists of
    True -> pure EnsureReflectionResult
      { errCreated = False, errPreviousDate = Nothing, errForwardLinkAdded = False }
    False -> do
      previousDate <- findPreviousReflectionDate reflectionsDir today
      let content = buildReflectionContent today previousDate
      createDirectoryIfMissing True reflectionsDir
      TIO.writeFile reflectionPath content
      forwardLinkAdded <- case previousDate of
        Nothing -> pure False
        Just pd -> do
          let prevPath = reflectionsDir </> T.unpack pd <> ".md"
          prevExists <- doesFileExist prevPath
          case prevExists of
            False -> pure False
            True  -> do
              prevContent <- TIO.readFile prevPath
              let updated = addForwardLink prevContent today
              case updated == prevContent of
                True  -> pure False
                False -> TIO.writeFile prevPath updated >> pure True
      pure EnsureReflectionResult
        { errCreated = True, errPreviousDate = previousDate, errForwardLinkAdded = forwardLinkAdded }

updateDailyReflection :: FilePath -> Text -> BlogSeriesConfig -> Text -> Text -> Maybe Text -> IO UpdateReflectionResult
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
  case linkInserted of
    True  -> TIO.writeFile reflectionPath updated
    False -> pure ()
  pure UpdateReflectionResult
    { urrReflectionCreated = errCreated
    , urrSectionCreated    = not hadSection && linkInserted
    , urrLinkInserted      = linkInserted
    , urrForwardLinkAdded  = errForwardLinkAdded
    , urrPreviousDate      = errPreviousDate
    }
