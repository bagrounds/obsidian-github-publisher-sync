module Automation.SocialPosting.ContentDiscovery
  ( ContentNote (..)
  , ContentToPost (..)
  , FindContentConfig (..)
  , readContentNote
  , discoverContentToPost
  , bfsContentDiscovery
  , isPostableContent
  , isChangesPath
  , isIndexPath
  , isUntitledReflection
  , isReflectionEligibleForPosting
  , checkBfsEligibility
  , isAwaitingImageBackfill
  , isRecentlyBackfilled
  , parseImageDate
  , detectPostedPlatforms
  , checkUrlPublished
  , urlFromFilePath
  , validateNoteUrl
  , defaultPostingCutoff
  ) where

import Control.Applicative ((<|>))
import Control.Exception (SomeException, try)
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Set (Set)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Data.Time
  ( Day
  , NominalDiffTime
  , UTCTime (..)
  , defaultTimeLocale
  , diffUTCTime
  , getCurrentTime
  , parseTimeM
  , utctDayTime
  )
import Data.Time.LocalTime (TimeOfDay (..), timeToTimeOfDay)
import qualified Network.HTTP.Client as HTTP
import Network.HTTP.Client (Manager)
import Network.HTTP.Types.Status (statusIsSuccessful)
import System.Directory (doesFileExist)
import System.FilePath (takeBaseName, takeDirectory, takeFileName, (</>))
import Text.Regex.TDFA ((=~))

import Automation.BlogImage.Eligibility (hasEmbeddedImage, shouldHaveImage)
import Automation.BlogImage.ContentDirectory (ContentDirectory (..), contentDirectoryFromText)
import Automation.Frontmatter (parseFrontmatter)
import Automation.Platform (Platform (..))
import qualified Automation.Platforms.Bluesky as Bluesky
import qualified Automation.Platforms.Mastodon as Mastodon
import qualified Automation.Platforms.Twitter as Twitter
import Automation.Reflection (findMostRecentReflection)
import Automation.RelativePath (RelativePath, mkRelativePath, unRelativePath)
import Automation.SocialPosting.FrontmatterUpdate (updateFrontmatterUrl)
import Automation.SocialPosting.LinkExtraction (extractMarkdownLinks)
import Automation.Title (Title, mkTitle, unTitle)
import Automation.Url (Url, mkUrl, unUrl)

data ContentNote = ContentNote
  { noteFilePath       :: FilePath
  , noteRelativePath   :: RelativePath
  , noteTitle          :: Title
  , noteUrl            :: Url
  , noteBody           :: Text
  , notePostedPlatforms :: Set Platform
  , noteLinkedNotePaths :: [RelativePath]
  , noteNoSocial       :: Bool
  , noteImageDate      :: Maybe UTCTime
  } deriving (Show, Eq)

data ContentToPost = ContentToPost
  { platform     :: Platform
  , note         :: ContentNote
  , pathFromRoot :: [Text]
  } deriving (Show, Eq)

data FindContentConfig = FindContentConfig
  { contentDir             :: FilePath
  , platforms              :: [Platform]
  , postingCutoff          :: TimeOfDay
  , publicationChecker     :: Maybe (Text -> IO Bool)
  , imageBackfillContentDirs :: [ContentDirectory]
  }

defaultPostingCutoff :: TimeOfDay
defaultPostingCutoff = TimeOfDay 17 0 0

minPostableBodyLength :: Int
minPostableBodyLength = 50

detectPostedPlatforms :: Text -> Set Platform
detectPostedPlatforms content =
  Set.fromList $ mapMaybe checkHeader
    [ (Twitter.sectionHeader, Twitter)
    , (Bluesky.sectionHeader, Bluesky)
    , (Mastodon.sectionHeader, Mastodon)
    ]
  where
    checkHeader (header, platform)
      | T.isInfixOf header content = Just platform
      | otherwise = Nothing

