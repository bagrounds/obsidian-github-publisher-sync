module Automation.SocialPosting.ContentDiscovery
  ( ContentNote (..)
  , ContentToPost (..)
  , FindContentConfig (..)
  , readContentNote
  , discoverContentToPost
  , bfsContentDiscovery
  , isPostableContent
  , isIndexPath
  , isUntitledReflection
  , isReflectionEligibleForPosting
  , checkBfsEligibility
  , isAwaitingImageBackfill
  , detectPostedPlatforms
  , checkUrlPublished
  , urlFromFilePath
  , validateNoteUrl
  , defaultPostingCutoff
  , findMostRecentReflection
  ) where

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
  , UTCTime (..)
  , defaultTimeLocale
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

import Automation.BlogImage (hasEmbeddedImage, shouldHaveImage)
import Automation.BlogSeriesConfig (imageBackfillContentIds)
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

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

data ContentNote = ContentNote
  { cnFilePath       :: FilePath
  , cnRelativePath   :: RelativePath
  , cnTitle          :: Title
  , cnUrl            :: Url
  , cnBody           :: Text
  , cnPostedPlatforms :: Set Platform
  , cnLinkedNotePaths :: [RelativePath]
  , cnNoSocial       :: Bool
  } deriving (Show, Eq)

data ContentToPost = ContentToPost
  { ctpPlatform     :: Platform
  , ctpNote         :: ContentNote
  , ctpPathFromRoot :: [Text]
  } deriving (Show, Eq)

data FindContentConfig = FindContentConfig
  { fccContentDir           :: FilePath
  , fccPlatforms            :: [Platform]
  , fccPostingCutoff        :: TimeOfDay
  , fccPublicationChecker   :: Maybe (Text -> IO Bool)
  }

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

defaultPostingCutoff :: TimeOfDay
defaultPostingCutoff = TimeOfDay 17 0 0

minPostableBodyLength :: Int
minPostableBodyLength = 50

--------------------------------------------------------------------------------
-- Platform detection
--------------------------------------------------------------------------------

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

--------------------------------------------------------------------------------
-- Reading content notes
--------------------------------------------------------------------------------

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
          validated = do
            title <- mkTitle titleText
            url <- mkUrl urlText
            path <- mkRelativePath relativePath
            paths <- traverse mkRelativePath linkedPaths
            pure ContentNote
              { cnFilePath = filePath
              , cnRelativePath = path
              , cnTitle = title
              , cnUrl = url
              , cnBody = body
              , cnPostedPlatforms = postedPlatforms
              , cnLinkedNotePaths = paths
              , cnNoSocial = noSocial
              }
      case validated of
        Right note -> pure (Just note)
        Left reason -> do
          putStrLn $ "  ⚠️  Skipping " <> filePath <> ": " <> T.unpack reason
          pure Nothing
    else pure Nothing

--------------------------------------------------------------------------------
-- URL validation
--------------------------------------------------------------------------------

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
  isLive <- checker (unUrl (cnUrl note))
  if isLive
    then pure (Just note)
    else do
      let pathUrl = urlFromFilePath (unRelativePath (cnRelativePath note))
      if pathUrl == unUrl (cnUrl note)
        then do
          putStrLn $ "  🚫 URL not published (404): "
            <> T.unpack (unTitle (cnTitle note)) <> " (" <> T.unpack (unUrl (cnUrl note)) <> ")"
          pure Nothing
        else do
          putStrLn $ "  🔧 Frontmatter URL 404'd (" <> T.unpack (unUrl (cnUrl note))
            <> "), trying file-path URL: " <> T.unpack pathUrl
          isPathLive <- checker pathUrl
          if isPathLive
            then case mkUrl pathUrl of
              Right newUrl -> do
                putStrLn "  ✅ File-path URL is live, updating frontmatter"
                updateFrontmatterUrl (cnFilePath note) pathUrl
                pure (Just note { cnUrl = newUrl })
              Left reason -> do
                putStrLn $ "  ⚠️  Invalid path URL: " <> T.unpack reason
                pure Nothing
            else do
              putStrLn $ "  🚫 Both URLs not published: "
                <> T.unpack (unUrl (cnUrl note)) <> " and " <> T.unpack pathUrl
              pure Nothing

