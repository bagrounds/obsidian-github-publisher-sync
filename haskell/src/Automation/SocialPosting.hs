module Automation.SocialPosting
  ( SocialPost (..)
  , PostedNote (..)
  , socialPostContent
  , socialPostPlatform
  , mkTweet
  , mkBlueskyPost
  , mkMastodonPost
  , mkSocialPost
  , autoPost
  , runPostingPipeline
  ) where

import Control.Concurrent.Async (mapConcurrently)
import Control.Exception (SomeException, try)

import Data.List.NonEmpty (NonEmpty ((:|)))
import Data.Maybe (catMaybes, fromMaybe, mapMaybe)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (getCurrentTime, utctDayTime)
import Data.Time.LocalTime (timeToTimeOfDay)
import qualified Data.Map.Strict as Map
import Network.HTTP.Client (Manager)
import qualified Network.HTTP.Client.TLS as TLS

import Automation.DailyUpdates (UpdateLink (..), addUpdateLinksToReflection)
import Automation.EmbedSection
  ( buildBlueskySection
  , buildMastodonSection
  , buildTweetSection
  )
import Automation.Env (validateEnvironment)
import Automation.BlogPrompt (formatDay, todayPacificDay)
import qualified Automation.Gemini as Gemini
import qualified Automation.ObsidianSync as Sync
import Automation.Platform (Platform (..), PlatformLimits (..))
import qualified Automation.Platforms.Bluesky as Bluesky
import qualified Automation.Platforms.Mastodon as Mastodon
import Automation.Platforms.OgMetadata (fetchOgMetadata)
import qualified Automation.Platforms.Twitter as Twitter
import Automation.Prompts (PromptPair (..), assemblePost, buildQuestionPrompt, buildShortenQuestionPrompt, buildTagsPrompt)
import Automation.Reflection (ReflectionData (..))
import Automation.Secret (Secret, unSecret)
import Automation.SocialPosting.ContentDiscovery
  ( ContentNote (..)
  , ContentToPost (..)
  , FindContentConfig (..)
  , checkUrlPublished
  , defaultPostingCutoff
  , discoverContentToPost
  )
import Automation.SocialPosting.FrontmatterUpdate (updatePathTimestamps)
import Automation.Text (calculatePostLength, fitPostToLimit)
import Automation.Title (unTitle)
import Automation.Types (EnvironmentConfig (..), OgMetadata (..))
import Automation.Url (unUrl)
import Automation.RelativePath (RelativePath, unRelativePath)
import System.FilePath (takeBaseName, (</>))

data SocialPost
  = Tweet Text
  | BlueskyPost Text
  | MastodonPost Text
  deriving (Show, Eq)

socialPostContent :: SocialPost -> Text
socialPostContent (Tweet text) = text
socialPostContent (BlueskyPost text) = text
socialPostContent (MastodonPost text) = text

socialPostPlatform :: SocialPost -> Platform
socialPostPlatform (Tweet _) = Twitter
socialPostPlatform (BlueskyPost _) = Bluesky
socialPostPlatform (MastodonPost _) = Mastodon

mkTweet :: Text -> Either Text SocialPost
mkTweet text
  | calculatePostLength Twitter.limits text > platformMaxCharacters Twitter.limits =
      Left $ "Tweet exceeds " <> T.pack (show (platformMaxCharacters Twitter.limits))
        <> " characters (actual: " <> T.pack (show (calculatePostLength Twitter.limits text)) <> ")"
  | otherwise = Right (Tweet text)

mkBlueskyPost :: Text -> Either Text SocialPost
mkBlueskyPost text
  | calculatePostLength Bluesky.limits text > platformMaxCharacters Bluesky.limits =
      Left $ "Bluesky post exceeds " <> T.pack (show (platformMaxCharacters Bluesky.limits))
        <> " characters (actual: " <> T.pack (show (calculatePostLength Bluesky.limits text)) <> ")"
  | otherwise = Right (BlueskyPost text)

