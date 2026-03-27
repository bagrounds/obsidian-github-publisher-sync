module Automation.SocialPosting
  ( Platform (..)
  , ContentNote (..)
  , ContentToPost (..)
  , FindContentConfig (..)
  , autoPost
  , discoverContentToPost
  , bfsContentDiscovery
  , readContentNote
  , extractMarkdownLinks
  , detectPostedPlatforms
  , isPostableContent
  , isUntitledReflection
  , findMostRecentReflection
  , isReflectionEligibleForPosting
  , updateFrontmatterTimestamp
  , updatePathTimestamps
  , reconstructPath
  , runPostingPipeline
  ) where

import Control.Concurrent.Async (mapConcurrently)
import Control.Exception (SomeException, try)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.List (sortBy)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Data.Time
  ( UTCTime (..)
  , defaultTimeLocale
  , formatTime
  , getCurrentTime
  , utctDayTime
  )
import Network.HTTP.Client (Manager)
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory)
import System.Environment (lookupEnv)
import System.FilePath (takeBaseName, takeDirectory, (</>))
import Text.Regex.TDFA ((=~))

import Automation.DailyUpdates (UpdateLink (..), addUpdateLinksToReflection)
import Automation.EmbedSection
  ( buildBlueskySection
  , buildMastodonSection
  , buildTweetSection
  )
import Automation.Env (validateEnvironment)
import Automation.Frontmatter (parseFrontmatter)
import Automation.Gemini
  ( GenerationConfig (..)
  , GeminiResponse (..)
  , defaultGenerationConfig
  , generateContentWithFallback
  )
import qualified Automation.ObsidianSync as Sync
import Automation.Platforms.Bluesky (postToBluesky, getBlueskyEmbedHtml, extractBlueskyDid, extractBlueskyPostId, buildBlueskyPostUrl)
import Automation.Platforms.Mastodon (postToMastodon, getMastodonEmbedHtml, extractMastodonInstanceUrl, extractMastodonStatusId, extractMastodonUsername)
import Automation.Platforms.OgMetadata (fetchOgMetadata)
import Automation.Platforms.Twitter (postTweet, getEmbedHtml)
import Automation.Prompts (PromptPair (..), assemblePost, buildTagsPrompt)
import Automation.Text (fitPostToLimit)
import Automation.Types

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

data Platform = Twitter | Bluesky | Mastodon
  deriving (Show, Eq, Ord)

data ContentNote = ContentNote
  { cnFilePath       :: FilePath
  , cnRelativePath   :: Text
  , cnTitle          :: Text
  , cnUrl            :: Text
  , cnBody           :: Text
  , cnPostedPlatforms :: Set Platform
  , cnLinkedNotePaths :: [Text]
  , cnNoSocial       :: Bool
  } deriving (Show, Eq)

data ContentToPost = ContentToPost
  { ctpPlatform     :: Platform
  , ctpNote         :: ContentNote
  , ctpPathFromRoot :: [Text]
  } deriving (Show, Eq)

data FindContentConfig = FindContentConfig
  { fccContentDir     :: FilePath
  , fccPlatforms      :: [Platform]
  , fccPostingHourUTC :: Int
  } deriving (Show, Eq)

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

defaultPostingHourUTC :: Int
defaultPostingHourUTC = 17

minPostableBodyLength :: Int
minPostableBodyLength = 50

--------------------------------------------------------------------------------
-- Platform detection
--------------------------------------------------------------------------------

detectPostedPlatforms :: Text -> Set Platform
detectPostedPlatforms content =
  Set.fromList $ mapMaybe checkHeader
    [ (tweetSectionHeader, Twitter)
    , (blueskySectionHeader, Bluesky)
    , (mastodonSectionHeader, Mastodon)
    ]
  where
    checkHeader (header, platform)
      | T.isInfixOf header content = Just platform
      | otherwise = Nothing

platformSectionHeader :: Platform -> Text
platformSectionHeader Twitter  = tweetSectionHeader
platformSectionHeader Bluesky  = blueskySectionHeader
platformSectionHeader Mastodon = mastodonSectionHeader

platformMaxLength :: Platform -> Int
platformMaxLength Twitter  = twitterMaxLength
platformMaxLength Bluesky  = blueskyMaxLength
platformMaxLength Mastodon = mastodonMaxLength

--------------------------------------------------------------------------------
-- Link extraction
--------------------------------------------------------------------------------

