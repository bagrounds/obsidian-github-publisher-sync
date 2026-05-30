module Automation.TaskRunners
  ( taskRunners
  , runBlogSeries
  , runBackfillImages
  , runInternalLinking
  , runSocialPosting
  , runAiFiction
  , runReflectionTitle
  , runDailyAnalytics
  ) where

import Control.Exception (SomeException, try)
import Control.Monad (when)
import Data.List.NonEmpty (NonEmpty ((:|)))
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (catMaybes, fromMaybe)
import qualified Data.ByteString.Lazy as LBS
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Text.IO as TIO
import qualified Network.HTTP.Client as HTTP
import Network.HTTP.Types.Status (statusCode)
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, doesFileExist, listDirectory, removeFile)
import System.FilePath ((</>), dropExtension)
import Data.Time (Day, defaultTimeLocale, parseTimeM, getCurrentTime)

import Automation.AiBlogLinks (NavLinkResult (modified), aiBlogConfig, ensureAllNavLinks, buildReflectionLinks)
import qualified Automation.AiFiction as AiFiction
import Automation.AiFiction
  ( fictionEligibilityCutoff
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
  , lookupSeriesIn
  )
import Automation.BlogSeriesDiscovery (AutoBlogSeries (..))
import qualified Automation.Context as Context
import Automation.DailyReflection (UpdateReflectionResult (..), updateDailyReflection)
import Automation.DailyUpdates (UpdateDetail (..), UpdateLink (..), addUpdateLinksToReflection, extractTitleFromFile)
import Automation.Env (buildEnvMap, lookupEnvText)
import qualified Automation.GcpAuth as GcpAuth
import qualified Automation.Gemini as Gemini
import qualified Automation.GoogleAnalytics as GA
import qualified Automation.InternalLinking as IL
import qualified Automation.Json as Json
import Automation.PacificTime (formatDay, toPacificLocalTime, todayPacificDay, yesterdayPacificDay)
import Automation.Reflection (eligibleReflectionDays)
import qualified Automation.ReflectionTitle as ReflectionTitle
import Automation.ReflectionTitle
  ( defaultTitleModel
  , extractCreativeTitle
  , filterRecentReflectionFiles
  , generateReflectionTitle
  , reflectionNeedsTitle
  , reflectionTitleCutoff
  )
import Automation.RelativePath (unRelativePath, mkRelativePath)
import Automation.Scheduler
  ( TaskId (..)
  , blogPostExistsForToday
  , findPostToRegenerate
  )
import qualified Automation.Scheduler as Scheduler
import Automation.SocialPosting (autoPost)
import Automation.TaskRunner (logMessage, failTask)
import Automation.Text (stripCodeFences)
import Automation.Title (mkTitle)
import Automation.VaultSync (syncFileToVault, syncNewMarkdownFiles, copySeriesPosts, syncRepoPostsToVault, ensureFileInVault)
import Automation.Wikilink (buildBackLink)

callGeminiForGenerator :: Context.AppContext -> NonEmpty Gemini.Model -> (Text, Text) -> IO (Text, Text)
callGeminiForGenerator context models (systemPrompt, userPrompt) = do
  let config = Gemini.defaultGenerationConfig { Gemini.temperature = 0.9, Gemini.maxOutputTokens = 2048 }
  result <- Gemini.generateContentWithFallback (Context.httpManager context) models (Just systemPrompt) userPrompt (Context.geminiApiKey context) config
  case result of
    Left failure -> failTask $ "Gemini API error: " <> T.pack (show failure)
    Right response -> pure (Gemini.responseText response, Gemini.modelToText (Gemini.responseModel response))

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

