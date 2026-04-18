module Main where

import Control.Monad (when)
import Control.Exception (SomeException, try)
import Data.List.NonEmpty (NonEmpty ((:|)))
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (catMaybes, fromMaybe)
import qualified Data.ByteString.Lazy as LBS
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Text.IO as TIO
import Network.HTTP.Client (newManager)
import qualified Network.HTTP.Client as HTTP
import Network.HTTP.Client.TLS (tlsManagerSettings)
import Network.HTTP.Types.Status (statusCode)
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, doesFileExist, listDirectory, removeFile)
import System.Environment (getArgs, lookupEnv)
import System.Exit (exitFailure)
import System.FilePath ((</>), dropExtension)
import System.IO (hSetBuffering, stdout, stderr, BufferMode(..))

import Automation.AiBlogLinks (NavLinkResult (..), aiBlogConfig, ensureAllNavLinks, buildReflectionLinks)
import Automation.AiFiction
  ( FictionConfig (FictionConfig, fcModels, fcNoteContent)
  , FictionResult (frFiction, frModel, frUpdatedContent)
  , defaultFictionModel
  , generateFiction
  , reflectionNeedsFiction
  )
import Automation.BlogComments (fetchAllSeriesComments)
import Automation.BlogImage (BackfillConfig (..), BackfillResult (..), syncAttachmentsDir, backfillImages, processNote)
import Automation.BlogImage.ContentDirectory (ContentDirectory)
import Automation.BlogImage.Provider (ImageGenerationResult, resolveImageProviders)
import Automation.BlogPosts (BlogPost (..), readSeriesPosts)
import Automation.BlogPrompt
  ( DisplayTitle (..)
  , Slug (..)
  , assembleFrontmatter
  , buildBlogPrompt
  , buildDisplayTitle
  , generateSlug
  , mkSlug
  , sanitizeTitle
  )
import Automation.BlogSeries
  ( appendModelSignature
  , buildBlogContext
  , containsSystemPrompt
  , generateSeriesIndex
  , parseGeneratedPost
  , updatePreviousPost
  )
import Automation.BlogSeriesConfig
  ( BlogSeriesConfig (..)
  , imageBackfillContentDirsFrom
  , lookupSeriesIn
  )
import Automation.BlogSeriesDiscovery
  ( DiscoveredSeries (..)
  , DiscoveryError (..)
  , deriveBlogSeriesConfig
  , deriveBlogSeriesRunConfig
  , deriveScheduleEntry
  , discoverSeries
  )
import Automation.DailyReflection (UpdateReflectionResult (..), updateDailyReflection)
import Automation.DailyUpdates (UpdateDetail (..), UpdateLink (..), addUpdateLinksToReflection, extractTitleFromFile)
import qualified Automation.Gemini as Gemini
import Automation.ObsidianSync
  ( ObsidianCredentials (..)
  , syncObsidianVault
  , pushObsidianVault
  )
import Automation.ReflectionTitle
  ( ReflectionTitleConfig (ReflectionTitleConfig, rtcModels, rtcNoteContent, rtcDate, rtcRecentTitles)
  , ReflectionTitleResult (rtrFullTitle, rtrModel, rtrUpdatedContent)
  , defaultTitleModel
  , extractCreativeTitle
  , filterRecentReflectionFiles
  , generateReflectionTitle
  , reflectionNeedsTitle
  )
import Automation.Scheduler
  ( TaskId (..)
  , ScheduleEntry (..)
  , BlogSeriesRunConfig (..)
  , buildBlogSeriesRunConfigs
  , buildSchedule
  , blogPostExistsForToday
  , findPostToRegenerate
  , getScheduledTasks
  , isValidTaskId
  , nowPacificHour
  , taskIdFromText
  , taskIdToText
  )
import Automation.RelativePath (unRelativePath, mkRelativePath)
import Automation.Secret (Secret (..))
import Automation.Title (mkTitle)
import Automation.Wikilink (buildBackLink)
import qualified Automation.Context as Context
import qualified Automation.InternalLinking as IL
import Automation.SocialPosting (autoPost)
import Automation.CliArgs (CliArgs (..), parseCliArgs)
import Automation.PacificTime (formatDay, todayPacificDay, yesterdayPacificDay)
import Automation.VaultSync (syncFileToVault, syncNewAiBlogPosts, copySeriesPosts, syncRepoPostsToVault, ensureFileInVault)
import Automation.TaskRunner (inferenceDashboards, runTasks, logMsg, failTask)
import Automation.Text (stripCodeFences)
import qualified Automation.GoogleAnalytics as GA
import qualified Automation.GcpAuth as GcpAuth
import qualified Automation.Json as Json

