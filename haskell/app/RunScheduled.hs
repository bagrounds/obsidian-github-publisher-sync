module Main where

import Control.Monad (when)
import Control.Exception (SomeException, try)
import Data.List.NonEmpty (NonEmpty ((:|)))
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (catMaybes, fromMaybe, mapMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Data.Time (addDays)
import Network.HTTP.Client (newManager)
import Network.HTTP.Client.TLS (tlsManagerSettings)
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
import Automation.BlogImage (BackfillConfig (..), BackfillResult (..), ImageGenerationResult, syncAttachmentsDir, backfillImages, resolveImageProviders, processNote, contentDirectoryFromText)
import Automation.BlogPosts (BlogPost (..), readSeriesPosts)
import Automation.BlogPrompt
  ( DisplayTitle (..)
  , Slug (..)
  , assembleFrontmatter
  , buildBackLink
  , buildBlogPrompt
  , buildDisplayTitle
  , formatDay
  , generateSlug
  , mkSlug
  , sanitizeTitle
  , todayPacificDay
  )
import Automation.BlogSeries
  ( appendModelSignature
  , buildBlogContext
  , parseGeneratedPost
  , updatePreviousPost
  )
import Automation.BlogSeriesConfig
  ( BlogSeriesConfig (..)
  , imageBackfillContentIds
  , lookupSeries
  )
import Automation.DailyReflection (UpdateReflectionResult (..), updateDailyReflection)
import Automation.DailyUpdates (UpdateLink (..), addUpdateLinksToReflection, extractTitleFromFile)
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
  , generateReflectionTitle
  , isReflectionFile
  , reflectionNeedsTitle
  )
import Automation.Scheduler
  ( TaskId (..)
  , BlogSeriesRunConfig (..)
  , blogSeriesRunConfigs
  , blogPostExistsForToday
  , findPostToRegenerate
  , getScheduledTasks
  , isValidTaskId
  , nowPacificHour
  , taskIdFromText
  , taskIdToText
  )
import Automation.Types (Secret (..), unRelativePath, mkRelativePath, mkTitle)
import qualified Automation.Context as Context
import qualified Automation.InternalLinking as IL
import Automation.SocialPosting (autoPost)
import Automation.CliArgs (CliArgs (..), parseCliArgs)
import Automation.VaultSync (syncFileToVault, syncNewAiBlogPosts, copySeriesPosts)
import Automation.TaskRunner (inferenceDashboards, runTasks, logMsg)
import Automation.Text (stripCodeFences)

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Shared Gemini caller for fiction/title generators
-- ---------------------------------------------------------------------------

callGeminiForGenerator :: Context.AppContext -> NonEmpty Gemini.Model -> (Text, Text) -> IO (Text, Text)
callGeminiForGenerator context models (systemPrompt, userPrompt) = do
  let combinedPrompt = systemPrompt <> "\n\n" <> userPrompt
      config = Gemini.defaultGenerationConfig { Gemini.gcTemperature = 0.9, Gemini.gcMaxOutputTokens = 2048 }
  result <- Gemini.generateContentWithFallback (Context.httpManager context) models combinedPrompt (Context.geminiApiKey context) config
  case result of
    Left err -> error $ "Gemini API error: " <> show err
    Right response -> pure (Gemini.responseText response, Gemini.modelToText (Gemini.responseModel response))

-- ---------------------------------------------------------------------------
-- Environment helpers
-- ---------------------------------------------------------------------------

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

-- ---------------------------------------------------------------------------
-- readPreviousPostFilename from metadata file
-- ---------------------------------------------------------------------------

readPreviousPostFilename :: FilePath -> IO (Maybe Text)
readPreviousPostFilename metadataPath = do
  exists <- doesFileExist metadataPath
  if not exists
    then pure Nothing
    else do
      content <- TIO.readFile metadataPath
      -- Simple parse: find "previousPostFilename":"value"
      case T.breakOn "\"previousPostFilename\"" content of
        (_, rest) | not (T.null rest) ->
          case T.breakOn "\"" (T.drop 1 (snd (T.breakOn ":" rest))) of
            (_, afterColon) | not (T.null afterColon) ->
              let afterQuote = T.drop 1 afterColon
                  val = T.takeWhile (/= '"') afterQuote
              in pure (Just val)
            _ -> pure Nothing
        _ -> pure Nothing

-- ---------------------------------------------------------------------------
-- Extract recent creative titles for reflection-title generation
-- ---------------------------------------------------------------------------