runBlogSeries :: Context.AppContext -> Map Text BlogSeriesConfig -> Map Text Scheduler.BlogSeriesRunConfig -> Text -> IO ()
runBlogSeries context seriesMap runConfigs seriesId = do
  let taskName = "blog-series:" <> seriesId
      manager = Context.httpManager context
      repoRoot = Context.repoRoot context
      vaultDir = Context.vaultDir context
      apiKey = Context.geminiApiKey context
  logMessage $ "▶️  " <> taskName

  runConfig <- case Map.lookup seriesId runConfigs of
    Just config -> pure config
    Nothing -> failTask $ "No run config for series: " <> seriesId

  today <- todayPacificDay
  let todayText = formatDay today
  _ <- copySeriesPosts vaultDir seriesId repoRoot

  series <- either failTask pure (lookupSeriesIn seriesMap seriesId)
  let agentsRelPath = T.unpack seriesId </> "AGENTS.md"
  _ <- syncFileToVault (repoRoot </> agentsRelPath) agentsRelPath vaultDir
  let vaultIndexPath = vaultDir </> T.unpack seriesId </> "index.md"
  indexCreated <- ensureFileInVault vaultIndexPath (generateSeriesIndex series)
  when indexCreated $ logMessage $ "  📋 Created index.md for " <> seriesId
  _ <- syncRepoPostsToVault repoRoot seriesId vaultDir logMessage

  let seriesDir = repoRoot </> T.unpack seriesId
  maybeRegenPost <- findPostToRegenerate seriesDir todayText
  case maybeRegenPost of
    Just postToRegen -> do
      logMessage $ "  ♻️  Regeneration requested for " <> T.pack postToRegen <> " — removing old post"
      removeFile (seriesDir </> postToRegen)
    Nothing -> do
      existsForToday <- blogPostExistsForToday seriesDir todayText
      when existsForToday $
        logMessage $ "  ⏭️  Already generated for " <> todayText

  existsNow <- blogPostExistsForToday seriesDir todayText
  case (maybeRegenPost, existsNow) of
    (Nothing, True) -> pure ()
    _ -> do
      envModel <- lookupEnvText "BLOG_GEMINI_MODEL"
      let models = Gemini.overrideModelChain envModel (Scheduler.modelChain runConfig)

      priorityUser <- lookupEnvText (T.unpack (Scheduler.priorityUserEnvVar runConfig))

      comments <- fetchAllSeriesComments manager seriesId (priorityUser >>= (\u -> if T.null u then Nothing else Just u))
      logMessage $ "  📝 Fetched " <> T.pack (show (length comments)) <> " comments"

      blogContextResult <- buildBlogContext seriesMap seriesId repoRoot comments today
      case blogContextResult of
        Left reason -> failTask $ "Blog context build failed: " <> reason
        Right blogContext -> do
          let (systemPrompt, userPrompt) = buildBlogPrompt blogContext
              genConfig = Gemini.defaultGenerationConfig
                { Gemini.temperature = 0.9, Gemini.maxOutputTokens = 8192
                , Gemini.searchGrounding = Scheduler.searchGrounding runConfig
                }

          result <- Gemini.generateContentWithFallback manager models (Just systemPrompt) userPrompt apiKey genConfig
          case result of
            Left failure -> failTask $ "Blog generation failed: " <> T.pack (show failure)
            Right response -> do
              let rawText = stripCodeFences (Gemini.responseText response)
                  usedModel = Gemini.modelToText (Gemini.responseModel response)
                  groundingSources = Gemini.responseGroundingSources response
              when (containsSystemPrompt systemPrompt rawText) $
                failTask "Generated post echoes the system prompt (AGENTS.md) — rejecting"
              case parseGeneratedPost rawText of
                Nothing -> failTask "Failed to parse generated blog post"
                Just (body, rawTitle) -> do
                  let title = sanitizeTitle series rawTitle
                      slugText = generateSlug title
                  slug <- either (\slugError -> failTask $ "Invalid slug: " <> slugError) pure (mkSlug slugText)
                  let newPostFilename = todayText <> "-" <> unSlug slug <> ".md"

                  posts <- readSeriesPosts seriesDir
                  let previousPost = case posts of
                        (p:_) -> Just p
                        []    -> Nothing

                  let frontmatter = assembleFrontmatter series today title slug
                      backLink = case previousPost of
                        Just post -> " | " <> buildBackLink series (filename post)
                        Nothing -> ""
                      navLine = navLink series <> backLink
                      displayTitle = unDisplayTitle $ buildDisplayTitle series today title
                      header = navLine <> "\n# " <> displayTitle <> "\n\n"
                      maybeSourcesSection = Gemini.formatGroundingSources groundingSources
                      bodyWithSig = appendModelSignature body usedModel
                  if null groundingSources
                    then when (Scheduler.searchGrounding runConfig) $
                      logMessage $ "  ⚠️  Grounding was requested but " <> usedModel <> " returned no sources"
                    else logMessage $ "  🔍 Embedded " <> T.pack (show (length groundingSources)) <> " grounding sources"
                  createDirectoryIfMissing True seriesDir
                  let postPath = seriesDir </> T.unpack newPostFilename
                  TIO.writeFile postPath (frontmatter <> "\n" <> header <> bodyWithSig <> fromMaybe "" maybeSourcesSection <> "\n")
                  logMessage $ "  ✅ Written: " <> newPostFilename <> " [" <> usedModel <> "]"

                  let attachmentsDir = repoRoot </> "attachments"
                  imageEnvMap <- buildEnvMap
                    [ "GEMINI_API_KEY", "CLOUDFLARE_API_TOKEN", "CLOUDFLARE_ACCOUNT_ID"
                    , "CLOUDFLARE_IMAGE_MODEL", "HUGGINGFACE_API_TOKEN", "HUGGINGFACE_IMAGE_MODEL"
                    , "TOGETHER_API_TOKEN", "TOGETHER_IMAGE_MODEL", "POLLINATIONS_ENABLED"
                    , "POLLINATIONS_IMAGE_MODEL", "PROMPT_DESCRIBER_MODEL", "IMAGE_GEMINI_MODEL"
                    ]
                  let imageProviders = resolveImageProviders imageEnvMap
                  case imageProviders of
                    [] -> logMessage "  ⚠️  No image providers configured, skipping image generation"
                    (provider : _) -> do
                      imageResult <- try (processNote manager provider postPath attachmentsDir) :: IO (Either SomeException ImageGenerationResult)
                      case imageResult of
                        Right _ -> logMessage $ "  🖼️  Image generated for " <> newPostFilename
                        Left failure -> logMessage $ "  ⚠️  Image generation failed for " <> newPostFilename <> ": " <> T.pack (show failure)

                  case previousPost of
                    Just post -> updatePreviousPost (vaultDir </> T.unpack seriesId) post series newPostFilename
                    Nothing -> pure ()

                  let metadataPath = seriesDir </> ".last-generate-metadata.json"
                  case previousPost of
                    Just post -> TIO.writeFile metadataPath $
                      "{\"previousPostFilename\":\"" <> filename post <> "\",\"newPostFilename\":\"" <> newPostFilename <> "\"}"
                    Nothing -> pure ()

                  let filenameNoExt = T.pack $ dropExtension $ T.unpack newPostFilename
                      regenFilenameNoExt = case maybeRegenPost of
                        Just r  -> Just (T.pack (dropExtension r))
                        Nothing -> Nothing
                  postTitle <- either (\e -> failTask $ "Invalid display title: " <> e) pure (mkTitle displayTitle)
                  _ <- updateDailyReflection vaultDir today series filenameNoExt postTitle regenFilenameNoExt

                  let postRelPath = T.unpack seriesId </> T.unpack newPostFilename
                      postLocalPath = repoRoot </> postRelPath
                  _ <- syncFileToVault postLocalPath postRelPath vaultDir

                  syncAttachmentsDir (repoRoot </> "attachments") (vaultDir </> "attachments")
                  pure ()

  logMessage $ "✅ " <> taskName

