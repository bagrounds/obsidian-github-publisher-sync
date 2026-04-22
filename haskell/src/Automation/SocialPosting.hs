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
  , regenerateBlueskyEmbeds
  , regenerateMastodonEmbeds
  ) where

import Control.Concurrent.Async (mapConcurrently)
import Control.Exception (SomeException, try)

import Data.List.NonEmpty (NonEmpty ((:|)))
import Data.Maybe (catMaybes, fromMaybe, mapMaybe)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Data.Time (getCurrentTime, utctDayTime)
import Data.Time.LocalTime (timeToTimeOfDay)
import qualified Data.Map.Strict as Map
import Network.HTTP.Client (Manager)
import qualified Network.HTTP.Client.TLS as TLS
import System.Directory (listDirectory, doesFileExist, doesDirectoryExist)

import Automation.DailyUpdates (UpdateDetail (..), UpdateLink (..), addUpdateLinksToReflection)
import Automation.EmbedSection
  ( buildBlueskySection
  , buildMastodonSection
  , buildTweetSection
  )
import Automation.Env (validateEnvironment, EnvironmentConfig (..))
import Automation.PacificTime (todayPacificDay)
import qualified Automation.Gemini as Gemini
import qualified Automation.ObsidianSync as Sync
import Automation.Platform (Platform (..), PlatformLimits (..))
import qualified Automation.Platforms.Bluesky as Bluesky
import qualified Automation.Platforms.Mastodon as Mastodon
import qualified Automation.Platforms.OgMetadata as OgMeta
import Automation.Platforms.OgMetadata (fetchOgMetadata)
import qualified Automation.Platforms.Twitter as Twitter
import Automation.Prompts (PromptPair (..), assemblePost, buildQuestionPrompt, buildShortenQuestionPrompt, buildTagsPrompt)
import Automation.Reflection (ReflectionData (..))
import Automation.Secret (Secret, unSecret)
import Automation.BlogImage.ContentDirectory (ContentDirectory)
import qualified Automation.SocialPosting.ContentDiscovery as CD
import Automation.SocialPosting.ContentDiscovery
  ( ContentNote (..)
  , FindContentConfig (FindContentConfig)
  , checkUrlPublished
  , defaultPostingCutoff
  , discoverContentToPost
  )
import Automation.SocialPosting.FrontmatterUpdate (updatePathTimestamps)
import Automation.Text (calculatePostLength, fitPostToLimit)
import Automation.Title (unTitle)
import Automation.Url (unUrl)
import Automation.RelativePath (RelativePath, unRelativePath)
import System.FilePath (takeBaseName, takeExtension, (</>))

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

platformUpdateDetail :: Platform -> UpdateDetail
platformUpdateDetail = PostedTo

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
  [ case twitter ec of { Just _ -> Just Twitter; Nothing -> Nothing }
  , case bluesky ec of { Just _ -> Just Bluesky; Nothing -> Nothing }
  , case mastodon ec of { Just _ -> Just Mastodon; Nothing -> Nothing }
  ]