callGeminiForGenerator :: Context.AppContext -> NonEmpty Gemini.Model -> (Text, Text) -> IO (Text, Text)
callGeminiForGenerator context models (systemPrompt, userPrompt) = do
  let config = Gemini.defaultGenerationConfig { Gemini.temperature = 0.9, Gemini.maxOutputTokens = 2048 }
  result <- Gemini.generateContentWithFallback (Context.httpManager context) models (Just systemPrompt) userPrompt (Context.geminiApiKey context) config
  case result of
    Left err -> failTask $ "Gemini API error: " <> T.pack (show err)
    Right response -> pure (Gemini.responseText response, Gemini.modelToText (Gemini.responseModel response))

requireEnv :: String -> IO Text
requireEnv key = do
  mVal <- lookupEnv key
  case mVal of
    Just val -> pure (T.pack val)
    Nothing  -> error $ "Missing required environment variable: " <> key

lookupEnvText :: String -> IO (Maybe Text)
lookupEnvText key = fmap (fmap T.pack) (lookupEnv key)

getObsidianCreds :: IO ObsidianCredentials
getObsidianCreds = do
  authToken <- requireEnv "OBSIDIAN_AUTH_TOKEN"
  vaultName <- requireEnv "OBSIDIAN_VAULT_NAME"
  vaultPassword <- lookupEnvText "OBSIDIAN_VAULT_PASSWORD"
  pure ObsidianCredentials
    { ocAuthToken = Secret authToken
    , ocVaultName = vaultName
    , ocVaultPassword = fmap Secret vaultPassword
    }

buildEnvMap :: [String] -> IO (Map Text Text)
buildEnvMap keys = Map.fromList <$> mapM lookupOne keys
  where
    lookupOne k = do
      mVal <- lookupEnv k
      pure (T.pack k, maybe "" T.pack mVal)

extractRecentCreativeTitles :: FilePath -> Text -> IO [Text]
extractRecentCreativeTitles reflectionsDir today = do
  exists <- doesDirectoryExist reflectionsDir
  if not exists
    then pure []
    else do
      entries <- listDirectory reflectionsDir
      let recent = filterRecentReflectionFiles today entries
      titles <- traverse readCreativeTitle recent
      pure (filter (not . T.null) titles)
  where
    readCreativeTitle filename = do
      content <- TIO.readFile (reflectionsDir </> filename)
      pure (extractCreativeTitle content)