extractMarkdownLinks :: Text -> Text -> FilePath -> [Text]
extractMarkdownLinks body noteRelativePath contentDir =
  let noteDir = takeDirectory (contentDir </> T.unpack noteRelativePath)
      seen    = Set.empty :: Set Text
  in snd $ foldl collectLink (seen, [])
       (mdLinks body noteDir contentDir <> wikiLinksFromBody body noteDir contentDir)

collectLink :: (Set Text, [Text]) -> Text -> (Set Text, [Text])
collectLink (seen, acc) rel
  | T.isPrefixOf ".." rel = (seen, acc)
  | Set.member rel seen   = (seen, acc)
  | otherwise             = (Set.insert rel seen, acc <> [rel])

mdLinks :: Text -> FilePath -> FilePath -> [Text]
mdLinks body noteDir contentDir = go (T.unpack body)
  where
    go :: String -> [Text]
    go s = case (s =~ ("\\]\\(([^)]+\\.md)\\)" :: String) :: (String, String, String, [String])) of
      (_, _, after, [target])
        | not (isPrefixOfS "http://" target) && not (isPrefixOfS "https://" target) ->
            let absTarget  = normalizeFilePath (noteDir </> target)
                relPath    = makeRelativeTo contentDir absTarget
            in T.pack relPath : go after
        | otherwise -> go after
      _ -> []

wikiLinksFromBody :: Text -> FilePath -> FilePath -> [Text]
wikiLinksFromBody body noteDir contentDir = go (T.unpack body)
  where
    go :: String -> [Text]
    go s = case (s =~ ("\\[\\[([^\\]|#]+)" :: String) :: (String, String, String, [String])) of
      (_, _, after, [target]) ->
        let trimmed = stripS target
            withMd  = if hasSuffix ".md" trimmed then trimmed else trimmed <> ".md"
            rel
              | '/' `elem` withMd = T.pack withMd
              | otherwise         =
                  let absTarget = normalizeFilePath (noteDir </> withMd)
                  in T.pack (makeRelativeTo contentDir absTarget)
        in rel : go after
      _ -> []

isPrefixOfS :: String -> String -> Bool
isPrefixOfS [] _          = True
isPrefixOfS _ []          = False
isPrefixOfS (x:xs) (y:ys) = x == y && isPrefixOfS xs ys

hasSuffix :: String -> String -> Bool
hasSuffix sfx s = reverse sfx `isPrefixOfS` reverse s

stripS :: String -> String
stripS = reverse . dropWhile (== ' ') . reverse . dropWhile (== ' ')

normalizeFilePath :: FilePath -> FilePath
normalizeFilePath = joinSlash . resolve . splitSlash
  where
    resolve :: [String] -> [String]
    resolve = foldl step []

    step :: [String] -> String -> [String]
    step acc "."      = acc
    step (_:rest) ".." = rest
    step acc seg       = seg : acc

makeRelativeTo :: FilePath -> FilePath -> FilePath
makeRelativeTo base target =
  let baseParts   = splitSlash base
      targetParts = splitSlash target
      common      = length $ takeWhile id $ zipWith (==) baseParts targetParts
      remaining   = drop common targetParts
  in joinSlash remaining

splitSlash :: FilePath -> [String]
splitSlash = fmap T.unpack . filter (not . T.null) . T.splitOn "/" . T.pack

joinSlash :: [String] -> FilePath
joinSlash []     = ""
joinSlash [x]    = x
joinSlash (x:xs) = x </> joinSlash xs

--------------------------------------------------------------------------------
-- Reading content notes
--------------------------------------------------------------------------------

readContentNote :: Text -> FilePath -> IO (Maybe ContentNote)
readContentNote relativePath contentDir = do
  let filePath = contentDir </> T.unpack relativePath
  exists <- doesFileExist filePath
  case exists of
    False -> pure Nothing
    True  -> do
      content <- TIO.readFile filePath
      let (fm, body) = parseFrontmatter content
          postedPlatforms = detectPostedPlatforms content
          linkedPaths = extractMarkdownLinks body relativePath contentDir
          noSocial = Map.lookup "no_social" fm == Just "true"
          title = fromMaybe (T.pack $ takeBaseName $ T.unpack relativePath) (Map.lookup "title" fm)
          slug = fromMaybe relativePath (T.stripSuffix ".md" relativePath)
          url = fromMaybe ("https://bagrounds.org/" <> slug) (Map.lookup "URL" fm)
      pure $ Just ContentNote
        { cnFilePath = filePath
        , cnRelativePath = relativePath
        , cnTitle = title
        , cnUrl = url
        , cnBody = body
        , cnPostedPlatforms = postedPlatforms
        , cnLinkedNotePaths = linkedPaths
        , cnNoSocial = noSocial
        }

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
isIndexPage note =
  takeBaseName (T.unpack (cnRelativePath note)) == "index"