runBackfillImages :: Context.AppContext -> [ContentDirectory] -> IO ()
runBackfillImages context contentDirs = do
  let manager = Context.httpManager context
      repoRoot = Context.repoRoot context
      vaultDir = Context.vaultDir context
  logMessage "▶️  backfill-blog-images"

  today <- todayPacificDay
  let todayText = formatDay today

  let repoAiBlogDir = repoRoot </> "ai-blog"
      vaultAiBlogDir = vaultDir </> "ai-blog"
      repoToolsDir = repoRoot </> "tools"
      vaultToolsDir = vaultDir </> "tools"
  newPostCount <- syncNewMarkdownFiles repoAiBlogDir vaultAiBlogDir logMessage
  case newPostCount of
    0 -> pure ()
    count -> logMessage $ "  📝 Synced " <> T.pack (show count) <> " new AI blog post(s) to vault"
  newToolCount <- syncNewMarkdownFiles repoToolsDir vaultToolsDir logMessage
  case newToolCount of
    0 -> pure ()
    count -> logMessage $ "  🧰 Synced " <> T.pack (show count) <> " new tool page(s) to vault"

  envMap <- buildEnvMap
    [ "GEMINI_API_KEY", "CLOUDFLARE_API_TOKEN", "CLOUDFLARE_ACCOUNT_ID"
    , "CLOUDFLARE_IMAGE_MODEL", "HUGGINGFACE_API_TOKEN", "HUGGINGFACE_IMAGE_MODEL"
    , "TOGETHER_API_TOKEN", "TOGETHER_IMAGE_MODEL", "POLLINATIONS_ENABLED"
    , "POLLINATIONS_IMAGE_MODEL", "PROMPT_DESCRIBER_MODEL", "IMAGE_GEMINI_MODEL"
    ]
  let providers = resolveImageProviders envMap
  imageModifiedFiles <- case providers of
    [] -> do
      logMessage "  ⚠️  No image providers configured, skipping image backfill"
      pure []
    _  -> do
      logMessage $ "  🎨 Image providers: " <> T.pack (show (length providers))
      let backfillConfig = BackfillConfig
            { backfillRepoRoot = vaultDir
            , backfillContentDirs = contentDirs
            , backfillAttachmentsDir = vaultDir </> "attachments"
            , backfillProviders = providers
            , backfillMaxImages = 2
            }
      result <- backfillImages manager backfillConfig
      logMessage $ "  🖼️  Images: " <> T.pack (show (imagesGenerated result))
            <> "/" <> T.pack (show (backfillMaxImages backfillConfig))
            <> " generated, " <> T.pack (show (filesUpdated result))
            <> " files updated, " <> T.pack (show (filesSkipped result)) <> " skipped"
      case errors result of
        [] -> pure ()
        errs -> logMessage $ "  ⚠️  Errors: " <> T.intercalate "; " errs
      pure (modifiedFiles result)

  let aiBlogDir = vaultDir </> "ai-blog"
  navResults <- ensureAllNavLinks aiBlogDir
  let modifiedCount = length (filter modified navResults)
  logMessage $ "  🔗 Nav links: " <> T.pack (show modifiedCount) <> " files updated"

  imageUpdateLinks <- catMaybes <$> traverse (\filePath -> do
        title <- extractTitleFromFile (vaultDir </> T.unpack filePath)
        case (mkRelativePath filePath, mkTitle title) of
          (Right relativePath, Right validTitle) ->
            pure (Just (UpdateLink relativePath validTitle [ImageAdded]))
          (Left pathError, _) -> do
            logMessage $ "  ⚠️  Skipping update link for " <> filePath <> ": " <> pathError
            pure Nothing
          (_, Left titleError) -> do
            logMessage $ "  ⚠️  Skipping update link for " <> filePath <> ": " <> titleError
            pure Nothing
        ) imageModifiedFiles
  case imageUpdateLinks of
    [] -> pure ()
    _  -> do
      _ <- addUpdateLinksToReflection vaultDir today imageUpdateLinks
      pure ()

  aiBlogLinks <- buildReflectionLinks aiBlogDir navResults
  let todayLinks = filter (\(_, _, dateText) -> dateText <= todayText) aiBlogLinks
  mapM_ (\(relPath, title, dateText) -> do
    case parseTimeM True defaultTimeLocale "%Y-%m-%d" (T.unpack dateText) of
      Nothing -> logMessage $ "  ⚠️  Skipping AI blog link with unparseable date (expected YYYY-MM-DD): " <> dateText
      Just day -> do
        let filename = T.drop (T.length "ai-blog/") relPath
        result <- updateDailyReflection vaultDir day aiBlogConfig filename title Nothing
        case result of
          _ | urrLinkInserted result ->
                logMessage $ "  🤖 Added AI blog link to " <> dateText <> " reflection: " <> relPath
            | otherwise -> pure ()
    ) todayLinks

  logMessage "✅ backfill-blog-images"