runBlogSeries :: Context.AppContext -> Map Text BlogSeriesConfig -> Map Text BlogSeriesRunConfig -> Text -> IO ()
runBlogSeries context seriesMap runConfigs seriesId = do
  let taskName = "blog-series:" <> seriesId
      manager = Context.httpManager context
      repoRoot = Context.repoRoot context
      vaultDir = Context.vaultDir context
      apiKey = Context.geminiApiKey context
  logMsg $ "▶️  " <> taskName

  let mRunConfig = Map.lookup seriesId runConfigs
  runConfig <- case mRunConfig of
    Just rc -> pure rc
    Nothing -> failTask $ "No run config for series: " <> seriesId

  today <- todayPacificDay
  let todayText = formatDay today
  _ <- copySeriesPosts vaultDir seriesId repoRoot

  series <- either failTask pure (lookupSeriesIn seriesMap seriesId)
  let agentsRelPath = T.unpack seriesId </> "AGENTS.md"
  _ <- syncFileToVault (repoRoot </> agentsRelPath) agentsRelPath vaultDir
  let vaultIndexPath = vaultDir </> T.unpack seriesId </> "index.md"
  indexCreated <- ensureFileInVault vaultIndexPath (generateSeriesIndex series)
  when indexCreated $ logMsg $ "  📋 Created index.md for " <> seriesId
  _ <- syncRepoPostsToVault repoRoot seriesId vaultDir logMsg

  let seriesDir = repoRoot </> T.unpack seriesId
  mRegen <- findPostToRegenerate seriesDir todayText
  case mRegen of
    Just postToRegen -> do
      logMsg $ "  ♻️  Regeneration requested for " <> T.pack postToRegen <> " — removing old post"
      removeFile (seriesDir </> postToRegen)
    Nothing -> do
      existsForToday <- blogPostExistsForToday seriesDir todayText
      when existsForToday $
        logMsg $ "  ⏭️  Already generated for " <> todayText

  existsNow <- blogPostExistsForToday seriesDir todayText
  case (mRegen, existsNow) of
    (Nothing, True) -> pure ()
    _ -> do
      envModel <- lookupEnvText "BLOG_GEMINI_MODEL"
      let models = Gemini.overrideModelChain envModel (bsrcModelChain runConfig)

      priorityUser <- lookupEnvText (T.unpack (bsrcPriorityUserEnvVar runConfig))

      comments <- fetchAllSeriesComments manager seriesId (priorityUser >>= (\u -> if T.null u then Nothing else Just u))
      logMsg $ "  📝 Fetched " <> T.pack (show (length comments)) <> " comments"

      blogContextResult <- buildBlogContext seriesMap seriesId repoRoot comments today
      case blogContextResult of
        Left reason -> failTask $ "Blog context build failed: " <> reason
        Right blogContext -> do
          let (systemPrompt, userPrompt) = buildBlogPrompt blogContext
              genConfig = Gemini.defaultGenerationConfig { Gemini.temperature = 0.9, Gemini.maxOutputTokens = 8192 }

          result <- Gemini.generateContentWithFallback manager models (Just systemPrompt) userPrompt apiKey genConfig
          case result of
            Left err -> failTask $ "Blog generation failed: " <> T.pack (show err)
            Right response -> do
              let rawText = stripCodeFences (Gemini.responseText response)
                  usedModel = Gemini.modelToText (Gemini.responseModel response)
              when (containsSystemPrompt systemPrompt rawText) $
                failTask "Generated post echoes the system prompt (AGENTS.md) — rejecting"
              case parseGeneratedPost rawText of
                Nothing -> failTask "Failed to parse generated blog post"
                Just (body, rawTitle) -> do
                  let title = sanitizeTitle series rawTitle
                      slugText = generateSlug title
                  slug <- either (\slugError -> failTask $ "Invalid slug: " <> slugError) pure (mkSlug slugText)
                  let filename = todayText <> "-" <> unSlug slug <> ".md"

                  posts <- readSeriesPosts seriesDir
                  let previousPost = case posts of
                        (p:_) -> Just p
                        []    -> Nothing

                  let frontmatter = assembleFrontmatter series today title slug
                      backLink = case previousPost of
                        Just pp -> " | " <> buildBackLink series (bpFilename pp)
                        Nothing -> ""
                      navLine = bscNavLink series <> backLink
                      displayTitle = unDisplayTitle $ buildDisplayTitle series today title
                      header = navLine <> "\n# " <> displayTitle <> "\n\n"
                      bodyWithSig = appendModelSignature body usedModel
                  createDirectoryIfMissing True seriesDir
                  let postPath = seriesDir </> T.unpack filename
                  TIO.writeFile postPath (frontmatter <> "\n" <> header <> bodyWithSig <> "\n")
                  logMsg $ "  ✅ Written: " <> filename <> " [" <> usedModel <> "]"

                  let attachmentsDir = repoRoot </> "attachments"
                  imageEnvMap <- buildEnvMap
                    [ "GEMINI_API_KEY", "CLOUDFLARE_API_TOKEN", "CLOUDFLARE_ACCOUNT_ID"
                    , "CLOUDFLARE_IMAGE_MODEL", "HUGGINGFACE_API_TOKEN", "HUGGINGFACE_IMAGE_MODEL"
                    , "TOGETHER_API_TOKEN", "TOGETHER_IMAGE_MODEL", "POLLINATIONS_ENABLED"
                    , "POLLINATIONS_IMAGE_MODEL", "PROMPT_DESCRIBER_MODEL", "IMAGE_GEMINI_MODEL"
                    ]
                  let imageProviders = resolveImageProviders imageEnvMap
                  case imageProviders of
                    [] -> logMsg "  ⚠️  No image providers configured, skipping image generation"
                    (provider : _) -> do
                      imageResult <- try (processNote manager provider postPath attachmentsDir) :: IO (Either SomeException ImageGenerationResult)
                      case imageResult of
                        Right _ -> logMsg $ "  🖼️  Image generated for " <> filename
                        Left err -> logMsg $ "  ⚠️  Image generation failed for " <> filename <> ": " <> T.pack (show err)

                  case previousPost of
                    Just pp -> updatePreviousPost (vaultDir </> T.unpack seriesId) pp series filename
                    Nothing -> pure ()

                  let metadataPath = seriesDir </> ".last-generate-metadata.json"
                  case previousPost of
                    Just pp -> TIO.writeFile metadataPath $
                      "{\"previousPostFilename\":\"" <> bpFilename pp <> "\",\"newPostFilename\":\"" <> filename <> "\"}"
                    Nothing -> pure ()

                  let filenameNoExt = T.pack $ dropExtension $ T.unpack filename
                      regenFilenameNoExt = case mRegen of
                        Just r  -> Just (T.pack (dropExtension r))
                        Nothing -> Nothing
                  postTitle <- either (\e -> failTask $ "Invalid display title: " <> e) pure (mkTitle displayTitle)
                  _ <- updateDailyReflection vaultDir todayText series filenameNoExt postTitle regenFilenameNoExt

                  let postRelPath = T.unpack seriesId </> T.unpack filename
                      postLocalPath = repoRoot </> postRelPath
                  _ <- syncFileToVault postLocalPath postRelPath vaultDir

                  syncAttachmentsDir (repoRoot </> "attachments") (vaultDir </> "attachments")
                  pure ()

  logMsg $ "✅ " <> taskName