extractRecentCreativeTitles :: FilePath -> Text -> IO [Text]
extractRecentCreativeTitles reflectionsDir today = do
  exists <- doesDirectoryExist reflectionsDir
  if not exists
    then pure []
    else do
      entries <- listDirectory reflectionsDir
      let dateFiles = filter isReflectionFile entries
          sorted = reverse $ filter (< T.unpack today <> ".md") dateFiles
          recent = take 20 sorted
      titles <- mapM readCreativeTitle recent
      pure (filter (not . T.null) titles)
  where
    readCreativeTitle filename = do
      content <- TIO.readFile (reflectionsDir </> filename)
      pure (extractCreativeTitle content)

-- ---------------------------------------------------------------------------
-- yesterdayPacific
-- ---------------------------------------------------------------------------

yesterdayPacific :: IO Text
yesterdayPacific = formatDay . addDays (-1) <$> todayPacificDay

-- ---------------------------------------------------------------------------
-- Task runners
-- ---------------------------------------------------------------------------

runBlogSeries :: Context.AppContext -> Text -> IO ()
runBlogSeries context seriesId = do
  let taskName = "blog-series:" <> seriesId
      manager = Context.httpManager context
      repoRoot = Context.repoRoot context
      vaultDir = Context.vaultDir context
      apiKey = Context.geminiApiKey context
  logMsg $ "▶️  " <> taskName

  let mRunConfig = Map.lookup seriesId blogSeriesRunConfigs
  runConfig <- case mRunConfig of
    Just rc -> pure rc
    Nothing -> error $ "No run config for series: " <> T.unpack seriesId

  today <- todayPacificDay
  let todayText = formatDay today
  _ <- copySeriesPosts vaultDir seriesId repoRoot

  -- 2. Check regeneration or already exists
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

  -- Recheck after potential removal
  existsNow <- blogPostExistsForToday seriesDir todayText
  case (mRegen, existsNow) of
    (Nothing, True) -> pure () -- Already existed, skip
    _ -> do
      -- 3. Determine model chain
      envModel <- lookupEnvText "BLOG_GEMINI_MODEL"
      let models = Gemini.overrideModelChain envModel (bsrcModelChain runConfig)

      priorityUser <- lookupEnvText (T.unpack (bsrcPriorityUserEnvVar runConfig))

      -- 4. Fetch comments
      let series = either (error . T.unpack) id (lookupSeries seriesId)
      comments <- fetchAllSeriesComments manager seriesId (priorityUser >>= (\u -> if T.null u then Nothing else Just u))
      logMsg $ "  📝 Fetched " <> T.pack (show (length comments)) <> " comments"

      -- 5. Build context and prompt
      blogContextResult <- buildBlogContext seriesId seriesDir comments today
      case blogContextResult of
        Left reason -> error $ "Blog context build failed: " <> T.unpack reason
        Right blogContext -> do
          let (systemPrompt, userPrompt) = buildBlogPrompt blogContext
              combinedPrompt = systemPrompt <> "\n\n" <> userPrompt
              genConfig = Gemini.defaultGenerationConfig { Gemini.gcTemperature = 0.9, Gemini.gcMaxOutputTokens = 8192 }

          -- 6. Call Gemini
          result <- Gemini.generateContentWithFallback manager models combinedPrompt apiKey genConfig
          case result of
            Left err -> error $ "Blog generation failed: " <> show err
            Right response -> do
              let rawText = stripCodeFences (Gemini.responseText response)
                  usedModel = Gemini.modelToText (Gemini.responseModel response)
              case parseGeneratedPost rawText of
                Nothing -> error "Failed to parse generated blog post"
                Just (body, rawTitle) -> do
                  let title = sanitizeTitle series rawTitle
                      slugText = generateSlug title
                      slug = case mkSlug slugText of
                        Right s -> s
                        Left e  -> error $ "Invalid slug: " <> T.unpack e
                      filename = todayText <> "-" <> unSlug slug <> ".md"

                  -- Read previous posts for nav link update
                  posts <- readSeriesPosts seriesDir
                  let previousPost = case posts of
                        (p:_) -> Just p
                        []    -> Nothing

                  -- Write blog post
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

                  -- Generate blog image (continue on error, matching TypeScript behavior)
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

                  -- Update previous post with forward link — edit directly in vault
                  case previousPost of
                    Just pp -> updatePreviousPost (vaultDir </> T.unpack seriesId) pp series filename
                    Nothing -> pure ()

                  -- Write metadata
                  let metadataPath = seriesDir </> ".last-generate-metadata.json"
                  case previousPost of
                    Just pp -> TIO.writeFile metadataPath $
                      "{\"previousPostFilename\":\"" <> bpFilename pp <> "\",\"newPostFilename\":\"" <> filename <> "\"}"
                    Nothing -> pure ()

                  -- Update daily reflection
                  let filenameNoExt = T.pack $ dropExtension $ T.unpack filename
                      regenFilenameNoExt = case mRegen of
                        Just r  -> Just (T.pack (dropExtension r))
                        Nothing -> Nothing
                  _ <- updateDailyReflection vaultDir todayText series filenameNoExt title regenFilenameNoExt

                  -- Sync new post to vault (this is a genuinely new file)
                  let postRelPath = T.unpack seriesId </> T.unpack filename
                      postLocalPath = repoRoot </> postRelPath
                  _ <- syncFileToVault postLocalPath postRelPath vaultDir

                  -- Sync AGENTS.md (lives in git, needs to go to vault)
                  let agentsRelPath = T.unpack seriesId </> "AGENTS.md"
                  _ <- syncFileToVault (repoRoot </> agentsRelPath) agentsRelPath vaultDir

                  -- Sync attachments (new image files) to vault
                  syncAttachmentsDir (repoRoot </> "attachments") (vaultDir </> "attachments")
                  pure ()

  logMsg $ "✅ " <> taskName