isUntitledReflection :: ContentNote -> Bool
isUntitledReflection note =
  isReflectionPath (cnRelativePath note) && looksLikeDateTitle (cnTitle note)

isReflectionPath :: Text -> Bool
isReflectionPath p = T.isPrefixOf "reflections/" p

looksLikeDateTitle :: Text -> Bool
looksLikeDateTitle title =
  let t = T.strip title
  in (t :: Text) =~ ("^[0-9]{4}-[0-9]{2}-[0-9]{2}$" :: String)

--------------------------------------------------------------------------------
-- Finding most recent reflection
--------------------------------------------------------------------------------

findMostRecentReflection :: FilePath -> IO (Maybe Text)
findMostRecentReflection contentDir = do
  let reflDir = contentDir </> "reflections"
  exists <- doesDirectoryExist reflDir
  case exists of
    False -> pure Nothing
    True  -> do
      files <- listDirectory reflDir
      let datePattern = "^[0-9]{4}-[0-9]{2}-[0-9]{2}\\.md$" :: String
          dateFiles   = filter (\f -> (f :: String) =~ datePattern) files
          sorted      = sortBy (flip compare) dateFiles
      pure $ case sorted of
        (f : _) -> Just ("reflections/" <> T.pack f)
        []      -> Nothing

--------------------------------------------------------------------------------
-- Reflection eligibility
--------------------------------------------------------------------------------

isReflectionEligibleForPosting :: Text -> Int -> IO Bool
isReflectionEligibleForPosting dateStr postingHourUTC = do
  now <- getCurrentTime
  let currentHour = floor (utctDayTime now / 3600) :: Int
      todayStr = T.pack $ formatTime defaultTimeLocale "%Y-%m-%d" now
      yesterdayStr = T.pack $ formatTime defaultTimeLocale "%Y-%m-%d" $
        now { utctDay = pred (utctDay now) }
  pure $
    (dateStr == yesterdayStr && currentHour >= postingHourUTC)
      || (dateStr < yesterdayStr)
      || (dateStr == todayStr && False)

--------------------------------------------------------------------------------
-- BFS content discovery
--------------------------------------------------------------------------------