runBackfillImages :: Context.AppContext -> [ContentDirectory] -> IO ()
runBackfillImages context contentDirs = do
  let manager = Context.httpManager context
      repoRoot = Context.repoRoot context
      vaultDir = Context.vaultDir context
  logMsg "▶️  backfill-blog-images"

  today <- todayPacificDay
  let todayText = formatDay today

  -- 1. Sync new AI blog posts from repo to vault (copy-if-missing only)
  let repoAiBlogDir = repoRoot </> "ai-blog"
      vaultAiBlogDir = vaultDir </> "ai-blog"
  newPostCount <- syncNewAiBlogPosts repoAiBlogDir vaultAiBlogDir logMsg
  case newPostCount of
    0 -> pure ()
    n -> logMsg $ "  📝 Synced " <> T.pack (show n) <> " new AI blog post(s) to vault"

  -- 2. Image backfill — operates directly on vault files
  envMap <- buildEnvMap
    [ "GEMINI_API_KEY", "CLOUDFLARE_API_TOKEN", "CLOUDFLARE_ACCOUNT_ID"
    , "CLOUDFLARE_IMAGE_MODEL", "HUGGINGFACE_API_TOKEN", "HUGGINGFACE_IMAGE_MODEL"
    , "TOGETHER_API_TOKEN", "TOGETHER_IMAGE_MODEL", "POLLINATIONS_ENABLED"
    , "POLLINATIONS_IMAGE_MODEL", "PROMPT_DESCRIBER_MODEL", "IMAGE_GEMINI_MODEL"
    ]
  let providers = resolveImageProviders envMap
  imageModifiedFiles <- case providers of
    [] -> do
      logMsg "  ⚠️  No image providers configured, skipping image backfill"
      pure []
    _  -> do
      logMsg $ "  🎨 Image providers: " <> T.pack (show (length providers))
      let backfillConfig = BackfillConfig
            { backfillRepoRoot = vaultDir
            , backfillContentDirs = contentDirs
            , backfillAttachmentsDir = vaultDir </> "attachments"
            , backfillProviders = providers
            , backfillMaxImages = 2
            }
      result <- backfillImages manager backfillConfig
      logMsg $ "  🖼️  Images: " <> T.pack (show (brImagesGenerated result))
            <> "/" <> T.pack (show (backfillMaxImages backfillConfig))
            <> " generated, " <> T.pack (show (brFilesUpdated result))
            <> " files updated, " <> T.pack (show (brFilesSkipped result)) <> " skipped"
      case brErrors result of
        [] -> pure ()
        errs -> logMsg $ "  ⚠️  Errors: " <> T.intercalate "; " errs
      pure (brModifiedFiles result)

  -- 3. Update AI blog nav links — operates directly on vault files
  let aiBlogDir = vaultDir </> "ai-blog"
  navResults <- ensureAllNavLinks aiBlogDir
  let modifiedCount = length (filter nlrModified navResults)
  logMsg $ "  🔗 Nav links: " <> T.pack (show modifiedCount) <> " files updated"

  -- 4. Add update links from image backfill results
  imageUpdateLinks <- catMaybes <$> traverse (\filePath -> do
        title <- extractTitleFromFile (vaultDir </> T.unpack filePath)
        case (mkRelativePath filePath, mkTitle title) of
          (Right relativePath, Right validTitle) ->
            pure (Just (UpdateLink relativePath validTitle [ImageAdded]))
          (Left pathError, _) -> do
            logMsg $ "  ⚠️  Skipping update link for " <> filePath <> ": " <> pathError
            pure Nothing
          (_, Left titleError) -> do
            logMsg $ "  ⚠️  Skipping update link for " <> filePath <> ": " <> titleError
            pure Nothing
        ) imageModifiedFiles
  case imageUpdateLinks of
    [] -> pure ()
    _  -> do
      _ <- addUpdateLinksToReflection vaultDir today imageUpdateLinks
      pure ()

  -- 5. Link AI blog posts to their date's reflection with a dedicated AI Blog section
  --    Filter out future dates to avoid creating reflections ahead of Pacific time
  aiBlogLinks <- buildReflectionLinks aiBlogDir navResults
  let todayLinks = filter (\(_, _, date) -> date <= todayText) aiBlogLinks
  mapM_ (\(relPath, title, date) -> do
    let filename = T.drop (T.length "ai-blog/") relPath
    result <- updateDailyReflection vaultDir date aiBlogConfig filename title Nothing
    case result of
      _ | urrLinkInserted result ->
            logMsg $ "  🤖 Added AI blog link to " <> date <> " reflection: " <> relPath
        | otherwise -> pure ()
    ) todayLinks

  logMsg "✅ backfill-blog-images"