mkMastodonPost :: Text -> Either Text SocialPost
mkMastodonPost text
  | calculatePostLength Mastodon.limits text > platformMaxCharacters Mastodon.limits =
      Left $ "Mastodon post exceeds " <> T.pack (show (platformMaxCharacters Mastodon.limits))
        <> " characters (actual: " <> T.pack (show (calculatePostLength Mastodon.limits text)) <> ")"
  | otherwise = Right (MastodonPost text)

mkSocialPost :: Platform -> Text -> Either Text SocialPost
mkSocialPost Twitter = mkTweet
mkSocialPost Bluesky = mkBlueskyPost
mkSocialPost Mastodon = mkMastodonPost

platformDetail :: Platform -> Text
platformDetail Twitter  = "🐦 posted to Twitter"
platformDetail Bluesky  = "🦋 posted to BlueSky"
platformDetail Mastodon = "🐘 posted to Mastodon"

platformSectionHeader :: Platform -> Text
platformSectionHeader Twitter  = Twitter.sectionHeader
platformSectionHeader Bluesky  = Bluesky.sectionHeader
platformSectionHeader Mastodon = Mastodon.sectionHeader

platformLimits :: Platform -> PlatformLimits
platformLimits Twitter  = Twitter.limits
platformLimits Bluesky  = Bluesky.limits
platformLimits Mastodon = Mastodon.limits

getConfiguredPlatforms :: EnvironmentConfig -> [Platform]
getConfiguredPlatforms ec = catMaybes
  [ case ecTwitter ec of { Just _ -> Just Twitter; Nothing -> Nothing }
  , case ecBluesky ec of { Just _ -> Just Bluesky; Nothing -> Nothing }
  , case ecMastodon ec of { Just _ -> Just Mastodon; Nothing -> Nothing }
  ]

generateSocialPostText :: Manager -> Secret -> ContentNote -> Platform -> IO (Either Text Text)
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
      maxLen = platformMaxCharacters (platformLimits platform)
      genConfig = Gemini.defaultGenerationConfig { Gemini.gcTemperature = 0.8, Gemini.gcMaxOutputTokens = 512 }

  tagsResult <- Gemini.generateContentWithFallback manager (Gemini.defaultModel :| [Gemini.gemini3Flash, Gemini.flashFallback]) tagsCombined apiKey genConfig
  questionResult <- Gemini.generateContentWithFallback manager (Gemini.defaultQuestionModel :| [Gemini.flashFallback]) questionCombined apiKey genConfig

  case (tagsResult, questionResult) of
    (Left err, _) -> pure (Left $ "Tags generation failed: " <> T.pack (show err))
    (_, Left err) -> pure (Left $ "Question generation failed: " <> T.pack (show err))
    (Right tagsResponse, Right questionResponse) -> do
      let tags = T.strip (Gemini.responseText tagsResponse)
          question = T.strip (Gemini.responseText questionResponse)
          modelOutput = question <> "\n" <> tags
          rawPost = assemblePost modelOutput rd
          overage = T.length rawPost - platformMaxCharacters Bluesky.limits
      finalPost <- if overage > 0
        then do
          let shortenSafetyBuffer = 10
              shortenPrompt = buildShortenQuestionPrompt question (overage + shortenSafetyBuffer)
              shortenCombined = ppSystem shortenPrompt <> "\n\n" <> ppUser shortenPrompt
          putStrLn $ "  ✂️ Post exceeds Bluesky limit by " <> show overage <> " chars — asking LLM to shorten question..."
          shortenResult <- Gemini.generateContentWithFallback manager (Gemini.defaultQuestionModel :| [Gemini.flashFallback]) shortenCombined apiKey genConfig
          case shortenResult of
            Right shortenResponse -> do
              let shortenedQ = T.strip (Gemini.responseText shortenResponse)
                  shortenedOutput = shortenedQ <> "\n" <> tags
              pure $ assemblePost shortenedOutput rd
            Left _ -> pure rawPost
        else pure rawPost
      pure (Right (fitPostToLimit finalPost maxLen))