generateSocialPostText :: Manager -> Secret -> ContentNote -> Platform -> IO (Either Text Text)
generateSocialPostText manager apiKey note platform = do
  let rd = ReflectionData
        { date = extractDateFromPath (noteRelativePath note)
        , title = noteTitle note
        , url = noteUrl note
        , body = noteBody note
        , filePath = T.pack (noteFilePath note)
        , hasTweetSection = Set.member Twitter (notePostedPlatforms note)
        , hasBlueskySection = Set.member Bluesky (notePostedPlatforms note)
        , hasMastodonSection = Set.member Mastodon (notePostedPlatforms note)
        }
      tagsPrompt = buildTagsPrompt rd
      questionPrompt = buildQuestionPrompt rd
      tagsCombined = system tagsPrompt <> "\n\n" <> user tagsPrompt
      questionCombined = system questionPrompt <> "\n\n" <> user questionPrompt
      maxLen = platformMaxCharacters (platformLimits platform)
      genConfig = Gemini.defaultGenerationConfig { Gemini.temperature = 0.8, Gemini.maxOutputTokens = 512 }

  tagsResult <- Gemini.generateContentWithFallback manager (Gemini.defaultModel :| [Gemini.gemini3Flash, Gemini.flashFallback]) Nothing tagsCombined apiKey genConfig False
  questionResult <- Gemini.generateContentWithFallback manager (Gemini.defaultQuestionModel :| [Gemini.flashFallback]) Nothing questionCombined apiKey genConfig False

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
              shortenCombined = system shortenPrompt <> "\n\n" <> user shortenPrompt
          putStrLn $ "  ✂️ Post exceeds Bluesky limit by " <> show overage <> " chars — asking LLM to shorten question..."
          shortenResult <- Gemini.generateContentWithFallback manager (Gemini.defaultQuestionModel :| [Gemini.flashFallback]) Nothing shortenCombined apiKey genConfig False
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
  { platform :: Platform
  , embedHtml :: Text
  , sectionBuilder :: Text -> Text -> Text
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
  case twitter env of
    Nothing -> pure (Left "Twitter not configured")
    Just creds -> do
      result <- Twitter.post manager creds postText
      case result of
        Left err -> pure (Left $ "Twitter post failed: " <> T.pack (show err))
        Right (tweetId, _tweetText) -> do
          embedHtml <- Twitter.getEmbedHtml manager tweetId (unSecret (Twitter.accessToken creds))
                         (unSecret (Twitter.apiKey creds)) (unSecret (Twitter.apiSecret creds))
          pure $ Right PostResult
            { platform = Twitter
            , embedHtml = embedHtml
            , sectionBuilder = buildTweetSection
            }

postToBlueskyPlatform :: Manager -> EnvironmentConfig -> ContentNote -> Text
                      -> IO (Either Text PostResult)
postToBlueskyPlatform manager env note postText =
  case bluesky env of
    Nothing -> pure (Left "Bluesky not configured")
    Just creds -> do
      ogMeta <- fetchOgMetadata (unUrl (noteUrl note))
      let linkCard = Bluesky.LinkCard
            { uri = noteUrl note
            , title = fromMaybe (noteTitle note) (OgMeta.title ogMeta)
            , description = fromMaybe "" (OgMeta.description ogMeta)
            , thumbUrl = OgMeta.imageUrl ogMeta
            }
      result <- Bluesky.post manager creds postText (Just linkCard)
      case result of
        Left err -> pure (Left $ "Bluesky post failed: " <> T.pack (show err))
        Right blueskyPostResult -> do
          embedHtml <- Bluesky.getEmbedHtml manager Bluesky.defaultOEmbedConfig
                         (Bluesky.postUri blueskyPostResult)
          pure $ Right PostResult
            { platform = Bluesky
            , embedHtml = embedHtml
            , sectionBuilder = buildBlueskySection
            }

postToMastodonPlatform :: Manager -> EnvironmentConfig -> ContentNote -> Text
                       -> IO (Either Text PostResult)
postToMastodonPlatform manager env _note postText =
  case mastodon env of
    Nothing -> pure (Left "Mastodon not configured")
    Just creds -> do
      result <- Mastodon.post manager creds postText
      case result of
        Left err -> pure (Left $ "Mastodon post failed: " <> T.pack (show err))
        Right mpr -> do
          let postUrl = unUrl (Mastodon.url mpr)
              mInstance = Mastodon.extractInstanceUrl postUrl
              mStatusId = Mastodon.extractStatusId postUrl
              mUsername = Mastodon.extractUsername postUrl
          case (mInstance, mStatusId, mUsername) of
            (Just instanceUrl, Just statusId, Just _username) -> do
              embedHtml <- Mastodon.getEmbedHtml manager postUrl instanceUrl statusId
              pure $ Right PostResult
                { platform = Mastodon
                , embedHtml = embedHtml
                , sectionBuilder = buildMastodonSection
                }
            _ -> pure $ Left "Could not extract Mastodon post details from URL"

data PostedNote = PostedNote
  { note      :: ContentNote
  , platforms :: [Platform]
  } deriving (Show, Eq)

runPostingPipeline :: Manager -> EnvironmentConfig -> Secret -> FilePath -> [ContentDirectory] -> IO [PostedNote]
runPostingPipeline manager env apiKey vaultDir imageBackfillContentDirs = do
  let platforms = getConfiguredPlatforms env
  putStrLn $ "  🔍 Configured platforms: " <> show platforms

  now <- getCurrentTime
  tlsManager <- TLS.newTlsManager
  let currentTime = timeToTimeOfDay (utctDayTime now)
      config = FindContentConfig
        { contentDir = vaultDir
        , platforms = platforms
        , postingCutoff = defaultPostingCutoff
        , publicationChecker = Just (checkUrlPublished tlsManager)
        , imageBackfillContentDirs = imageBackfillContentDirs
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

groupByNote :: [CD.ContentToPost] -> [([Platform], ContentNote, [Text])]
groupByNote items =
  let noteMap = foldl addToGroup Map.empty items
  in Map.elems noteMap
  where
    addToGroup acc ctp =
      let key = noteRelativePath (CD.note ctp)
      in Map.insertWith merge key
           ([CD.platform ctp], CD.note ctp, CD.pathFromRoot ctp) acc
    merge (p1, n, path) (p2, _, _) = (p1 <> p2, n, path)

processNoteGroup :: Manager -> EnvironmentConfig -> Secret -> FilePath
                 -> ([Platform], ContentNote, [Text]) -> IO (Maybe PostedNote)
processNoteGroup manager env apiKey vaultDir (platforms, note, pathFromRoot) = do
  putStrLn $ "  📝 Processing: " <> T.unpack (unTitle (noteTitle note))
  putStrLn $ "     Platforms: " <> show platforms

  updatePathTimestamps vaultDir pathFromRoot

  results <- mapConcurrently (postForPlatform manager env apiKey note) platforms

  let successes = mapMaybe eitherToMaybe results
      embedSections = fmap
        (\pr -> (platformSectionHeader (platform pr), embedHtml pr, sectionBuilder pr))
        successes
      postedPlatforms = fmap platform successes

  case embedSections of
    [] -> do
      putStrLn "  ⚠️  No successful posts"
      pure Nothing
    _  -> do
      Sync.writeEmbedsToNote (noteFilePath note) embedSections
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

autoPost :: Manager -> FilePath -> [ContentDirectory] -> IO ()
autoPost manager vaultDir imageBackfillContentDirs = do
  env <- validateEnvironment
  let apiKey = Gemini.apiKey (gemini env)

  regenerateResult <- try (regenerateBlueskyEmbeds manager vaultDir)
    :: IO (Either SomeException ())
  case regenerateResult of
    Left exception -> putStrLn $ "  ⚠️  Bluesky embed regeneration failed: " <> show exception
    Right () -> pure ()

  mastodonRegenerateResult <- try (regenerateMastodonEmbeds vaultDir)
    :: IO (Either SomeException ())
  case mastodonRegenerateResult of
    Left exception -> putStrLn $ "  ⚠️  Mastodon embed regeneration failed: " <> show exception
    Right () -> pure ()

  postedNotes <- runPostingPipeline manager env apiKey vaultDir imageBackfillContentDirs

  today <- todayPacificDay
  let updateLinks = fmap (\pn ->
        let details = fmap platformUpdateDetail (platforms pn)
        in UpdateLink (noteRelativePath (note pn)) (noteTitle (note pn)) details
        ) postedNotes
  _ <- addUpdateLinksToReflection vaultDir today updateLinks
  pure ()

regenerateBlueskyEmbeds :: Manager -> FilePath -> IO ()
regenerateBlueskyEmbeds manager vaultDir = do
  putStrLn "  🔄 Scanning for Bluesky placeholder embeds to regenerate..."
  files <- findMarkdownFiles vaultDir
  regenerated <- mapM (tryRegenerateFile manager) files
  let count = sum regenerated
  if count > 0
    then putStrLn $ "  ✅ Regenerated " <> show count <> " Bluesky embed(s)"
    else putStrLn "  📭 No Bluesky placeholder embeds found"

findMarkdownFiles :: FilePath -> IO [FilePath]
findMarkdownFiles dir = do
  entries <- listDirectory dir
  let visible = filter (not . isHidden) entries
  paths <- mapM (processEntry dir) visible
  pure (concat paths)
  where
    isHidden name = case name of
      ('.' : _) -> True
      _         -> False
    processEntry parent name = do
      let fullPath = parent </> name
      isFile <- doesFileExist fullPath
      if isFile && takeExtension name == ".md"
        then pure [fullPath]
        else do
          isDir <- doesDirectoryExist fullPath
          if isDir
            then findMarkdownFiles fullPath
            else pure []

tryRegenerateFile :: Manager -> FilePath -> IO Int
tryRegenerateFile manager filePath = do
  content <- TIO.readFile filePath
  let blueskyHeader = Bluesky.sectionHeader
  if not (blueskyHeader `T.isInfixOf` content)
    then pure 0
    else do
      let sectionContent = extractSectionContent blueskyHeader content
      case Bluesky.extractRegenerationUrl sectionContent of
        Just postUrl -> do
          putStrLn $ "  🔄 Regenerating embed for: " <> filePath
          oembedResult <- Bluesky.fetchOEmbed manager postUrl
          case oembedResult of
            Right (Bluesky.EmbedResult newEmbed) -> do
              let newContent = Bluesky.replaceSectionContent content newEmbed
              TIO.writeFile filePath newContent
              putStrLn $ "  ✅ Regenerated: " <> filePath
              pure 1
            Left err -> do
              putStrLn $ "  ⚠️  oEmbed still failing for " <> filePath <> ": " <> show err
              pure 0
        Nothing
          | Bluesky.needsDarkModeUpdate sectionContent -> do
              putStrLn $ "  🌑 Updating Bluesky embed to dark mode: " <> filePath
              let darkContent = Bluesky.toDarkMode sectionContent
                  newContent = Bluesky.replaceSectionContent content darkContent
              TIO.writeFile filePath newContent
              putStrLn $ "  ✅ Updated: " <> filePath
              pure 1
          | otherwise -> pure 0

extractSectionContent :: Text -> Text -> Text
extractSectionContent header content =
  case T.breakOn header content of
    (_, "") -> ""
    (_, rest) ->
      let afterHeader = T.drop (T.length header) rest
          lines' = T.lines afterHeader
          sectionLines = takeWhile (not . isNextSection) (drop 1 lines')
      in T.unlines sectionLines
  where
    isNextSection line = "## " `T.isPrefixOf` T.stripStart line

regenerateMastodonEmbeds :: FilePath -> IO ()
regenerateMastodonEmbeds vaultDir = do
  putStrLn "  🔄 Scanning for Mastodon embeds needing dark mode update..."
  files <- findMarkdownFiles vaultDir
  regenerated <- mapM tryDarkenMastodonFile files
  let count = sum regenerated
  if count > 0
    then putStrLn $ "  ✅ Updated " <> show count <> " Mastodon embed(s) to dark mode"
    else putStrLn "  📭 No Mastodon embeds need dark mode update"

tryDarkenMastodonFile :: FilePath -> IO Int
tryDarkenMastodonFile filePath = do
  content <- TIO.readFile filePath
  let mastodonHeader = Mastodon.sectionHeader
      sectionContent = extractSectionContent mastodonHeader content
  if mastodonHeader `T.isInfixOf` content && Mastodon.needsDarkModeUpdate sectionContent
    then do
      putStrLn $ "  🌑 Updating Mastodon embed to dark mode: " <> filePath
      let darkContent = Mastodon.toDarkMode sectionContent
          newContent = Mastodon.replaceSectionContent content darkContent
      TIO.writeFile filePath newContent
      putStrLn $ "  ✅ Updated: " <> filePath
      pure 1
    else pure 0
