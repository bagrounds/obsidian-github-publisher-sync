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
import Control.Monad (when, unless)
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
import Data.Time (defaultTimeLocale, parseTimeM)

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
  , lookupSeriesIn
  )
import Automation.BlogSeriesDiscovery (DiscoveredSeries (..))
import qualified Automation.Context as Context
import Automation.DailyReflection (UpdateReflectionResult (..), updateDailyReflection)
import Automation.DailyUpdates (UpdateDetail (..), UpdateLink (..), addUpdateLinksToReflection, extractTitleFromFile)
import Automation.Env (buildEnvMap, lookupEnvText)
import qualified Automation.GcpAuth as GcpAuth
import qualified Automation.Gemini as Gemini
import qualified Automation.GoogleAnalytics as GA
import qualified Automation.InternalLinking as IL
import qualified Automation.Json as Json
import Automation.PacificTime (formatDay, todayPacificDay, yesterdayPacificDay)
import Automation.ReflectionTitle
  ( ReflectionTitleConfig (ReflectionTitleConfig, rtcModels, rtcNoteContent, rtcDate, rtcRecentTitles)
  , ReflectionTitleResult (rtrFullTitle, rtrModel, rtrUpdatedContent)
  , defaultTitleModel
  , extractCreativeTitle
  , filterRecentReflectionFiles
  , generateReflectionTitle
  , reflectionNeedsTitle
  )
import Automation.RelativePath (unRelativePath, mkRelativePath)
import Automation.Scheduler
  ( TaskId (..)
  , blogPostExistsForToday
  , findPostToRegenerate
  )
import qualified Automation.Scheduler as Scheduler
import Automation.SocialPosting (autoPost)
import Automation.TaskRunner (logMsg, failTask)
import Automation.Text (stripCodeFences)
import Automation.Title (mkTitle)
import Automation.VaultSync (syncFileToVault, syncNewAiBlogPosts, copySeriesPosts, syncRepoPostsToVault, ensureFileInVault)
import Automation.Wikilink (buildBackLink)