data BfsState = BfsState
  { bsVisited   :: Set Text
  , bsQueue     :: [(Text, [Text])]
  , bsResults   :: [ContentToPost]
  , bsFilled    :: Set Platform
  , bsParentMap :: Map Text Text
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
          let neededPlatforms = filter
                (\p -> not (Set.member p (bsFilled state'))
                       && not (Set.member p (cnPostedPlatforms note)))
                (fccPlatforms config)
              newResults
                | isPostableContent note =
                    fmap (\p -> ContentToPost p note pathFromRoot) neededPlatforms
                | otherwise = []
              newFilled = Set.union (bsFilled state') $
                Set.fromList (fmap ctpPlatform newResults)
              neighbors = filter (\l -> not (Set.member l (bsVisited state')))
                            (cnLinkedNotePaths note)
              newVisited = foldl (flip Set.insert) (bsVisited state') neighbors
              newQueue = rest <> fmap (\n -> (n, pathFromRoot <> [n])) neighbors
              state'' = state'
                { bsVisited = newVisited
                , bsQueue   = newQueue
                , bsResults = bsResults state' <> newResults
                , bsFilled  = newFilled
                }
          bfsLoop config state''

--------------------------------------------------------------------------------
-- Discover content to post (main entry point for discovery)
--------------------------------------------------------------------------------

discoverContentToPost :: FindContentConfig -> Bool -> IO [ContentToPost]
discoverContentToPost config isPastPostingHour = do
  case isPastPostingHour of
    True -> do
      mRefl <- findMostRecentReflection (fccContentDir config)
      case mRefl of
        Nothing -> bfsContentDiscovery config
        Just reflPath -> do
          eligible <- isReflectionEligibleForPosting
            (extractDateFromPath reflPath) (fccPostingHourUTC config)
          case eligible of
            True -> do
              mNote <- readContentNote reflPath (fccContentDir config)
              case mNote of
                Just note | isPostableContent note -> do
                  let neededPlatforms = filter
                        (\p -> not (Set.member p (cnPostedPlatforms note)))
                        (fccPlatforms config)
                  case neededPlatforms of
                    [] -> bfsContentDiscovery config
                    _  -> pure $ fmap (\p -> ContentToPost p note [reflPath]) neededPlatforms
                _ -> bfsContentDiscovery config
            False -> bfsContentDiscovery config
    False -> bfsContentDiscovery config

extractDateFromPath :: Text -> Text
extractDateFromPath path =
  let base = T.pack $ takeBaseName $ T.unpack path
  in base

--------------------------------------------------------------------------------
-- Path reconstruction and timestamp updates
--------------------------------------------------------------------------------

reconstructPath :: Map Text Text -> Text -> Text -> [Text]
reconstructPath parentMap start target = reverse $ go target
  where
    go current
      | current == start = [current]
      | otherwise = case Map.lookup current parentMap of
          Just parent -> current : go parent
          Nothing     -> [current]

updateFrontmatterTimestamp :: FilePath -> IO ()
updateFrontmatterTimestamp filePath = do
  exists <- doesFileExist filePath
  case exists of
    False -> pure ()
    True  -> do
      content <- TIO.readFile filePath
      now <- getCurrentTime
      let timestamp = T.pack $ formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%S" now
          (fm, body) = parseFrontmatter content
          fm' = Map.insert "updated" timestamp fm
          newContent = renderFrontmatter fm' <> body
      TIO.writeFile filePath newContent

updatePathTimestamps :: FilePath -> [Text] -> IO ()
updatePathTimestamps contentDir paths =
  mapM_ (\p -> updateFrontmatterTimestamp (contentDir </> T.unpack p)) paths

renderFrontmatter :: Map Text Text -> Text
renderFrontmatter fm =
  let lines' = fmap (\(k, v) -> k <> ": " <> v) (Map.toAscList fm)
  in "---\n" <> T.intercalate "\n" lines' <> "\n---\n"

--------------------------------------------------------------------------------
-- Configured platforms from environment
--------------------------------------------------------------------------------

getConfiguredPlatforms :: EnvironmentConfig -> [Platform]
getConfiguredPlatforms ec = mapMaybe id
  [ case ecTwitter ec of { Just _ -> Just Twitter; Nothing -> Nothing }
  , case ecBluesky ec of { Just _ -> Just Bluesky; Nothing -> Nothing }
  , case ecMastodon ec of { Just _ -> Just Mastodon; Nothing -> Nothing }
  ]

--------------------------------------------------------------------------------
-- Social post generation via Gemini
--------------------------------------------------------------------------------

generateSocialPostText :: Manager -> Text -> ContentNote -> Platform -> IO (Either Text Text)
generateSocialPostText manager apiKey note platform = do
  let rd = ReflectionData
        { rdDate = extractDateFromPath (cnRelativePath note)
        , rdTitle = cnTitle note
        , rdUrl = cnUrl note
        , rdBody = cnBody note
        , rdFilePath = T.pack (cnFilePath note)
        , rdHasTweetSection = Set.member Twitter (cnPostedPlatforms note)
        , rdHasBlueskySection = Set.member Bluesky (cnPostedPlatforms note)
        , rdHasMastodonSection = Set.member Mastodon (cnPostedPlatforms note)
        }
      tagPrompt = buildTagsPrompt rd
      combinedPrompt = ppSystem tagPrompt <> "\n\n" <> ppUser tagPrompt
      maxLen = platformMaxLength platform
      config = defaultGenerationConfig { gcTemperature = 0.8, gcMaxOutputTokens = 512 }
      models = [defaultGeminiModel, gemini3Flash, geminiFlashFallback]
  result <- generateContentWithFallback manager models combinedPrompt apiKey config
  case result of
    Left err -> pure (Left err)
    Right resp -> do
      let rawPost = assemblePost (grText resp) rd
          fitted = fitPostToLimit rawPost maxLen
      pure (Right fitted)

--------------------------------------------------------------------------------
-- Platform posting tasks
--------------------------------------------------------------------------------

data PostResult = PostResult
  { prPlatform :: Platform
  , prEmbedHtml :: Text
  , prSectionBuilder :: Text -> Text -> Text
  }

postToPlatform :: Manager -> EnvironmentConfig -> ContentNote -> Text -> Platform
               -> IO (Either Text PostResult)
postToPlatform manager env note postText platform =
  case platform of
    Twitter -> postToTwitterPlatform manager env note postText
    Bluesky -> postToBlueskyPlatform manager env note postText
    Mastodon -> postToMastodonPlatform manager env note postText

postToTwitterPlatform :: Manager -> EnvironmentConfig -> ContentNote -> Text
                      -> IO (Either Text PostResult)
postToTwitterPlatform manager env _note postText =
  case ecTwitter env of
    Nothing -> pure (Left "Twitter not configured")
    Just creds -> do
      result <- postTweet manager creds postText
      case result of
        Left err -> pure (Left $ "Twitter post failed: " <> err)
        Right (tweetId, _tweetText) -> do
          embedHtml <- getEmbedHtml manager tweetId (tcAccessToken creds)
                         (tcApiKey creds) (tcApiSecret creds)
          pure $ Right PostResult
            { prPlatform = Twitter
            , prEmbedHtml = embedHtml
            , prSectionBuilder = buildTweetSection
            }

postToBlueskyPlatform :: Manager -> EnvironmentConfig -> ContentNote -> Text
                      -> IO (Either Text PostResult)
postToBlueskyPlatform manager env note postText =
  case ecBluesky env of
    Nothing -> pure (Left "Bluesky not configured")
    Just creds -> do
      ogMeta <- fetchOgMetadata (cnUrl note)
      let linkCard = LinkCard
            { lcUri = cnUrl note
            , lcTitle = fromMaybe (cnTitle note) (ogTitle ogMeta)
            , lcDescription = fromMaybe "" (ogDescription ogMeta)
            , lcThumbUrl = ogImageUrl ogMeta
            }
      result <- postToBluesky manager creds postText (Just linkCard)
      case result of
        Left err -> pure (Left $ "Bluesky post failed: " <> err)
        Right bpr -> do
          let mDid = extractBlueskyDid (bprUri bpr)
              mPostId = extractBlueskyPostId (bprUri bpr)
          case (mDid, mPostId) of
            (Just did, Just postId) -> do
              let postUrl = buildBlueskyPostUrl (bcIdentifier creds) postId
              embedHtml <- getBlueskyEmbedHtml manager postUrl did
                             (bcIdentifier creds) postId Nothing
              pure $ Right PostResult
                { prPlatform = Bluesky
                , prEmbedHtml = embedHtml
                , prSectionBuilder = buildBlueskySection
                }
            _ -> pure $ Left "Could not extract Bluesky post ID from URI"

postToMastodonPlatform :: Manager -> EnvironmentConfig -> ContentNote -> Text
                       -> IO (Either Text PostResult)
postToMastodonPlatform manager env _note postText =
  case ecMastodon env of
    Nothing -> pure (Left "Mastodon not configured")
    Just creds -> do
      result <- postToMastodon manager creds postText
      case result of
        Left err -> pure (Left $ "Mastodon post failed: " <> err)
        Right mpr -> do
          let postUrl = mprUrl mpr
              mInstance = extractMastodonInstanceUrl postUrl
              mStatusId = extractMastodonStatusId postUrl
              mUsername = extractMastodonUsername postUrl
          case (mInstance, mStatusId, mUsername) of
            (Just instanceUrl, Just statusId, Just _username) -> do
              embedHtml <- getMastodonEmbedHtml manager postUrl instanceUrl statusId
              pure $ Right PostResult
                { prPlatform = Mastodon
                , prEmbedHtml = embedHtml
                , prSectionBuilder = buildMastodonSection
                }
            _ -> pure $ Left "Could not extract Mastodon post details from URL"

--------------------------------------------------------------------------------
-- Posting pipeline
--------------------------------------------------------------------------------

runPostingPipeline :: Manager -> EnvironmentConfig -> Text -> FilePath -> IO ()
runPostingPipeline manager env apiKey vaultDir = do
  let platforms = getConfiguredPlatforms env
  putStrLn $ "  🔍 Configured platforms: " <> show platforms

  now <- getCurrentTime
  let currentHour = floor (utctDayTime now / 3600) :: Int
      config = FindContentConfig
        { fccContentDir = vaultDir
        , fccPlatforms = platforms
        , fccPostingHourUTC = defaultPostingHourUTC
        }
      isPastHour = currentHour >= defaultPostingHourUTC

  contentItems <- discoverContentToPost config isPastHour
  case contentItems of
    [] -> putStrLn "  📭 No content to post"
    items -> do
      putStrLn $ "  📋 Found " <> show (length items) <> " items to post"
      let grouped = groupByNote items
      mapM_ (processNoteGroup manager env apiKey vaultDir) grouped

groupByNote :: [ContentToPost] -> [([Platform], ContentNote, [Text])]
groupByNote items =
  let noteMap = foldl addToGroup Map.empty items
  in Map.elems noteMap
  where
    addToGroup acc ctp =
      let key = cnRelativePath (ctpNote ctp)
      in Map.insertWith merge key
           ([ctpPlatform ctp], ctpNote ctp, ctpPathFromRoot ctp) acc
    merge (p1, n, path) (p2, _, _) = (p1 <> p2, n, path)

processNoteGroup :: Manager -> EnvironmentConfig -> Text -> FilePath
                 -> ([Platform], ContentNote, [Text]) -> IO ()
processNoteGroup manager env apiKey vaultDir (platforms, note, pathFromRoot) = do
  putStrLn $ "  📝 Processing: " <> T.unpack (cnTitle note)
  putStrLn $ "     Platforms: " <> show platforms

  updatePathTimestamps vaultDir pathFromRoot

  results <- mapConcurrently (postForPlatform manager env apiKey note) platforms

  let successes = mapMaybe eitherToMaybe results
      embedSections = fmap
        (\pr -> (platformSectionHeader (prPlatform pr), prEmbedHtml pr, prSectionBuilder pr))
        successes

  case embedSections of
    [] -> putStrLn "  ⚠️  No successful posts"
    _  -> do
      Sync.appendEmbedsToObsidianNote
        (cnFilePath note) embedSections (toSyncCreds env)
      putStrLn $ "  ✅ " <> show (length successes) <> " embeds written"

postForPlatform :: Manager -> EnvironmentConfig -> Text -> ContentNote -> Platform
                -> IO (Either Text PostResult)
postForPlatform manager env apiKey note platform = do
  postTextResult <- generateSocialPostText manager apiKey note platform
  case postTextResult of
    Left err -> do
      putStrLn $ "  ❌ " <> show platform <> " text generation failed: " <> T.unpack err
      pure (Left err)
    Right postText -> do
      putStrLn $ "  📤 Posting to " <> show platform <> "..."
      result <- try (postToPlatform manager env note postText platform)
        :: IO (Either SomeException (Either Text PostResult))
      case result of
        Left exc -> do
          let errMsg = "Exception posting to " <> T.pack (show platform) <> ": " <> T.pack (show exc)
          putStrLn $ "  ❌ " <> T.unpack errMsg
          pure (Left errMsg)
        Right (Left err) -> do
          putStrLn $ "  ❌ " <> show platform <> ": " <> T.unpack err
          pure (Left err)
        Right (Right pr) -> do
          putStrLn $ "  ✅ " <> show platform <> " posted successfully"
          pure (Right pr)

eitherToMaybe :: Either a b -> Maybe b
eitherToMaybe (Right b) = Just b
eitherToMaybe (Left _)  = Nothing

toSyncCreds :: EnvironmentConfig -> Sync.ObsidianCredentials
toSyncCreds env =
  let oc = ecObsidian env
  in Sync.ObsidianCredentials
    { Sync.ocAuthToken = ocAuthToken oc
    , Sync.ocVaultName = ocVaultName oc
    , Sync.ocVaultPassword = ocVaultPassword oc
    }

--------------------------------------------------------------------------------
-- Main orchestrator
--------------------------------------------------------------------------------

autoPost :: Manager -> IO ()
autoPost manager = do
  env <- validateEnvironment
  let apiKey = gcApiKey (ecGemini env)
      creds = toSyncCreds env

  putStrLn "  🔄 Pulling vault..."
  vaultDir <- Sync.syncObsidianVault creds Nothing

  runPostingPipeline manager env apiKey vaultDir

  let reflectionsDir = vaultDir </> "reflections"
  now <- getCurrentTime
  let todayStr = T.pack $ formatTime defaultTimeLocale "%Y-%m-%d" now
  _ <- addUpdateLinksToReflection reflectionsDir todayStr
         [ UpdateLink "social-posting" "Social posts published" ]

  Sync.pushObsidianVault vaultDir (Sync.ocAuthToken creds)
  putStrLn "  📤 Vault pushed"