runInternalLinking :: Context.AppContext -> IO ()
runInternalLinking context = do
  let manager = Context.httpManager context
      vaultDir = Context.vaultDir context
  logMsg "▶️  internal-linking"

  envModel <- lookupEnvText "INTERNAL_LINKING_MODEL"
  let model = maybe IL.defaultLinkingModel Gemini.modelFromText envModel
  result <- IL.run manager model vaultDir
  logMsg $ "  🔗 Internal linking: "
        <> T.pack (show (IL.filesVisited result)) <> " visited, "
        <> T.pack (show (IL.filesModified result)) <> " modified, "
        <> T.pack (show (IL.totalLinksAdded result)) <> " links added"

  -- Add update links to daily reflection for modified files
  let modifiedResults = filter IL.modified (IL.fileResults result)
  case modifiedResults of
    [] -> pure ()
    _  -> do
      today <- todayPacificDay
      links <- catMaybes <$> traverse (\fr -> do
        title <- extractTitleFromFile (vaultDir </> T.unpack (unRelativePath (IL.relativePath fr)))
        case mkTitle title of
          Right validTitle -> pure (Just (UpdateLink (IL.relativePath fr) validTitle [InternalLinksAdded (IL.linksAdded fr)]))
          Left titleError -> do
            logMsg $ "  ⚠️  Skipping update link: " <> titleError
            pure Nothing
        ) modifiedResults
      _ <- addUpdateLinksToReflection vaultDir today links
      pure ()

  logMsg "✅ internal-linking"

runSocialPosting :: Context.AppContext -> [ContentDirectory] -> IO ()
runSocialPosting context contentDirs = do
  logMsg "▶️  social-posting"
  autoPost (Context.httpManager context) (Context.vaultDir context) contentDirs
  logMsg "✅ social-posting"

runAiFiction :: Context.AppContext -> IO ()
runAiFiction context = do
  let vaultDir = Context.vaultDir context
  logMsg "▶️  ai-fiction"

  today <- todayPacificDay
  let todayText = formatDay today

  let reflectionsDir = vaultDir </> "reflections"
      reflectionPath = reflectionsDir </> T.unpack todayText <> ".md"

  exists <- doesFileExist reflectionPath
  if not exists
    then do
      logMsg $ "  📭 No reflection for " <> todayText <> ", skipping AI fiction"
      logMsg "✅ ai-fiction (skipped)"
    else do
      noteContent <- TIO.readFile reflectionPath
      if not (reflectionNeedsFiction noteContent)
        then do
          logMsg $ "  ✅ Reflection " <> todayText <> " already has AI fiction"
          logMsg "✅ ai-fiction (already done)"
        else do
          -- Build model chain
          envModel <- lookupEnvText "FICTION_MODEL"
          let defaultChain = defaultFictionModel :| [Gemini.Gemini25FlashLite, Gemini.Gemini31FlashLite]
              models = Gemini.overrideModelChain envModel defaultChain

          let config = FictionConfig
                { fcModels = models
                , fcNoteContent = noteContent
                }

          result <- generateFiction config (callGeminiForGenerator context)

          let wordCount = length (T.words (frFiction result))
          logMsg $ "  🤖🐲 Generated fiction (model=" <> frModel result <> ", " <> T.pack (show wordCount) <> " words)"

          TIO.writeFile reflectionPath (frUpdatedContent result)
          logMsg $ "  ✏️  Updated " <> todayText <> ".md with AI fiction"

          logMsg "✅ ai-fiction"

