module Automation.SocialPosting
  ( Platform (..)
  , ContentNote (..)
  , ContentToPost (..)
  , PostedNote (..)
  , FindContentConfig (..)
  , autoPost
  , discoverContentToPost
  , bfsContentDiscovery
  , readContentNote
  , extractMarkdownLinks
  , detectPostedPlatforms
  , isPostableContent
  , isUntitledReflection
  , isIndexPath
  , findMostRecentReflection
  , isReflectionEligibleForPosting
  , checkBfsEligibility
  , parseWikiLinks
  , normalizeFilePath
  , updateFrontmatterTimestamp
  , updatePathTimestamps
  , reconstructPath
  , runPostingPipeline
  , checkUrlPublished
  , urlFromFilePath
  , validateNoteUrl
  , updateFrontmatterUrl
  ) where

import Control.Concurrent.Async (mapConcurrently)
import Control.Exception (SomeException, try)

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Data.Time
  ( Day
  , UTCTime (..)
  , defaultTimeLocale
  , formatTime
  , getCurrentTime
  , parseTimeM
  , utctDayTime
  )
import Data.Time.LocalTime (TimeOfDay (..), timeToTimeOfDay)
import qualified Network.HTTP.Client as HTTP
import Network.HTTP.Client (Manager)
import qualified Network.HTTP.Client.TLS as TLS
import Network.HTTP.Types.Status (statusIsSuccessful)
import System.Directory (doesFileExist)

import System.FilePath (takeBaseName, takeDirectory, (</>))
import Text.Regex.TDFA ((=~))

import Automation.DailyUpdates (UpdateLink (..), addUpdateLinksToReflection)
import Automation.EmbedSection
  ( buildBlueskySection
  , buildMastodonSection
  , buildTweetSection
  )
import Automation.Env (validateEnvironment)
import Automation.Frontmatter (parseFrontmatter, quoteYamlValue)
import Automation.BlogPrompt (DateStr (..), todayPacific)
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
import Automation.Prompts (PromptPair (..), assemblePost, buildQuestionPrompt, buildShortenQuestionPrompt, buildTagsPrompt)
import Automation.Reflection (findMostRecentReflection)
import Automation.Text (fitPostToLimit)
import Automation.Types

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

data Platform = Twitter | Bluesky | Mastodon
  deriving (Show, Eq, Ord)

platformDetail :: Platform -> Text
platformDetail Twitter  = "🐦 posted to Twitter"
platformDetail Bluesky  = "🦋 posted to BlueSky"
platformDetail Mastodon = "🐘 posted to Mastodon"

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
wikiLinksFromBody body noteDir contentDir =
  let targets = parseWikiLinks (T.unpack body)
  in fmap (resolveWikiLinkTarget noteDir contentDir) targets

resolveWikiLinkTarget :: FilePath -> FilePath -> String -> Text
resolveWikiLinkTarget noteDir contentDir target =
  let trimmed = stripS target
      withMd  = if hasSuffix ".md" trimmed then trimmed else trimmed <> ".md"
  in case '/' `elem` withMd of
    True  -> T.pack withMd
    False ->
      let absTarget = normalizeFilePath (noteDir </> withMd)
      in T.pack (makeRelativeTo contentDir absTarget)

parseWikiLinks :: String -> [String]
parseWikiLinks [] = []
parseWikiLinks ('[':'[':rest) =
  case extractWikiLinkTarget rest of
    Just (target, remaining) -> target : parseWikiLinks remaining
    Nothing -> parseWikiLinks rest
parseWikiLinks (_:rest) = parseWikiLinks rest

extractWikiLinkTarget :: String -> Maybe (String, String)
extractWikiLinkTarget input =
  let (target, after) = span (\c -> c /= ']' && c /= '#' && c /= '|') input
  in case after of
    (']':']':rest) | not (null target) -> Just (target, rest)
    ('#':rest) -> skipToClose target rest
    ('|':rest) -> skipToClose target rest
    _ -> Nothing
  where
    skipToClose _ [] = Nothing
    skipToClose t (']':']':rest) | not (null t) = Just (t, rest)
    skipToClose t (_:rest) = skipToClose t rest