runInternalLinking :: Context.AppContext -> IO ()
runInternalLinking context = do
  let manager = Context.httpManager context
      vaultDir = Context.vaultDir context
  logMessage "▶️  internal-linking"

  envModel <- lookupEnvText "INTERNAL_LINKING_MODEL"
  let model = maybe IL.defaultLinkingModel Gemini.modelFromText envModel
  result <- IL.run manager model vaultDir
  logMessage $ "  🔗 Internal linking: "
        <> T.pack (show (IL.filesVisited result)) <> " visited, "
        <> T.pack (show (IL.filesModified result)) <> " modified, "
        <> T.pack (show (IL.totalLinksAdded result)) <> " links added"

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
            logMessage $ "  ⚠️  Skipping update link: " <> titleError
            pure Nothing
        ) modifiedResults
      _ <- addUpdateLinksToReflection vaultDir today links
      pure ()

  logMessage "✅ internal-linking"

runSocialPosting :: Context.AppContext -> [ContentDirectory] -> IO ()
runSocialPosting context contentDirs = do
  logMessage "▶️  social-posting"
  autoPost (Context.httpManager context) (Context.vaultDir context) contentDirs
  logMessage "✅ social-posting"

runAiFiction :: Context.AppContext -> IO ()
runAiFiction context = do
  logMessage "▶️  ai-fiction"

  now <- getCurrentTime
  let localNow = toPacificLocalTime now
      eligibleDays = eligibleReflectionDays localNow fictionEligibilityCutoff

  logMessage $ "  🕐 Pacific time: " <> T.pack (show localNow) <> " — " <> T.pack (show (length eligibleDays)) <> " eligible day(s) to check"

  mapM_ (tryFictionForDate context) eligibleDays

  logMessage "✅ ai-fiction"