runReflectionTitle :: Context.AppContext -> IO ()
runReflectionTitle context = do
  logMsg "▶️  reflection-title"

  today <- todayPacificDay
  let todayText = formatDay today
  yesterday <- formatDay <$> yesterdayPacificDay

  -- Try today first, then yesterday
  todayDone <- tryTitleForDate context todayText
  if todayDone
    then pure ()
    else do
      logMsg $ "  📅 Checking yesterday (" <> yesterday <> ")..."
      _ <- tryTitleForDate context yesterday
      pure ()

  logMsg "✅ reflection-title"

tryTitleForDate :: Context.AppContext -> Text -> IO Bool
tryTitleForDate context date = do
  let reflectionsDir = Context.vaultDir context </> "reflections"
      reflectionPath = reflectionsDir </> T.unpack date <> ".md"

  exists <- doesFileExist reflectionPath
  if not exists
    then do
      logMsg $ "  ⏭️  No reflection note for " <> date
      pure False
    else do
      content <- TIO.readFile reflectionPath
      if not (reflectionNeedsTitle content date)
        then do
          logMsg $ "  ⏭️  Reflection title already set for " <> date
          pure False
        else do
          recentTitles <- extractRecentCreativeTitles reflectionsDir date
          logMsg $ "  📋 Found " <> T.pack (show (length recentTitles)) <> " recent titles for style reference"

          -- Build model chain
          envModel <- lookupEnvText "REFLECTION_TITLE_MODEL"
          let defaultChain = defaultTitleModel :| [Gemini.Gemini25FlashLite, Gemini.Gemini31FlashLite]
              models = Gemini.overrideModelChain envModel defaultChain

          let config = ReflectionTitleConfig
                { rtcModels = models
                , rtcNoteContent = content
                , rtcDate = date
                , rtcRecentTitles = recentTitles
                }

          result <- generateReflectionTitle config (callGeminiForGenerator context)

          logMsg $ "  🏷️  Generated title: " <> rtrFullTitle result <> " [" <> rtrModel result <> "]"

          TIO.writeFile reflectionPath (rtrUpdatedContent result)
          logMsg $ "  🏷️  Title written for " <> date
          pure True

runDailyAnalytics :: Context.AppContext -> IO ()
runDailyAnalytics context = do
  let manager = Context.httpManager context
      vaultDir = Context.vaultDir context
  logMsg "▶️  daily-analytics"

  mPropertyId <- lookupEnvText "GA_PROPERTY_ID"
  mServiceAccountJson <- lookupEnvText "GCP_SERVICE_ACCOUNT_KEY"

  case (mPropertyId, mServiceAccountJson) of
    (Nothing, _) -> do
      logMsg "  ⚠️  GA_PROPERTY_ID not set — daily analytics disabled"
      logMsg "✅ daily-analytics (disabled)"
    (_, Nothing) -> do
      logMsg "  ⚠️  GCP_SERVICE_ACCOUNT_KEY not set — daily analytics disabled"
      logMsg "✅ daily-analytics (disabled)"
    (Just propertyId, Just serviceAccountJson) -> do
      case GcpAuth.parseServiceAccountKey serviceAccountJson of
        Left err -> do
          logMsg $ "  ❌ Failed to parse service account key: " <> err
          logMsg "✅ daily-analytics (error)"
        Right serviceAccount -> do
          logMsg $ "  🔑 Service account: " <> GcpAuth.sakClientEmail serviceAccount
          tokenResult <- GcpAuth.getAccessTokenWithScope GA.analyticsReadonlyScope manager serviceAccount
          case tokenResult of
            Left err -> do
              logMsg $ "  ❌ Failed to get access token: " <> err
              logMsg "✅ daily-analytics (error)"
            Right accessToken -> do
              logMsg "  🔓 Access token obtained"
              yesterday <- yesterdayPacificDay
              let yesterdayText = formatDay yesterday
                  reflectionsDir = vaultDir </> "reflections"
                  reflectionPath = reflectionsDir </> T.unpack yesterdayText <> ".md"
                  endpoint = GA.analyticsApiEndpoint propertyId

              logMsg $ "  📅 Fetching analytics for: " <> yesterdayText
              logMsg $ "  🔗 GA4 property: " <> propertyId
              logMsg $ "  🌐 API endpoint: " <> endpoint

              exists <- doesFileExist reflectionPath
              if not exists
                then do
                  logMsg $ "  📭 No reflection for " <> yesterdayText <> ", skipping analytics"
                  logMsg "✅ daily-analytics (skipped)"
                else do
                  noteContent <- TIO.readFile reflectionPath
                  if not (GA.reflectionNeedsAnalytics noteContent)
                    then do
                      logMsg $ "  ✅ Reflection " <> yesterdayText <> " already has analytics"
                      logMsg "✅ daily-analytics (already done)"
                    else do
                      logMsg "  📡 Calling GA4 Data API for summary metrics..."
                      summaryResult <- fetchAnalytics manager accessToken endpoint (GA.buildSummaryRequestBody yesterdayText)
                      logMsg "  📡 Calling GA4 Data API for top pages..."
                      pagesResult <- fetchAnalytics manager accessToken endpoint (GA.buildTopPagesRequestBody yesterdayText)

                      case (summaryResult, pagesResult) of
                        (Left err, _) -> do
                          logMsg $ "  ❌ Summary API error: " <> err
                          logMsg "✅ daily-analytics (error)"
                        (_, Left err) -> do
                          logMsg $ "  ❌ Top pages API error: " <> err
                          logMsg "✅ daily-analytics (error)"
                        (Right summaryJson, Right pagesJson) -> do
                          logMsg $ "  📦 Summary response rows: " <> T.pack (show (GA.extractRowCount summaryJson))
                          logMsg $ "  📦 Pages response rows: " <> T.pack (show (GA.extractRowCount pagesJson))
                          case (GA.parseSummaryResponse summaryJson, GA.parseAnalyticsResponse pagesJson) of
                            (Left err, _) -> do
                              logMsg $ "  ❌ Parse summary error: " <> err
                              logMsg "✅ daily-analytics (error)"
                            (_, Left err) -> do
                              logMsg $ "  ❌ Parse pages error: " <> err
                              logMsg "✅ daily-analytics (error)"
                            (Right summary, Right pages) -> do
                              let report = GA.AnalyticsReport summary pages
                                  updatedContent = GA.applyAnalyticsSection noteContent report
                              TIO.writeFile reflectionPath updatedContent
                              logMsg $ "  📊 Analytics for " <> yesterdayText <> ": "
                                    <> T.pack (show (GA.activeUsers summary)) <> " users, "
                                    <> T.pack (show (GA.pageViews summary)) <> " views, "
                                    <> T.pack (show (GA.sessions summary)) <> " sessions"
                              logMsg $ "  📊 Top pages: " <> T.pack (show (length pages))
                              logMsg "✅ daily-analytics"