isPrefixOfS :: String -> String -> Bool
isPrefixOfS [] _          = True
isPrefixOfS _ []          = False
isPrefixOfS (x:xs) (y:ys) = x == y && isPrefixOfS xs ys

hasSuffix :: String -> String -> Bool
hasSuffix sfx s = reverse sfx `isPrefixOfS` reverse s

stripS :: String -> String
stripS = reverse . dropWhile (== ' ') . reverse . dropWhile (== ' ')

normalizeFilePath :: FilePath -> FilePath
normalizeFilePath = joinSlash . reverse . resolve . splitSlash
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
-- URL validation and auto-fix
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
  isLive <- checker (cnUrl note)
  case isLive of
    True -> pure (Just note)
    False -> do
      let pathUrl = urlFromFilePath (cnRelativePath note)
      case pathUrl == cnUrl note of
        True -> do
          putStrLn $ "  🚫 URL not published (404): "
            <> T.unpack (cnTitle note) <> " (" <> T.unpack (cnUrl note) <> ")"
          pure Nothing
        False -> do
          putStrLn $ "  🔧 Frontmatter URL 404'd (" <> T.unpack (cnUrl note)
            <> "), trying file-path URL: " <> T.unpack pathUrl
          isPathLive <- checker pathUrl
          case isPathLive of
            True -> do
              putStrLn $ "  ✅ File-path URL is live, updating frontmatter"
              updateFrontmatterUrl (cnFilePath note) pathUrl
              pure (Just note { cnUrl = pathUrl })
            False -> do
              putStrLn $ "  🚫 Both URLs not published: "
                <> T.unpack (cnUrl note) <> " and " <> T.unpack pathUrl
              pure Nothing

updateFrontmatterUrl :: FilePath -> Text -> IO ()
updateFrontmatterUrl filePath newUrl = do
  exists <- doesFileExist filePath
  case exists of
    False -> pure ()
    True  -> do
      content <- TIO.readFile filePath
      let ls = T.splitOn "\n" content
      case ls of
        (first : rest)
          | T.strip first == "---" ->
              case break (\l -> T.strip l == "---") rest of
                (_, []) -> pure ()
                (fmLines, closingDash : bodyLines) ->
                  let updatedFm = upsertFmField fmLines "URL" (quoteYamlValue newUrl)
                  in TIO.writeFile filePath
                       (T.intercalate "\n" (first : updatedFm <> [closingDash] <> bodyLines))
        _ -> pure ()

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
isIndexPage = isIndexPath . cnRelativePath

isIndexPath :: Text -> Bool
isIndexPath p = takeBaseName (T.unpack p) == "index"

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
-- Reflection eligibility
--------------------------------------------------------------------------------

-- | Pure eligibility check: given the current time, determine whether
-- a reflection with the given date is eligible for social posting.
-- A reflection is eligible when it is from yesterday (and the posting
-- cutoff has passed) or from any day before yesterday.
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
          eligible <- checkBfsEligibility (cnRelativePath note) (fccPostingCutoff config)
          mValidated <- case (isPostableContent note && eligible, fccPublicationChecker config) of
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