readContentNote :: Text -> FilePath -> IO (Maybe ContentNote)
readContentNote relativePath contentDir = do
  let filePath = contentDir </> T.unpack relativePath
  exists <- doesFileExist filePath
  if exists
    then do
      content <- TIO.readFile filePath
      let (fm, body) = parseFrontmatter content
          postedPlatforms = detectPostedPlatforms content
          linkedPaths = extractMarkdownLinks body relativePath contentDir
          noSocial = Map.lookup "no_social" fm == Just "true"
          titleText = fromMaybe (T.pack $ takeBaseName $ T.unpack relativePath) (Map.lookup "title" fm)
          slug = fromMaybe relativePath (T.stripSuffix ".md" relativePath)
          urlText = fromMaybe ("https://bagrounds.org/" <> slug) (Map.lookup "URL" fm)
          imageDate = Map.lookup "image_date" fm >>= parseImageDate
          validated = do
            title <- mkTitle titleText
            url <- mkUrl urlText
            path <- mkRelativePath relativePath
            paths <- traverse mkRelativePath linkedPaths
            pure ContentNote
              { noteFilePath = filePath
              , noteRelativePath = path
              , noteTitle = title
              , noteUrl = url
              , noteBody = body
              , notePostedPlatforms = postedPlatforms
              , noteLinkedNotePaths = paths
              , noteNoSocial = noSocial
              , noteImageDate = imageDate
              }
      case validated of
        Right note -> pure (Just note)
        Left reason -> do
          putStrLn $ "  ⚠️  Skipping " <> filePath <> ": " <> T.unpack reason
          pure Nothing
    else pure Nothing

parseImageDate :: Text -> Maybe UTCTime
parseImageDate value =
  parseTimeM True defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" (T.unpack value)
    <|> parseTimeM True defaultTimeLocale "%Y-%m-%dT%H:%M:%S%z" (T.unpack value)

checkUrlPublished :: Manager -> Text -> IO Bool
checkUrlPublished manager url = do
  result <- try (do
    req <- HTTP.parseRequest (T.unpack url)
    let headReq = req { HTTP.method = "HEAD", HTTP.redirectCount = 10 }
    resp <- HTTP.httpLbs headReq manager
    pure (statusIsSuccessful (HTTP.responseStatus resp))
    ) :: IO (Either SomeException Bool)
  case result of
    Left _  -> pure False
    Right b -> b `seq` pure b

urlFromFilePath :: Text -> Text
urlFromFilePath relativePath =
  let slug = fromMaybe relativePath (T.stripSuffix ".md" relativePath)
  in "https://bagrounds.org/" <> slug

validateNoteUrl :: (Text -> IO Bool) -> ContentNote -> IO (Maybe ContentNote)
validateNoteUrl checker note = do
  isLive <- checker (unUrl (noteUrl note))
  if isLive
    then pure (Just note)
    else do
      let pathUrl = urlFromFilePath (unRelativePath (noteRelativePath note))
      if pathUrl == unUrl (noteUrl note)
        then do
          putStrLn $ "  🚫 URL not published (404): "
            <> T.unpack (unTitle (noteTitle note)) <> " (" <> T.unpack (unUrl (noteUrl note)) <> ")"
          pure Nothing
        else do
          putStrLn $ "  🔧 Frontmatter URL 404'd (" <> T.unpack (unUrl (noteUrl note))
            <> "), trying file-path URL: " <> T.unpack pathUrl
          isPathLive <- checker pathUrl
          if isPathLive
            then case mkUrl pathUrl of
              Right newUrl -> do
                putStrLn "  ✅ File-path URL is live, updating frontmatter"
                updateFrontmatterUrl (noteFilePath note) pathUrl
                pure (Just note { noteUrl = newUrl })
              Left reason -> do
                putStrLn $ "  ⚠️  Invalid path URL: " <> T.unpack reason
                pure Nothing
            else do
              putStrLn $ "  🚫 Both URLs not published: "
                <> T.unpack (unUrl (noteUrl note)) <> " and " <> T.unpack pathUrl
              pure Nothing