tryFictionForDate :: Context.AppContext -> Day -> IO ()
tryFictionForDate context day = do
  let vaultDir = Context.vaultDir context
      dateText = formatDay day
      reflectionsDir = vaultDir </> "reflections"
      reflectionPath = reflectionsDir </> T.unpack dateText <> ".md"

  exists <- doesFileExist reflectionPath
  if not exists
    then logMessage $ "  ⏭️  No reflection note for " <> dateText
    else do
      noteContent <- TIO.readFile reflectionPath
      if not (reflectionNeedsFiction noteContent)
        then logMessage $ "  ⏭️  AI fiction already present for " <> dateText
        else do
          envModel <- lookupEnvText "FICTION_MODEL"
          let dayChain = AiFiction.selectFictionModelChain day AiFiction.fictionModelPool
              models = Gemini.overrideModelChain envModel dayChain

          let config = AiFiction.FictionConfig
                { AiFiction.models = models
                , AiFiction.noteContent = noteContent
                }

          result <- generateFiction config (callGeminiForGenerator context)

          let wordCount = length (T.words (AiFiction.fiction result))
          logMessage $ "  🤖🐲 Generated fiction (model=" <> AiFiction.model result <> ", " <> T.pack (show wordCount) <> " words)"

          TIO.writeFile reflectionPath (AiFiction.updatedContent result)
          logMessage $ "  ✏️  Updated " <> dateText <> ".md with AI fiction"

runReflectionTitle :: Context.AppContext -> IO ()
runReflectionTitle context = do
  logMessage "▶️  reflection-title"

  now <- getCurrentTime
  let localNow = toPacificLocalTime now
      eligibleDays = eligibleReflectionDays localNow reflectionTitleCutoff

  logMessage $ "  🕐 Pacific time: " <> T.pack (show localNow) <> " — " <> T.pack (show (length eligibleDays)) <> " eligible day(s) to check"

  mapM_ (tryTitleForDate context . formatDay) eligibleDays

  logMessage "✅ reflection-title"

tryTitleForDate :: Context.AppContext -> Text -> IO Bool
tryTitleForDate context date = do
  let reflectionsDir = Context.vaultDir context </> "reflections"
      reflectionPath = reflectionsDir </> T.unpack date <> ".md"

  exists <- doesFileExist reflectionPath
  if not exists
    then do
      logMessage $ "  ⏭️  No reflection note for " <> date
      pure False
    else do
      content <- TIO.readFile reflectionPath
      if not (reflectionNeedsTitle content date)
        then do
          logMessage $ "  ⏭️  Reflection title already set for " <> date
          pure False
        else do
          recentTitles <- extractRecentCreativeTitles reflectionsDir date
          logMessage $ "  📋 Found " <> T.pack (show (length recentTitles)) <> " recent titles for style reference"

          envModel <- lookupEnvText "REFLECTION_TITLE_MODEL"
          let defaultChain = defaultTitleModel :| [Gemini.Gemini25FlashLite, Gemini.Gemini31FlashLite]
              models = Gemini.overrideModelChain envModel defaultChain

          let config = ReflectionTitle.ReflectionTitleConfig
                { ReflectionTitle.models = models
                , ReflectionTitle.noteContent = content
                , ReflectionTitle.date = date
                , ReflectionTitle.recentTitles = recentTitles
                }

          result <- generateReflectionTitle config (callGeminiForGenerator context)

          logMessage $ "  🏷️  Generated title: " <> ReflectionTitle.fullTitle result <> " [" <> ReflectionTitle.model result <> "]"

          TIO.writeFile reflectionPath (ReflectionTitle.updatedContent result)
          logMessage $ "  🏷️  Title written for " <> date
          pure True