-- | Check if a note is eligible for BFS posting.
-- Non-reflections are always eligible. Reflections have timing constraints.
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
discoverContentToPost config isPastPostingHour = do
  case isPastPostingHour of
    True -> do
      mRefl <- findMostRecentReflection (fccContentDir config)
      case mRefl of
        Nothing -> bfsContentDiscovery config
        Just reflPath -> do
          now <- getCurrentTime
          let eligible = case parseDateFromPath reflPath of
                Nothing -> False
                Just reflectionDate -> isReflectionEligibleForPosting
                  now (fccPostingCutoff config) reflectionDate
          case eligible of
            True -> do
              mNote <- readContentNote reflPath (fccContentDir config)
              case mNote of
                Just note | isPostableContent note -> do
                  mValidated <- case fccPublicationChecker config of
                    Just checker -> validateNoteUrl checker note
                    Nothing      -> pure (Just note)
                  case mValidated of
                    Nothing -> do
                      putStrLn $ "  🚫 Prior day's reflection not yet published"
                      bfsContentDiscovery config
                    Just vNote -> do
                      let neededPlatforms = filter
                            (\p -> not (Set.member p (cnPostedPlatforms vNote)))
                            (fccPlatforms config)
                      case neededPlatforms of
                        [] -> bfsContentDiscovery config
                        _  -> pure $ fmap (\p -> ContentToPost p vNote [reflPath]) neededPlatforms
                _ -> bfsContentDiscovery config
            False -> bfsContentDiscovery config
    False -> bfsContentDiscovery config

extractDateFromPath :: Text -> Text
extractDateFromPath path =
  let base = T.pack $ takeBaseName $ T.unpack path
  in base

parseDateFromPath :: Text -> Maybe Day
parseDateFromPath path =
  let base = takeBaseName (T.unpack path)
  in parseTimeM True defaultTimeLocale "%Y-%m-%d" base

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
          ls = T.splitOn "\n" content
      case ls of
        (first : rest)
          | T.strip first == "---" ->
              case break (\l -> T.strip l == "---") rest of
                (_, []) -> pure ()
                (fmLines, closingDash : bodyLines) ->
                  let updatedFm = upsertFmField fmLines "updated" (quoteYamlValue timestamp)
                  in TIO.writeFile filePath
                       (T.intercalate "\n" (first : updatedFm <> [closingDash] <> bodyLines))
        _ -> pure ()

upsertFmField :: [Text] -> Text -> Text -> [Text]
upsertFmField ls key renderedVal =
  let newLine = key <> ": " <> renderedVal
      pat = key <> ":"
      has = any (\l -> T.isPrefixOf pat (T.stripStart l)) ls
      replaced = fmap (\l -> if T.isPrefixOf pat (T.stripStart l) then newLine else l) ls
  in if has then replaced else ls <> [newLine]

updatePathTimestamps :: FilePath -> [Text] -> IO ()
updatePathTimestamps contentDir paths =
  mapM_ (\p -> updateFrontmatterTimestamp (contentDir </> T.unpack p)) paths

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
      tagsPrompt = buildTagsPrompt rd
      questionPrompt = buildQuestionPrompt rd
      tagsCombined = ppSystem tagsPrompt <> "\n\n" <> ppUser tagsPrompt
      questionCombined = ppSystem questionPrompt <> "\n\n" <> ppUser questionPrompt
      maxLen = platformMaxLength platform
      genConfig = defaultGenerationConfig { gcTemperature = 0.8, gcMaxOutputTokens = 512 }
      tagsModels = [defaultGeminiModel, gemini3Flash, geminiFlashFallback]
      questionModels = [defaultQuestionModel, geminiFlashFallback]

  tagsResult <- generateContentWithFallback manager tagsModels tagsCombined apiKey genConfig
  questionResult <- generateContentWithFallback manager questionModels questionCombined apiKey genConfig

  case (tagsResult, questionResult) of
    (Left err, _) -> pure (Left $ "Tags generation failed: " <> err)
    (_, Left err) -> pure (Left $ "Question generation failed: " <> err)
    (Right tagsResp, Right questionResp) -> do
      let tags = T.strip (grText tagsResp)
          question = T.strip (grText questionResp)
          modelOutput = question <> "\n" <> tags
          rawPost = assemblePost modelOutput rd
          overage = T.length rawPost - blueskyMaxLength
      finalPost <- case overage > 0 of
        True -> do
          let shortenSafetyBuffer = 10
              shortenPrompt = buildShortenQuestionPrompt question (overage + shortenSafetyBuffer)
              shortenCombined = ppSystem shortenPrompt <> "\n\n" <> ppUser shortenPrompt
          putStrLn $ "  ✂️ Post exceeds Bluesky limit by " <> show overage <> " chars — asking LLM to shorten question..."
          shortenResult <- generateContentWithFallback manager questionModels shortenCombined apiKey genConfig
          case shortenResult of
            Right shortenResp -> do
              let shortenedQ = T.strip (grText shortenResp)
                  shortenedOutput = shortenedQ <> "\n" <> tags
              pure $ assemblePost shortenedOutput rd
            Left _ -> pure rawPost
        False -> pure rawPost
      pure (Right (fitPostToLimit finalPost maxLen))

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