fetchAnalytics :: HTTP.Manager -> Text -> Text -> Json.Value -> IO (Either Text Json.Value)
fetchAnalytics manager accessToken endpoint body = do
  let bodyBytes = Json.encode body
  initReq <- HTTP.parseRequest (T.unpack endpoint)
  let httpReq = initReq
        { HTTP.method = "POST"
        , HTTP.requestBody = HTTP.RequestBodyLBS bodyBytes
        , HTTP.requestHeaders =
            [ ("Authorization", "Bearer " <> TE.encodeUtf8 accessToken)
            , ("Content-Type", "application/json")
            ]
        }
  response <- HTTP.httpLbs httpReq manager
  let responseBytes = HTTP.responseBody response
      status = statusCode (HTTP.responseStatus response)
  logMsg $ "  📬 GA4 API response: HTTP " <> T.pack (show status) <> ", " <> T.pack (show (LBS.length responseBytes)) <> " bytes"
  case status of
    200 ->
      case Json.eitherDecode responseBytes of
        Right val -> pure $ Right val
        Left err -> pure $ Left $ "GA API JSON parse error: " <> T.pack err
          <> " — response: " <> TE.decodeUtf8 (LBS.toStrict (LBS.take 500 responseBytes))
    _ -> pure $ Left $ "GA API HTTP " <> T.pack (show status)
      <> ": " <> TE.decodeUtf8 (LBS.toStrict (LBS.take 1000 responseBytes))

taskRunners :: Context.AppContext -> Map Text BlogSeriesConfig -> Map Text BlogSeriesRunConfig -> [ContentDirectory] -> [DiscoveredSeries] -> Map TaskId (IO ())
taskRunners context seriesMap runConfigs contentDirs discovered =
  let blogSeriesRunners = Map.fromList
        (fmap (\series -> (BlogSeries (dsId series), runBlogSeries context seriesMap runConfigs (dsId series))) discovered)
      staticRunners = Map.fromList
        [ (BackfillBlogImages, runBackfillImages context contentDirs)
        , (InternalLinking, runInternalLinking context)
        , (SocialPosting, runSocialPosting context contentDirs)
        , (AiFiction, runAiFiction context)
        , (ReflectionTitle, runReflectionTitle context)
        , (DailyAnalytics, runDailyAnalytics context)
        ]
  in Map.union blogSeriesRunners staticRunners