isPostableContent :: ContentNote -> Bool
isPostableContent note =
  not (isIndexPage note)
    && not (isChangesPage note)
    && not (isUntitledReflection note)
    && not (noteNoSocial note)
    && T.length (T.strip (noteBody note)) >= minPostableBodyLength

isIndexPage :: ContentNote -> Bool
isIndexPage = isIndexPath . unRelativePath . noteRelativePath

isIndexPath :: Text -> Bool
isIndexPath p = takeBaseName (T.unpack p) == "index"

isChangesPage :: ContentNote -> Bool
isChangesPage = isChangesPath . unRelativePath . noteRelativePath

isChangesPath :: Text -> Bool
isChangesPath = T.isPrefixOf "changes/"

isUntitledReflection :: ContentNote -> Bool
isUntitledReflection note =
  isReflectionPath (unRelativePath (noteRelativePath note)) && looksLikeDateTitle (unTitle (noteTitle note))

isReflectionPath :: Text -> Bool
isReflectionPath = T.isPrefixOf "reflections/"

looksLikeDateTitle :: Text -> Bool
looksLikeDateTitle title =
  let t = T.strip title
  in (t :: Text) =~ ("^[0-9]{4}-[0-9]{2}-[0-9]{2}$" :: String)

propagationDelay :: NominalDiffTime
propagationDelay = 86400

isAwaitingImageBackfill :: [ContentDirectory] -> UTCTime -> Text -> Text -> Maybe UTCTime -> Bool
isAwaitingImageBackfill contentDirs now relativePath body imageDate =
  let directoryName = T.pack (takeFileName (takeDirectory (T.unpack relativePath)))
      filename = T.pack (takeFileName (T.unpack relativePath))
      directory = contentDirectoryFromText directoryName
      inBackfillDirectory = elem directory contentDirs && shouldHaveImage filename
  in inBackfillDirectory
       && (not (hasEmbeddedImage body) || isRecentlyBackfilled now imageDate)

isRecentlyBackfilled :: UTCTime -> Maybe UTCTime -> Bool
isRecentlyBackfilled _ Nothing = False
isRecentlyBackfilled now (Just generatedTime) = diffUTCTime now generatedTime < propagationDelay

isReflectionEligibleForPosting :: UTCTime -> TimeOfDay -> Day -> Bool
isReflectionEligibleForPosting now postingCutoff reflectionDate =
  let today = utctDay now
      yesterday = pred today
      currentTime = timeToTimeOfDay (utctDayTime now)
  in (reflectionDate == yesterday && currentTime >= postingCutoff)
       || reflectionDate < yesterday

data BfsState = BfsState
  { visited   :: Set Text
  , queue     :: [(Text, [Text])]
  , results   :: [ContentToPost]
  , filled    :: Set Platform
  , parentMap :: Map.Map Text Text
  }

bfsContentDiscovery :: FindContentConfig -> IO [ContentToPost]
bfsContentDiscovery config = do
  mStart <- findMostRecentReflection (contentDir config)
  case mStart of
    Nothing -> do
      putStrLn "  📭 No reflections found"
      pure []
    Just startPath -> do
      let initialState = BfsState
            { visited   = Set.singleton startPath
            , queue     = [(startPath, [startPath])]
            , results   = []
            , filled    = Set.empty
            , parentMap = Map.empty
            }
      bfsLoop config initialState