data PostedNote = PostedNote
  { pnNote      :: ContentNote
  , pnPlatforms :: [Platform]
  } deriving (Show, Eq)

runPostingPipeline :: Manager -> EnvironmentConfig -> Text -> FilePath -> IO [PostedNote]
runPostingPipeline manager env apiKey vaultDir = do
  let platforms = getConfiguredPlatforms env
  putStrLn $ "  🔍 Configured platforms: " <> show platforms

  now <- getCurrentTime
  tlsManager <- TLS.newTlsManager
  let currentTime = timeToTimeOfDay (utctDayTime now)
      config = FindContentConfig
        { fccContentDir = vaultDir
        , fccPlatforms = platforms
        , fccPostingCutoff = defaultPostingCutoff
        , fccPublicationChecker = Just (checkUrlPublished tlsManager)
        }
      isPastHour = currentTime >= defaultPostingCutoff

  contentItems <- discoverContentToPost config isPastHour
  case contentItems of
    [] -> do
      putStrLn "  📭 No content to post"
      pure []
    items -> do
      putStrLn $ "  📋 Found " <> show (length items) <> " items to post"
      let grouped = groupByNote items
      results <- mapM (processNoteGroup manager env apiKey vaultDir) grouped
      pure (mapMaybe id results)

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
                 -> ([Platform], ContentNote, [Text]) -> IO (Maybe PostedNote)
processNoteGroup manager env apiKey vaultDir (platforms, note, pathFromRoot) = do
  putStrLn $ "  📝 Processing: " <> T.unpack (cnTitle note)
  putStrLn $ "     Platforms: " <> show platforms

  updatePathTimestamps vaultDir pathFromRoot

  results <- mapConcurrently (postForPlatform manager env apiKey note) platforms

  let successes = mapMaybe eitherToMaybe results
      embedSections = fmap
        (\pr -> (platformSectionHeader (prPlatform pr), prEmbedHtml pr, prSectionBuilder pr))
        successes
      postedPlatforms = fmap prPlatform successes

  case embedSections of
    [] -> do
      putStrLn "  ⚠️  No successful posts"
      pure Nothing
    _  -> do
      Sync.writeEmbedsToNote (cnFilePath note) embedSections
      putStrLn $ "  ✅ " <> show (length successes) <> " embeds written"
      pure (Just (PostedNote note postedPlatforms))

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

--------------------------------------------------------------------------------
-- Main orchestrator
--------------------------------------------------------------------------------

autoPost :: Manager -> FilePath -> IO ()
autoPost manager vaultDir = do
  env <- validateEnvironment
  let apiKey = gcApiKey (ecGemini env)

  postedNotes <- runPostingPipeline manager env apiKey vaultDir

  let reflectionsDir = vaultDir </> "reflections"
  DateStr todayStr <- todayPacific
  let updateLinks = fmap (\pn ->
        let details = fmap platformDetail (pnPlatforms pn)
        in UpdateLink (cnRelativePath (pnNote pn)) (cnTitle (pnNote pn)) details
        ) postedNotes
  _ <- addUpdateLinksToReflection reflectionsDir todayStr updateLinks
  pure ()