runBackfillImages :: Context.AppContext -> IO ()
runBackfillImages context = do
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
      let contentDirectories = mapMaybe contentDirectoryFromText imageBackfillContentIds
          backfillConfig = BackfillConfig
            { backfillRepoRoot = vaultDir
            , backfillContentDirs = contentDirectories
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
  let reflectionsDir = vaultDir </> "reflections"
  imageUpdateLinks <- catMaybes <$> traverse (\filePath -> do
        title <- extractTitleFromFile (vaultDir </> T.unpack filePath)
        case (mkRelativePath filePath, mkTitle title) of
          (Right relativePath, Right validTitle) ->
            pure (Just (UpdateLink relativePath validTitle ["🖼️ added image"]))
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
      _ <- addUpdateLinksToReflection reflectionsDir todayText imageUpdateLinks
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
        <> T.pack (show (IL.lrFilesVisited result)) <> " visited, "
        <> T.pack (show (IL.lrFilesModified result)) <> " modified, "
        <> T.pack (show (IL.lrTotalLinksAdded result)) <> " links added"

  -- Add update links to daily reflection for modified files
  let modifiedResults = filter IL.frModified (IL.lrFileResults result)
  case modifiedResults of
    [] -> pure ()
    _  -> do
      today <- todayPacificDay
      let todayText = formatDay today
          reflectionsDir = vaultDir </> "reflections"
      links <- catMaybes <$> traverse (\fr -> do
        title <- extractTitleFromFile (vaultDir </> T.unpack (unRelativePath (IL.frRelativePath fr)))
        let linksAdded = IL.frLinksAdded fr
            detail = "🔗 added " <> T.pack (show linksAdded) <> " internal link" <> (if linksAdded == 1 then "" else "s")
        case mkTitle title of
          Right validTitle -> pure (Just (UpdateLink (IL.frRelativePath fr) validTitle [detail]))
          Left titleError -> do
            logMsg $ "  ⚠️  Skipping update link: " <> titleError
            pure Nothing
        ) modifiedResults
      _ <- addUpdateLinksToReflection reflectionsDir todayText links
      pure ()

  logMsg "✅ internal-linking"

runSocialPosting :: Context.AppContext -> IO ()
runSocialPosting context = do
  logMsg "▶️  social-posting"
  autoPost (Context.httpManager context) (Context.vaultDir context)
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
  yesterday <- yesterdayPacific

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

-- ---------------------------------------------------------------------------
-- Task dispatch
-- ---------------------------------------------------------------------------

taskRunners :: Context.AppContext -> Map TaskId (IO ())
taskRunners context = Map.fromList
  [ (BlogSeriesChickieLoo, runBlogSeries context "chickie-loo")
  , (BlogSeriesAutoBlogZero, runBlogSeries context "auto-blog-zero")
  , (BlogSeriesSystemsForPublicGood, runBlogSeries context "systems-for-public-good")
  , (BackfillBlogImages, runBackfillImages context)
  , (InternalLinking, runInternalLinking context)
  , (SocialPosting, runSocialPosting context)
  , (AiFiction, runAiFiction context)
  , (ReflectionTitle, runReflectionTitle context)
  ]

-- ---------------------------------------------------------------------------
-- Main
-- ---------------------------------------------------------------------------

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

  tasks <- case cliTaskOverride args of
    Just taskStr ->
      if isValidTaskId taskStr
        then case taskIdFromText taskStr of
          Just tid -> pure [tid]
          Nothing  -> do
            TIO.hPutStrLn stderr $ "❌ Unknown task: " <> taskStr
            exitFailure
        else do
          TIO.hPutStrLn stderr $ "❌ Unknown task: " <> taskStr
          exitFailure
    Nothing -> pure $ getScheduledTasks hourPacific

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
      let runners = taskRunners context
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