runDailyAnalytics :: Context.AppContext -> IO ()
runDailyAnalytics context = do
  let manager = Context.httpManager context
      vaultDir = Context.vaultDir context
  logMessage "▶️  daily-analytics"

  maybePropertyId <- lookupEnvText "GA_PROPERTY_ID"
  maybeServiceAccountJson <- lookupEnvText "GCP_SERVICE_ACCOUNT_KEY"

  case (maybePropertyId, maybeServiceAccountJson) of
    (Nothing, _) -> do
      logMessage "  ⚠️  GA_PROPERTY_ID not set — daily analytics disabled"
      logMessage "✅ daily-analytics (disabled)"
    (_, Nothing) -> do
      logMessage "  ⚠️  GCP_SERVICE_ACCOUNT_KEY not set — daily analytics disabled"
      logMessage "✅ daily-analytics (disabled)"
    (Just propertyId, Just serviceAccountJson) -> do
      case GcpAuth.parseServiceAccountKey serviceAccountJson of
        Left failure -> do
          logMessage $ "  ❌ Failed to parse service account key: " <> failure
          logMessage "✅ daily-analytics (error)"
        Right serviceAccount -> do
          logMessage $ "  🔑 Service account: " <> GcpAuth.clientEmail serviceAccount
          tokenResult <- GcpAuth.getAccessTokenWithScope GA.analyticsReadonlyScope manager serviceAccount
          case tokenResult of
            Left failure -> do
              logMessage $ "  ❌ Failed to get access token: " <> failure
              logMessage "✅ daily-analytics (error)"
            Right accessToken -> do
              logMessage "  🔓 Access token obtained"
              yesterday <- yesterdayPacificDay
              let yesterdayText = formatDay yesterday
                  reflectionsDir = vaultDir </> "reflections"
                  reflectionPath = reflectionsDir </> T.unpack yesterdayText <> ".md"
                  endpoint = GA.analyticsApiEndpoint propertyId

              logMessage $ "  📅 Fetching analytics for: " <> yesterdayText
              logMessage $ "  🔗 GA4 property: " <> propertyId
              logMessage $ "  🌐 API endpoint: " <> endpoint

              exists <- doesFileExist reflectionPath
              if not exists
                then do
                  logMessage $ "  📭 No reflection for " <> yesterdayText <> ", skipping analytics"
                  logMessage "✅ daily-analytics (skipped)"
                else do
                  noteContent <- TIO.readFile reflectionPath
                  if not (GA.reflectionNeedsAnalytics noteContent)
                    then do
                      logMessage $ "  ✅ Reflection " <> yesterdayText <> " already has analytics"
                      logMessage "✅ daily-analytics (already done)"
                    else do
                      logMessage "  📡 Calling GA4 Data API for summary metrics..."
                      summaryResult <- fetchAnalytics manager accessToken endpoint (GA.buildSummaryRequestBody yesterdayText)
                      logMessage "  📡 Calling GA4 Data API for top pages..."
                      pagesResult <- fetchAnalytics manager accessToken endpoint (GA.buildTopPagesRequestBody yesterdayText)

                      case (summaryResult, pagesResult) of
                        (Left failure, _) -> do
                          logMessage $ "  ❌ Summary API error: " <> failure
                          logMessage "✅ daily-analytics (error)"
                        (_, Left failure) -> do
                          logMessage $ "  ❌ Top pages API error: " <> failure
                          logMessage "✅ daily-analytics (error)"
                        (Right summaryJson, Right pagesJson) -> do
                          logMessage $ "  📦 Summary response rows: " <> T.pack (show (GA.extractRowCount summaryJson))
                          logMessage $ "  📦 Pages response rows: " <> T.pack (show (GA.extractRowCount pagesJson))
                          case (GA.parseSummaryResponse summaryJson, GA.parseAnalyticsResponse pagesJson) of
                            (Left failure, _) -> do
                              logMessage $ "  ❌ Parse summary error: " <> failure
                              logMessage "✅ daily-analytics (error)"
                            (_, Left failure) -> do
                              logMessage $ "  ❌ Parse pages error: " <> failure
                              logMessage "✅ daily-analytics (error)"
                            (Right summary, Right pages) -> do
                              enrichedPages <- traverse (enrichPageMetricWithTitle vaultDir) pages
                              let report = GA.AnalyticsReport summary enrichedPages
                                  updatedContent = GA.applyAnalyticsSection noteContent report
                              TIO.writeFile reflectionPath updatedContent
                              logMessage $ "  📊 Analytics for " <> yesterdayText <> ": "
                                    <> T.pack (show (GA.pageViews summary)) <> " views, "
                                    <> T.pack (show (GA.visitors summary)) <> " visitors, "
                                    <> GA.formatPercentage (GA.bounceRate summary) <> " bounce"
                              logMessage $ "  📊 Top pages: " <> T.pack (show (length enrichedPages))
                              logMessage "✅ daily-analytics"