bfsLoop :: FindContentConfig -> BfsState -> IO [ContentToPost]
bfsLoop config state =
  case queue state of
    [] -> pure (results state)
    _ | Set.fromList (platforms config) == filled state ->
        pure (results state)
    ((currentPath, pathFromRoot) : rest) -> do
      let state' = state { queue = rest }
      mNote <- readContentNote currentPath (contentDir config)
      case mNote of
        Nothing -> bfsLoop config state'
        Just note -> do
          eligible <- checkBfsEligibility (unRelativePath (noteRelativePath note)) (postingCutoff config)
          now <- getCurrentTime
          let awaitingImage = isAwaitingImageBackfill
                (imageBackfillContentDirs config) now
                (unRelativePath (noteRelativePath note)) (noteBody note)
                (noteImageDate note)
          mValidated <- case (isPostableContent note && eligible && not awaitingImage, publicationChecker config) of
            (True, Just checker) -> validateNoteUrl checker note
            (True, Nothing)      -> pure (Just note)
            (False, _)           -> pure Nothing
          let neededPlatforms = filter
                (\p -> not (Set.member p (filled state'))
                       && not (Set.member p (notePostedPlatforms note)))
                (platforms config)
              newResults = case mValidated of
                Just vNote -> fmap (\p -> ContentToPost p vNote pathFromRoot) neededPlatforms
                Nothing    -> []
              newFilled = Set.union (filled state') $
                Set.fromList (fmap platform newResults)
              neighbors = filter (\l -> not (Set.member l (visited state')))
                            (fmap unRelativePath (noteLinkedNotePaths note))
              newVisited = foldl (flip Set.insert) (visited state') neighbors
              newQueue = rest <> fmap (\n -> (n, pathFromRoot <> [n])) neighbors
              state'' = state'
                { visited = newVisited
                , queue   = newQueue
                , results = results state' <> newResults
                , filled  = newFilled
                }
          bfsLoop config state''

checkBfsEligibility :: Text -> TimeOfDay -> IO Bool
checkBfsEligibility relativePath postingCutoff
  | isIndexPath relativePath = pure False
  | isChangesPath relativePath = pure False
  | isReflectionPath relativePath =
      case parseDateFromPath relativePath of
        Nothing -> pure False
        Just reflectionDate -> do
          now <- getCurrentTime
          pure $ isReflectionEligibleForPosting now postingCutoff reflectionDate
  | otherwise = pure True

discoverContentToPost :: FindContentConfig -> Bool -> IO [ContentToPost]
discoverContentToPost config isPastPostingHour =
  if isPastPostingHour
    then do
      mRefl <- findMostRecentReflection (contentDir config)
      case mRefl of
        Nothing -> bfsContentDiscovery config
        Just reflPath -> do
          now <- getCurrentTime
          let eligible = case parseDateFromPath reflPath of
                Nothing -> False
                Just reflectionDate -> isReflectionEligibleForPosting
                  now (postingCutoff config) reflectionDate
          if eligible
            then do
              mNote <- readContentNote reflPath (contentDir config)
              case mNote of
                Just note | isPostableContent note
                          , not (isAwaitingImageBackfill (imageBackfillContentDirs config) now (unRelativePath (noteRelativePath note)) (noteBody note) (noteImageDate note)) -> do
                  mValidated <- case publicationChecker config of
                    Just checker -> validateNoteUrl checker note
                    Nothing      -> pure (Just note)
                  case mValidated of
                    Nothing -> do
                      putStrLn "  🚫 Prior day's reflection not yet published"
                      bfsContentDiscovery config
                    Just vNote -> do
                      let neededPlatforms = filter
                            (\p -> not (Set.member p (notePostedPlatforms vNote)))
                            (platforms config)
                      case neededPlatforms of
                        [] -> bfsContentDiscovery config
                        _  -> pure $ fmap (\p -> ContentToPost p vNote [reflPath]) neededPlatforms
                _ -> bfsContentDiscovery config
            else bfsContentDiscovery config
    else bfsContentDiscovery config

parseDateFromPath :: Text -> Maybe Day
parseDateFromPath path =
  let base = takeBaseName (T.unpack path)
  in parseTimeM True defaultTimeLocale "%Y-%m-%d" base