--------------------------------------------------------------------------------
-- Content filtering
--------------------------------------------------------------------------------

isPostableContent :: ContentNote -> Bool
isPostableContent note =
  not (isIndexPage note)
    && not (isUntitledReflection note)
    && not (cnNoSocial note)
    && T.length (T.strip (cnBody note)) >= minPostableBodyLength

isIndexPage :: ContentNote -> Bool
isIndexPage = isIndexPath . unRelativePath . cnRelativePath

isIndexPath :: Text -> Bool
isIndexPath p = takeBaseName (T.unpack p) == "index"

isUntitledReflection :: ContentNote -> Bool
isUntitledReflection note =
  isReflectionPath (unRelativePath (cnRelativePath note)) && looksLikeDateTitle (unTitle (cnTitle note))

isReflectionPath :: Text -> Bool
isReflectionPath = T.isPrefixOf "reflections/"

looksLikeDateTitle :: Text -> Bool
looksLikeDateTitle title =
  let t = T.strip title
  in (t :: Text) =~ ("^[0-9]{4}-[0-9]{2}-[0-9]{2}$" :: String)

isAwaitingImageBackfill :: Text -> Text -> Bool
isAwaitingImageBackfill relativePath body =
  let directoryName = T.pack (takeFileName (takeDirectory (T.unpack relativePath)))
      filename = T.pack (takeFileName (T.unpack relativePath))
  in elem directoryName imageBackfillContentIds
       && shouldHaveImage filename
       && not (hasEmbeddedImage body)

--------------------------------------------------------------------------------
-- Reflection eligibility
--------------------------------------------------------------------------------

isReflectionEligibleForPosting :: UTCTime -> TimeOfDay -> Day -> Bool
isReflectionEligibleForPosting now postingCutoff reflectionDate =
  let today = utctDay now
      yesterday = pred today
      currentTime = timeToTimeOfDay (utctDayTime now)
  in (reflectionDate == yesterday && currentTime >= postingCutoff)
       || reflectionDate < yesterday

--------------------------------------------------------------------------------
-- BFS content discovery
--------------------------------------------------------------------------------

data BfsState = BfsState
  { bsVisited   :: Set Text
  , bsQueue     :: [(Text, [Text])]
  , bsResults   :: [ContentToPost]
  , bsFilled    :: Set Platform
  , bsParentMap :: Map.Map Text Text
  }

bfsContentDiscovery :: FindContentConfig -> IO [ContentToPost]
bfsContentDiscovery config = do
  mStart <- findMostRecentReflection (fccContentDir config)
  case mStart of
    Nothing -> do
      putStrLn "  📭 No reflections found"
      pure []
    Just startPath -> do
      let initialState = BfsState
            { bsVisited   = Set.singleton startPath
            , bsQueue     = [(startPath, [startPath])]
            , bsResults   = []
            , bsFilled    = Set.empty
            , bsParentMap = Map.empty
            }
      bfsLoop config initialState