enrichPageMetricWithTitle :: FilePath -> GA.PageMetric -> IO GA.PageMetric
enrichPageMetricWithTitle vaultDir metric = do
  let urlPath = GA.pagePath metric
      relativePath = GA.pathToWikilinkTarget urlPath
      filePath = vaultDir </> T.unpack relativePath <> ".md"
  exists <- doesFileExist filePath
  if exists
    then do
      title <- extractTitleFromFile filePath
      pure metric { GA.pageTitle = Just title }
    else pure metric

fetchAnalytics :: HTTP.Manager -> Text -> Text -> Json.Value -> IO (Either Text Json.Value)
fetchAnalytics manager accessToken endpoint body = do
  let bodyBytes = Json.encode body
  parsedRequest <- HTTP.parseRequest (T.unpack endpoint)
  let httpRequest = parsedRequest
        { HTTP.method = "POST"
        , HTTP.requestBody = HTTP.RequestBodyLBS bodyBytes
        , HTTP.requestHeaders =
            [ ("Authorization", "Bearer " <> TE.encodeUtf8 accessToken)
            , ("Content-Type", "application/json")
            ]
        }
  response <- HTTP.httpLbs httpRequest manager
  let responseBytes = HTTP.responseBody response
      status = statusCode (HTTP.responseStatus response)
  logMessage $ "  📬 GA4 API response: HTTP " <> T.pack (show status) <> ", " <> T.pack (show (LBS.length responseBytes)) <> " bytes"
  case status of
    200 ->
      case Json.eitherDecode responseBytes of
        Right val -> pure $ Right val
        Left failure -> pure $ Left $ "GA API JSON parse error: " <> T.pack failure
          <> " — response: " <> TE.decodeUtf8 (LBS.toStrict (LBS.take 500 responseBytes))
    _ -> pure $ Left $ "GA API HTTP " <> T.pack (show status)
      <> ": " <> TE.decodeUtf8 (LBS.toStrict (LBS.take 1000 responseBytes))

taskRunners :: Context.AppContext -> Map Text BlogSeriesConfig -> Map Text Scheduler.BlogSeriesRunConfig -> [ContentDirectory] -> [AutoBlogSeries] -> Map TaskId (IO ())
taskRunners context seriesMap runConfigs contentDirs discovered =
  let blogSeriesRunners = Map.fromList
        (fmap (\AutoBlogSeries{..} -> (BlogSeries seriesId, runBlogSeries context seriesMap runConfigs seriesId)) discovered)
      staticRunners = Map.fromList
        [ (BackfillBlogImages, runBackfillImages context contentDirs)
        , (InternalLinking, runInternalLinking context)
        , (SocialPosting, runSocialPosting context contentDirs)
        , (AiFiction, runAiFiction context)
        , (ReflectionTitle, runReflectionTitle context)
        , (DailyAnalytics, runDailyAnalytics context)
        ]
  in Map.union blogSeriesRunners staticRunners