callGeminiForGenerator :: Context.AppContext -> NonEmpty Gemini.Model -> (Text, Text) -> IO (Text, Text)
callGeminiForGenerator context models (systemPrompt, userPrompt) = do
  let config = Gemini.defaultGenerationConfig { Gemini.temperature = 0.9, Gemini.maxOutputTokens = 2048 }
  result <- Gemini.generateContentWithFallback (Context.httpManager context) models (Just systemPrompt) userPrompt (Context.geminiApiKey context) config
  case result of
    Left err -> failTask $ "Gemini API error: " <> T.pack (show err)
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
  logMsg $ "▶️  " <> taskName

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
  when indexCreated $ logMsg $ "  📋 Created index.md for " <> seriesId
  _ <- syncRepoPostsToVault repoRoot seriesId vaultDir logMsg

  let seriesDir = repoRoot </> T.unpack seriesId
  maybeRegenPost <- findPostToRegenerate seriesDir todayText
  case maybeRegenPost of
    Just postToRegen -> do
      logMsg $ "  ♻️  Regeneration requested for " <> T.pack postToRegen <> " — removing old post"
      removeFile (seriesDir </> postToRegen)
    Nothing -> do
      existsForToday <- blogPostExistsForToday seriesDir todayText
      when existsForToday $
        logMsg $ "  ⏭️  Already generated for " <> todayText

  existsNow <- blogPostExistsForToday seriesDir todayText
  case (maybeRegenPost, existsNow) of
    (Nothing, True) -> pure ()
    _ -> do
      envModel <- lookupEnvText "BLOG_GEMINI_MODEL"
      let models = Gemini.overrideModelChain envModel (Scheduler.modelChain runConfig)

      priorityUser <- lookupEnvText (T.unpack (Scheduler.priorityUserEnvVar runConfig))

      comments <- fetchAllSeriesComments manager seriesId (priorityUser >>= (\u -> if T.null u then Nothing else Just u))
      logMsg $ "  📝 Fetched " <> T.pack (show (length comments)) <> " comments"

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
            Left err -> failTask $ "Blog generation failed: " <> T.pack (show err)
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
                  let filename = todayText <> "-" <> unSlug slug <> ".md"

                  posts <- readSeriesPosts seriesDir
                  let previousPost = case posts of
                        (p:_) -> Just p
                        []    -> Nothing

                  let frontmatter = assembleFrontmatter series today title slug
                      backLink = case previousPost of
                        Just post -> " | " <> buildBackLink series (bpFilename post)
                        Nothing -> ""
                      navLine = bscNavLink series <> backLink
                      displayTitle = unDisplayTitle $ buildDisplayTitle series today title
                      header = navLine <> "\n# " <> displayTitle <> "\n\n"
                      maybeSourcesSection = Gemini.formatGroundingSources groundingSources
                      bodyWithSig = appendModelSignature body usedModel
                  unless (null groundingSources) $
                    logMsg $ "  🔍 Embedded " <> T.pack (show (length groundingSources)) <> " grounding sources"
                  createDirectoryIfMissing True seriesDir
                  let postPath = seriesDir </> T.unpack filename
                  TIO.writeFile postPath (frontmatter <> "\n" <> header <> bodyWithSig <> fromMaybe "" maybeSourcesSection <> "\n")
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
                    Just post -> updatePreviousPost (vaultDir </> T.unpack seriesId) post series filename
                    Nothing -> pure ()

                  let metadataPath = seriesDir </> ".last-generate-metadata.json"
                  case previousPost of
                    Just post -> TIO.writeFile metadataPath $
                      "{\"previousPostFilename\":\"" <> bpFilename post <> "\",\"newPostFilename\":\"" <> filename <> "\"}"
                    Nothing -> pure ()

                  let filenameNoExt = T.pack $ dropExtension $ T.unpack filename
                      regenFilenameNoExt = case maybeRegenPost of
                        Just r  -> Just (T.pack (dropExtension r))
                        Nothing -> Nothing
                  postTitle <- either (\e -> failTask $ "Invalid display title: " <> e) pure (mkTitle displayTitle)
                  _ <- updateDailyReflection vaultDir today series filenameNoExt postTitle regenFilenameNoExt

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

  let repoAiBlogDir = repoRoot </> "ai-blog"
      vaultAiBlogDir = vaultDir </> "ai-blog"
  newPostCount <- syncNewAiBlogPosts repoAiBlogDir vaultAiBlogDir logMsg
  case newPostCount of
    0 -> pure ()
    count -> logMsg $ "  📝 Synced " <> T.pack (show count) <> " new AI blog post(s) to vault"

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

  let aiBlogDir = vaultDir </> "ai-blog"
  navResults <- ensureAllNavLinks aiBlogDir
  let modifiedCount = length (filter nlrModified navResults)
  logMsg $ "  🔗 Nav links: " <> T.pack (show modifiedCount) <> " files updated"

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

  aiBlogLinks <- buildReflectionLinks aiBlogDir navResults
  let todayLinks = filter (\(_, _, dateText) -> dateText <= todayText) aiBlogLinks
  mapM_ (\(relPath, title, dateText) -> do
    case parseTimeM True defaultTimeLocale "%Y-%m-%d" (T.unpack dateText) of
      Nothing -> logMsg $ "  ⚠️  Skipping AI blog link with unparseable date (expected YYYY-MM-DD): " <> dateText
      Just day -> do
        let filename = T.drop (T.length "ai-blog/") relPath
        result <- updateDailyReflection vaultDir day aiBlogConfig filename title Nothing
        case result of
          _ | urrLinkInserted result ->
                logMsg $ "  🤖 Added AI blog link to " <> dateText <> " reflection: " <> relPath
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

  maybePropertyId <- lookupEnvText "GA_PROPERTY_ID"
  maybeServiceAccountJson <- lookupEnvText "GCP_SERVICE_ACCOUNT_KEY"

  case (maybePropertyId, maybeServiceAccountJson) of
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
                              enrichedPages <- traverse (enrichPageMetricWithTitle vaultDir) pages
                              let report = GA.AnalyticsReport summary enrichedPages
                                  updatedContent = GA.applyAnalyticsSection noteContent report
                              TIO.writeFile reflectionPath updatedContent
                              logMsg $ "  📊 Analytics for " <> yesterdayText <> ": "
                                    <> T.pack (show (GA.pageViews summary)) <> " views, "
                                    <> T.pack (show (GA.visitors summary)) <> " visitors, "
                                    <> GA.formatPercentage (GA.bounceRate summary) <> " bounce"
                              logMsg $ "  📊 Top pages: " <> T.pack (show (length enrichedPages))
                              logMsg "✅ daily-analytics"

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
  let httpReq = parsedRequest
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

taskRunners :: Context.AppContext -> Map Text BlogSeriesConfig -> Map Text Scheduler.BlogSeriesRunConfig -> [ContentDirectory] -> [DiscoveredSeries] -> Map TaskId (IO ())
taskRunners context seriesMap runConfigs contentDirs discovered =
  let blogSeriesRunners = Map.fromList
        (fmap (\DiscoveredSeries{..} -> (BlogSeries seriesId, runBlogSeries context seriesMap runConfigs seriesId)) discovered)
      staticRunners = Map.fromList
        [ (BackfillBlogImages, runBackfillImages context contentDirs)
        , (InternalLinking, runInternalLinking context)
        , (SocialPosting, runSocialPosting context contentDirs)
        , (AiFiction, runAiFiction context)
        , (ReflectionTitle, runReflectionTitle context)
        , (DailyAnalytics, runDailyAnalytics context)
        ]
  in Map.union blogSeriesRunners staticRunners