bfsLoop :: FindContentConfig -> BfsState -> IO [ContentToPost]
bfsLoop config state =
  case bsQueue state of
    [] -> pure (bsResults state)
    _ | Set.fromList (fccPlatforms config) == bsFilled state ->
        pure (bsResults state)
    ((currentPath, pathFromRoot) : rest) -> do
      let state' = state { bsQueue = rest }
      mNote <- readContentNote currentPath (fccContentDir config)
      case mNote of
        Nothing -> bfsLoop config state'
        Just note -> do
          eligible <- checkBfsEligibility (unRelativePath (cnRelativePath note)) (fccPostingCutoff config)
          let awaitingImage = isAwaitingImageBackfill
                (unRelativePath (cnRelativePath note)) (cnBody note)
          mValidated <- case (isPostableContent note && eligible && not awaitingImage, fccPublicationChecker config) of
            (True, Just checker) -> validateNoteUrl checker note
            (True, Nothing)      -> pure (Just note)
            (False, _)           -> pure Nothing
          let neededPlatforms = filter
                (\p -> not (Set.member p (bsFilled state'))
                       && not (Set.member p (cnPostedPlatforms note)))
                (fccPlatforms config)
              newResults = case mValidated of
                Just vNote -> fmap (\p -> ContentToPost p vNote pathFromRoot) neededPlatforms
                Nothing    -> []
              newFilled = Set.union (bsFilled state') $
                Set.fromList (fmap ctpPlatform newResults)
              neighbors = filter (\l -> not (Set.member l (bsVisited state')))
                            (fmap unRelativePath (cnLinkedNotePaths note))
              newVisited = foldl (flip Set.insert) (bsVisited state') neighbors
              newQueue = rest <> fmap (\n -> (n, pathFromRoot <> [n])) neighbors
              state'' = state'
                { bsVisited = newVisited
                , bsQueue   = newQueue
                , bsResults = bsResults state' <> newResults
                , bsFilled  = newFilled
                }
          bfsLoop config state''

checkBfsEligibility :: Text -> TimeOfDay -> IO Bool
checkBfsEligibility relativePath postingCutoff
  | isIndexPath relativePath = pure False
  | isReflectionPath relativePath =
      case parseDateFromPath relativePath of
        Nothing -> pure False
        Just reflectionDate -> do
          now <- getCurrentTime
          pure $ isReflectionEligibleForPosting now postingCutoff reflectionDate
  | otherwise = pure True

--------------------------------------------------------------------------------
-- Discover content to post (main entry point for discovery)
--------------------------------------------------------------------------------

discoverContentToPost :: FindContentConfig -> Bool -> IO [ContentToPost]
discoverContentToPost config isPastPostingHour =
  if isPastPostingHour
    then do
      mRefl <- findMostRecentReflection (fccContentDir config)
      case mRefl of
        Nothing -> bfsContentDiscovery config
        Just reflPath -> do
          now <- getCurrentTime
          let eligible = case parseDateFromPath reflPath of
                Nothing -> False
                Just reflectionDate -> isReflectionEligibleForPosting
                  now (fccPostingCutoff config) reflectionDate
          if eligible
            then do
              mNote <- readContentNote reflPath (fccContentDir config)
              case mNote of
                Just note | isPostableContent note
                          , not (isAwaitingImageBackfill (unRelativePath (cnRelativePath note)) (cnBody note)) -> do
                  mValidated <- case fccPublicationChecker config of
                    Just checker -> validateNoteUrl checker note
                    Nothing      -> pure (Just note)
                  case mValidated of
                    Nothing -> do
                      putStrLn "  🚫 Prior day's reflection not yet published"
                      bfsContentDiscovery config
                    Just vNote -> do
                      let neededPlatforms = filter
                            (\p -> not (Set.member p (cnPostedPlatforms vNote)))
                            (fccPlatforms config)
                      case neededPlatforms of
                        [] -> bfsContentDiscovery config
                        _  -> pure $ fmap (\p -> ContentToPost p vNote [reflPath]) neededPlatforms
                _ -> bfsContentDiscovery config
            else bfsContentDiscovery config
    else bfsContentDiscovery config

--------------------------------------------------------------------------------
-- Date parsing helpers
--------------------------------------------------------------------------------

parseDateFromPath :: Text -> Maybe Day
parseDateFromPath path =
  let base = takeBaseName (T.unpack path)
  in parseTimeM True defaultTimeLocale "%Y-%m-%d" base