-- | Extract a date string from a relative path (the filename without extension)
extractDateFromPath :: RelativePath -> Text
extractDateFromPath path =
  T.pack $ takeBaseName $ T.unpack $ unRelativePath path

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
      result <- Twitter.post manager creds postText
      case result of
        Left err -> pure (Left $ "Twitter post failed: " <> T.pack (show err))
        Right (tweetId, _tweetText) -> do
          embedHtml <- Twitter.getEmbedHtml manager tweetId (unSecret (Twitter.tcAccessToken creds))
                         (unSecret (Twitter.tcApiKey creds)) (unSecret (Twitter.tcApiSecret creds))
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
      ogMeta <- fetchOgMetadata (unUrl (cnUrl note))
      let linkCard = Bluesky.LinkCard
            { lcUri = cnUrl note
            , lcTitle = fromMaybe (cnTitle note) (ogTitle ogMeta)
            , lcDescription = fromMaybe "" (ogDescription ogMeta)
            , lcThumbUrl = ogImageUrl ogMeta
            }
      result <- Bluesky.post manager creds postText (Just linkCard)
      case result of
        Left err -> pure (Left $ "Bluesky post failed: " <> T.pack (show err))
        Right bpr -> do
          let mDid = Bluesky.extractDid (Bluesky.bprUri bpr)
              mPostId = Bluesky.extractPostId (Bluesky.bprUri bpr)
          case (mDid, mPostId) of
            (Just did, Just postId) -> do
              let postUrl = Bluesky.buildPostUrl (Bluesky.bcIdentifier creds) postId
              embedHtml <- Bluesky.getEmbedHtml manager postUrl did
                             (Bluesky.bcIdentifier creds) postId Nothing
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
      result <- Mastodon.post manager creds postText
      case result of
        Left err -> pure (Left $ "Mastodon post failed: " <> T.pack (show err))
        Right mpr -> do
          let postUrl = unUrl (Mastodon.mprUrl mpr)
              mInstance = Mastodon.extractInstanceUrl postUrl
              mStatusId = Mastodon.extractStatusId postUrl
              mUsername = Mastodon.extractUsername postUrl
          case (mInstance, mStatusId, mUsername) of
            (Just instanceUrl, Just statusId, Just _username) -> do
              embedHtml <- Mastodon.getEmbedHtml manager postUrl instanceUrl statusId
              pure $ Right PostResult
                { prPlatform = Mastodon
                , prEmbedHtml = embedHtml
                , prSectionBuilder = buildMastodonSection
                }
            _ -> pure $ Left "Could not extract Mastodon post details from URL"

data PostedNote = PostedNote
  { pnNote      :: ContentNote
  , pnPlatforms :: [Platform]
  } deriving (Show, Eq)

runPostingPipeline :: Manager -> EnvironmentConfig -> Secret -> FilePath -> IO [PostedNote]
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
      pure (catMaybes results)

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

processNoteGroup :: Manager -> EnvironmentConfig -> Secret -> FilePath
                 -> ([Platform], ContentNote, [Text]) -> IO (Maybe PostedNote)
processNoteGroup manager env apiKey vaultDir (platforms, note, pathFromRoot) = do
  putStrLn $ "  📝 Processing: " <> T.unpack (unTitle (cnTitle note))
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

postForPlatform :: Manager -> EnvironmentConfig -> Secret -> ContentNote -> Platform
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

autoPost :: Manager -> FilePath -> IO ()
autoPost manager vaultDir = do
  env <- validateEnvironment
  let apiKey = Gemini.gcApiKey (ecGemini env)

  postedNotes <- runPostingPipeline manager env apiKey vaultDir

  let reflectionsDir = vaultDir </> "reflections"
  today <- todayPacificDay
  let todayStr = formatDay today
      updateLinks = fmap (\pn ->
        let details = fmap platformDetail (pnPlatforms pn)
        in UpdateLink (cnRelativePath (pnNote pn)) (cnTitle (pnNote pn)) details
        ) postedNotes
  _ <- addUpdateLinksToReflection reflectionsDir todayStr updateLinks
  pure ()