main :: IO ()
main = do
  hSetBuffering stdout LineBuffering

  args <- parseCliArgs <$> getArgs
  hourPacific <- maybe nowPacificHour pure (cliHourOverride args)

  -- Repo root: prefer REPO_ROOT env, then GITHUB_WORKSPACE, then "."
  mRepoRoot <- lookupEnv "REPO_ROOT"
  mWorkspace <- lookupEnv "GITHUB_WORKSPACE"
  let repoRoot = case mRepoRoot of
        Just r  -> r
        Nothing -> fromMaybe "." mWorkspace
  manager <- newManager tlsManagerSettings

  -- Discover blog series from JSON config files
  let haskellDir = repoRoot </> "haskell"
  discoveryResult <- discoverSeries haskellDir
  discovered <- case discoveryResult of
    Right series -> do
      logMsg $ "📋 Discovered " <> T.pack (show (length series)) <> " blog series: "
        <> T.intercalate ", " (fmap dsId series)
      pure series
    Left errors -> do
      TIO.hPutStrLn stderr "❌ Blog series discovery errors:"
      mapM_ (\case
        JsonParseError path err -> TIO.hPutStrLn stderr $ "  📄 " <> T.pack path <> ": " <> T.pack err
        ValidationError path msg -> TIO.hPutStrLn stderr $ "  ⚠️  " <> T.pack path <> ": " <> msg
        ) errors
      exitFailure

  let seriesConfigs = fmap deriveBlogSeriesConfig discovered
      seriesMap = Map.fromList (fmap (\config -> (bscId config, config)) seriesConfigs)
      runConfigs = buildBlogSeriesRunConfigs (fmap deriveBlogSeriesRunConfig discovered)
      dynamicScheduleEntries = fmap deriveScheduleEntry discovered
      fullSchedule = buildSchedule dynamicScheduleEntries
      contentDirs = imageBackfillContentDirsFrom seriesConfigs

  tasks <- case cliTaskOverride args of
    Just taskStr ->
      if isValidTaskId fullSchedule taskStr
        then case taskIdFromText (fmap seTaskId dynamicScheduleEntries) taskStr of
          Just tid -> pure [tid]
          Nothing  -> do
            TIO.hPutStrLn stderr $ "❌ Unknown task: " <> taskStr
            exitFailure
        else do
          TIO.hPutStrLn stderr $ "❌ Unknown task: " <> taskStr
          exitFailure
    Nothing -> pure $ getScheduledTasks fullSchedule hourPacific

  let taskNames = T.intercalate ", " (fmap taskIdToText tasks)
  logMsg $ "Scheduler start — hour " <> T.pack (show hourPacific) <> " Pacific, "
    <> T.pack (show (length tasks)) <> " task(s): " <> taskNames
  TIO.putStrLn "📊 Inference dashboards:"
  mapM_ (\(name, url) -> TIO.putStrLn $ "   " <> name <> ": " <> url) inferenceDashboards

  case tasks of
    [] -> do
      logMsg "  ⏭️  No tasks scheduled for this hour"
      pure ()
    _ -> do
      -- Pull vault ONCE at the start
      creds <- getObsidianCreds
      logMsg "📥 Pulling Obsidian vault..."
      vaultDir <- syncObsidianVault creds
      logMsg $ "📂 Vault ready at " <> T.pack vaultDir

      geminiApiKey <- Secret <$> requireEnv "GEMINI_API_KEY"
      context <- case Context.mkAppContext manager vaultDir repoRoot geminiApiKey creds of
        Right ctx -> pure ctx
        Left err -> do
          TIO.hPutStrLn stderr $ "❌ Invalid context: " <> T.pack err
          exitFailure
      let runners = taskRunners context seriesMap runConfigs contentDirs discovered
      results <- runTasks runners tasks

      -- Push vault ONCE at the end
      logMsg "📤 Pushing Obsidian vault..."
      pushObsidianVault vaultDir (ocAuthToken creds)
      logMsg "📤 Vault pushed"

      let succeeded = length (filter (\(_, success, _) -> success) results)
          total = length results

      TIO.putStrLn "\n--- Run Summary ---"
      mapM_ (\(taskIdentifier, success, errorMessage) ->
        let icon = if success then "✅" else "❌"
            errorSuffix = maybe "" (" — " <>) errorMessage
        in TIO.putStrLn $ "  " <> icon <> " " <> taskIdToText taskIdentifier <> errorSuffix
        ) results
      TIO.putStrLn $ "  📊 " <> T.pack (show succeeded) <> "/" <> T.pack (show total) <> " succeeded"
      TIO.putStrLn "-------------------\n"
