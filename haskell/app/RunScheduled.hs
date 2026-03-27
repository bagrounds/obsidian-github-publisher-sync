module Main where

import Control.Concurrent (threadDelay)
import Control.Exception (SomeException, try)
import Data.Char (isDigit)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Data.Time (UTCTime (..), addDays, defaultTimeLocale, formatTime, fromGregorian, getCurrentTime)
import Network.HTTP.Client (Manager, newManager)
import Network.HTTP.Client.TLS (tlsManagerSettings)
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, doesFileExist, listDirectory, removeFile)
import System.Environment (getArgs, lookupEnv)
import System.Exit (exitFailure)
import System.FilePath ((</>), dropExtension, takeExtension)
import System.IO (hSetBuffering, stdout, stderr, BufferMode(..))

import Automation.AiBlogLinks (NavLinkResult (..), ensureAllNavLinks, buildReflectionLinks)
import Automation.AiFiction
  ( FictionConfig (..)
  , FictionResult (..)
  , defaultFictionModel
  , generateFiction
  , reflectionNeedsFiction
  )
import Automation.BlogComments (fetchAllSeriesComments)
import Automation.BlogImage (BackfillConfig (..), BackfillResult (..), syncMarkdownDir, syncAttachmentsDir, backfillImages, resolveImageProviders)
import Automation.BlogPosts (BlogPost (..), readSeriesPosts)
import Automation.BlogPrompt
  ( assembleFrontmatter
  , buildBackLink
  , buildBlogPrompt
  , todayPacific
  )
import Automation.BlogSeries
  ( appendModelSignature
  , buildBlogContext
  , extractSlug
  , parseGeneratedPost
  , updatePreviousPost
  )
import Automation.BlogSeriesConfig
  ( BlogSeriesConfig (..)
  , backfillContentIds
  , lookupSeries
  )
import Automation.DailyReflection (updateDailyReflection)
import Automation.DailyUpdates (UpdateLink (..), addUpdateLinksToReflection)
import Automation.Gemini
  ( GenerationConfig (..)
  , GeminiResponse (..)
  , generateContentWithFallback
  , defaultGenerationConfig
  )
import Automation.ObsidianSync
  ( ObsidianCredentials (..)
  , syncObsidianVault
  , pushObsidianVault
  )
import Automation.ReflectionTitle
  ( ReflectionTitleConfig (..)
  , ReflectionTitleResult (..)
  , defaultTitleModel
  , generateReflectionTitle
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
import qualified Automation.InternalLinking as IL
import Automation.SocialPosting (autoPost)

-- ---------------------------------------------------------------------------
-- Logging helpers
-- ---------------------------------------------------------------------------

ts :: IO Text
ts = T.pack . formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%S%QZ" <$> getCurrentTime

logMsg :: Text -> IO ()
logMsg msg = do
  timestamp <- ts
  TIO.putStrLn $ "[" <> timestamp <> "] " <> msg

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------

interTaskDelayMs :: Int
interTaskDelayMs = 30000000 -- 30 seconds in microseconds

inferenceDashboards :: [(Text, Text)]
inferenceDashboards =
  [ ("Gemini API", "https://aistudio.google.com/apikey")
  , ("GCP Quotas", "https://console.cloud.google.com/iam-admin/quotas")
  , ("Cloudflare AI", "https://dash.cloudflare.com/?to=/:account/ai/workers-ai")
  , ("Hugging Face", "https://huggingface.co/settings/billing")
  , ("Together AI", "https://api.together.ai/settings/billing")
  ]

-- ---------------------------------------------------------------------------
-- Shared Gemini caller for fiction/title generators
-- ---------------------------------------------------------------------------

callGeminiForGenerator :: Manager -> Text -> [Text] -> (Text, Text) -> IO (Text, Text)
callGeminiForGenerator manager apiKey models (systemPrompt, userPrompt) = do
  let combinedPrompt = systemPrompt <> "\n\n" <> userPrompt
      config = defaultGenerationConfig { gcTemperature = 0.9, gcMaxOutputTokens = 2048 }
  result <- generateContentWithFallback manager models combinedPrompt apiKey config
  case result of
    Left err -> error $ "Gemini API error: " <> T.unpack err
    Right resp -> pure (grText resp, grModel' resp)

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
    { ocAuthToken = authToken
    , ocVaultName = vaultName
    , ocVaultPassword = vaultPassword
    }

getVaultCacheDir :: IO (Maybe FilePath)
getVaultCacheDir = lookupEnv "OBSIDIAN_VAULT_CACHE_DIR"

buildEnvMap :: [String] -> IO (Map Text Text)
buildEnvMap keys = Map.fromList <$> mapM lookupOne keys
  where
    lookupOne k = do
      mVal <- lookupEnv k
      pure (T.pack k, maybe "" T.pack mVal)

-- ---------------------------------------------------------------------------
-- Slug generation (matches TypeScript generateSlug)
-- ---------------------------------------------------------------------------

generateSlug :: Text -> Text
generateSlug title =
  let cleaned = T.filter (\c -> not (isEmoji c)) title
      lowered = T.toLower (T.strip cleaned)
      alphanum = T.map (\c -> if isAlphaNumOrSpace c then c else ' ') lowered
      dashed = T.intercalate "-" (T.words alphanum)
      trimmed = T.dropWhile (== '-') (T.dropWhileEnd (== '-') dashed)
  in trimmed
  where
    isAlphaNumOrSpace c = (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == ' ' || c == '-'
    isEmoji c =
      (c >= '\x1f300' && c <= '\x1faff')
        || (c >= '\x2600' && c <= '\x27bf')
        || (c >= '\x200d' && c <= '\x200d')
        || c == '\xfe0f'
        || (c >= '\x2300' && c <= '\x23ff')
        || (c >= '\x2702' && c <= '\x27b0')

-- ---------------------------------------------------------------------------
-- Strip code fences from LLM output
-- ---------------------------------------------------------------------------

stripCodeFences :: Text -> Text
stripCodeFences t =
  let t1 = case T.stripPrefix "```markdown\n" t of
              Just rest -> rest
              Nothing -> case T.stripPrefix "```md\n" t of
                Just rest -> rest
                Nothing -> case T.stripPrefix "```\n" t of
                  Just rest -> rest
                  Nothing -> t
      t2 = case T.stripSuffix "\n```" t1 of
              Just rest -> rest
              Nothing -> t1
  in t2

-- ---------------------------------------------------------------------------
-- syncFileToVault (local implementation matching TypeScript)
-- ---------------------------------------------------------------------------

syncFileToVault :: FilePath -> FilePath -> FilePath -> IO Bool
syncFileToVault localPath vaultRelPath vaultDir = do
  let vaultPath = vaultDir </> vaultRelPath
  localExists <- doesFileExist localPath
  case localExists of
    False -> pure False
    True -> do
      localContent <- TIO.readFile localPath
      vaultExists <- doesFileExist vaultPath
      case vaultExists of
        True -> do
          vaultContent <- TIO.readFile vaultPath
          case localContent == vaultContent of
            True  -> pure False
            False -> do
              createDirectoryIfMissing True (takeDirectory vaultPath)
              TIO.writeFile vaultPath localContent
              pure True
        False -> do
          createDirectoryIfMissing True (takeDirectory vaultPath)
          TIO.writeFile vaultPath localContent
          pure True
  where
    takeDirectory = reverse . dropWhile (/= '/') . reverse

-- ---------------------------------------------------------------------------
-- copySeriesPosts (matches TypeScript pull-vault-posts.ts)
-- ---------------------------------------------------------------------------

copySeriesPosts :: FilePath -> Text -> FilePath -> IO Int
copySeriesPosts vaultDir seriesId repoRoot = do
  let vaultSeriesDir = vaultDir </> T.unpack seriesId
      localSeriesDir = repoRoot </> T.unpack seriesId
  vaultExists <- doesDirectoryExist vaultSeriesDir
  case vaultExists of
    False -> pure 0
    True -> do
      entries <- listDirectory vaultSeriesDir
      let dateFiles = filter isDateFile entries
      createDirectoryIfMissing True localSeriesDir
      mapM_ (copyFile' vaultSeriesDir localSeriesDir) dateFiles
      pure (length dateFiles)
  where
    isDateFile f =
      length f >= 14
        && takeExtension f == ".md"
        && all isDigit (take 4 f)
        && f !! 4 == '-'
    copyFile' srcDir dstDir f = do
      content <- TIO.readFile (srcDir </> f)
      TIO.writeFile (dstDir </> f) content

-- ---------------------------------------------------------------------------
-- readPreviousPostFilename from metadata file
-- ---------------------------------------------------------------------------

readPreviousPostFilename :: FilePath -> IO (Maybe Text)
readPreviousPostFilename metadataPath = do
  exists <- doesFileExist metadataPath
  case exists of
    False -> pure Nothing
    True -> do
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
  case exists of
    False -> pure []
    True -> do
      entries <- listDirectory reflectionsDir
      let dateFiles = filter isReflectionFile entries
          sorted = reverse $ filter (< T.unpack today <> ".md") (map id dateFiles)
          recent = take 20 sorted
      titles <- mapM extractCreativeTitle recent
      pure (filter (not . T.null) titles)
  where
    isReflectionFile f =
      length f == 13  -- "YYYY-MM-DD.md"
        && takeExtension f == ".md"
        && all isDigit (take 4 f)
        && f !! 4 == '-'
    extractCreativeTitle f = do
      content <- TIO.readFile (reflectionsDir </> f)
      let titleLine = foldr (\l acc -> if T.isPrefixOf "title:" l then Just l else acc) Nothing (T.lines content)
      pure $ case titleLine of
        Just tl ->
          let val = T.strip (T.drop 6 tl)
              unquoted = T.dropAround (\c -> c == '"' || c == '\'') val
          in case T.breakOn " | " unquoted of
               (_, rest) | not (T.null rest) -> T.drop 3 rest
               _ -> ""
        Nothing -> ""

-- ---------------------------------------------------------------------------
-- yesterdayPacific
-- ---------------------------------------------------------------------------

yesterdayPacific :: IO Text
yesterdayPacific = do
  today <- todayPacific
  -- Simple: parse the date, subtract 1 day
  let (y, m, d) = parseYMD today
  pure $ formatYMD (addDaysToYMD (-1) y m d)
  where
    parseYMD t =
      let parts = T.splitOn "-" t
      in case parts of
           [y, m, d] -> (read (T.unpack y) :: Integer, read (T.unpack m) :: Int, read (T.unpack d) :: Int)
           _ -> (2026, 1, 1)
    addDaysToYMD n y m d =
      let day = fromGregorian y m d
          newDay = addDays n day
      in newDay
    formatYMD day =
      T.pack $ formatTime defaultTimeLocale "%Y-%m-%d" day

-- ---------------------------------------------------------------------------
-- Task runners
-- ---------------------------------------------------------------------------

runBlogSeries :: Manager -> FilePath -> Text -> IO ()
runBlogSeries manager repoRoot seriesId = do
  let taskName = "blog-series:" <> seriesId
  logMsg $ "▶️  " <> taskName

  let mRunConfig = Map.lookup seriesId blogSeriesRunConfigs
  runConfig <- case mRunConfig of
    Just rc -> pure rc
    Nothing -> error $ "No run config for series: " <> T.unpack seriesId

  creds <- getObsidianCreds
  apiKey <- requireEnv "GEMINI_API_KEY"
  today <- todayPacific

  -- 1. Pull vault posts for this series
  cacheDir <- getVaultCacheDir
  vaultDir <- syncObsidianVault creds cacheDir
  _ <- copySeriesPosts vaultDir seriesId repoRoot

  -- 2. Check regeneration or already exists
  let seriesDir = repoRoot </> T.unpack seriesId
  mRegen <- findPostToRegenerate seriesDir today
  case mRegen of
    Just postToRegen -> do
      logMsg $ "  ♻️  Regeneration requested for " <> T.pack postToRegen <> " — removing old post"
      removeFile (seriesDir </> postToRegen)
    Nothing -> do
      existsForToday <- blogPostExistsForToday seriesDir today
      case existsForToday of
        True -> do
          logMsg $ "  ⏭️  Already generated for " <> today
          pure ()
        False -> pure ()

  -- Recheck after potential removal
  existsNow <- blogPostExistsForToday seriesDir today
  case (mRegen, existsNow) of
    (Nothing, True) -> pure () -- Already existed, skip
    _ -> do
      -- 3. Determine model chain
      envModel <- lookupEnvText "BLOG_GEMINI_MODEL"
      let models = case envModel of
            Just em | not (T.null (T.strip em)) ->
              T.strip em : filter (/= T.strip em) (bsrcModelChain runConfig)
            _ -> bsrcModelChain runConfig

      priorityUser <- lookupEnvText (T.unpack (bsrcPriorityUserEnvVar runConfig))

      -- 4. Fetch comments
      let series = either (error . T.unpack) id (lookupSeries seriesId)
      comments <- fetchAllSeriesComments manager seriesId (priorityUser >>= (\u -> if T.null u then Nothing else Just u))
      logMsg $ "  📝 Fetched " <> T.pack (show (length comments)) <> " comments"

      -- 5. Build context and prompt
      context <- buildBlogContext seriesId seriesDir comments today
      let (systemPrompt, userPrompt) = buildBlogPrompt context
          combinedPrompt = systemPrompt <> "\n\n" <> userPrompt
          genConfig = defaultGenerationConfig { gcTemperature = 0.9, gcMaxOutputTokens = 8192 }

      -- 6. Call Gemini
      result <- generateContentWithFallback manager models combinedPrompt apiKey genConfig
      case result of
        Left err -> error $ "Blog generation failed: " <> T.unpack err
        Right resp -> do
          let rawText = stripCodeFences (grText resp)
              usedModel = grModel' resp
          case parseGeneratedPost rawText of
            Nothing -> error "Failed to parse generated blog post"
            Just (body, title) -> do
              let slug = generateSlug title
                  filename = today <> "-" <> slug <> ".md"

              -- Read previous posts for nav link update
              posts <- readSeriesPosts seriesDir
              let previousPost = case posts of
                    (p:_) -> Just p
                    []    -> Nothing

              -- Write blog post
              let frontmatter = assembleFrontmatter series today title slug []
                  backLink = case previousPost of
                    Just pp -> " | " <> buildBackLink series (bpFilename pp)
                    Nothing -> ""
                  navLine = bscNavLink series <> backLink
                  displayTitle = today <> " | " <> bscIcon series <> " " <> title <> " " <> bscIcon series
                  header = navLine <> "\n# " <> displayTitle <> "\n\n"
                  bodyWithSig = appendModelSignature body usedModel
              createDirectoryIfMissing True seriesDir
              TIO.writeFile (seriesDir </> T.unpack filename) (frontmatter <> "\n" <> header <> bodyWithSig <> "\n")
              logMsg $ "  ✅ Written: " <> filename <> " [" <> usedModel <> "]"

              -- Update previous post with forward link
              case previousPost of
                Just pp -> updatePreviousPost seriesDir pp series filename
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
              _ <- updateDailyReflection vaultDir today series filenameNoExt title regenFilenameNoExt

              -- 7. Sync to vault
              syncVaultDir <- syncObsidianVault creds cacheDir
              let postRelPath = T.unpack seriesId </> T.unpack filename
                  postLocalPath = repoRoot </> postRelPath
              changed1 <- syncFileToVault postLocalPath postRelPath syncVaultDir

              -- Sync previous post if updated
              prevPostFilename <- readPreviousPostFilename metadataPath
              changed2 <- case prevPostFilename of
                Just pf -> do
                  let prevRelPath = T.unpack seriesId </> T.unpack pf
                  syncFileToVault (repoRoot </> prevRelPath) prevRelPath syncVaultDir
                Nothing -> pure False

              -- Sync AGENTS.md
              let agentsRelPath = T.unpack seriesId </> "AGENTS.md"
              changed3 <- syncFileToVault (repoRoot </> agentsRelPath) agentsRelPath syncVaultDir

              let anyChanged = changed1 || changed2 || changed3
              case anyChanged of
                True -> do
                  pushObsidianVault syncVaultDir (ocAuthToken creds)
                  logMsg "  📤 Vault pushed"
                False -> pure ()

  logMsg $ "✅ " <> taskName

runBackfillImages :: Manager -> FilePath -> IO ()
runBackfillImages manager repoRoot = do
  logMsg "▶️  backfill-blog-images"

  creds <- getObsidianCreds
  cacheDir <- getVaultCacheDir
  today <- todayPacific

  -- 1. Pull vault posts
  vaultDir <- syncObsidianVault creds cacheDir
  mapM_ (\sid -> copySeriesPosts vaultDir sid repoRoot) backfillContentIds

  -- 2. Image backfill
  envMap <- buildEnvMap
    [ "GEMINI_API_KEY", "CLOUDFLARE_API_TOKEN", "CLOUDFLARE_ACCOUNT_ID"
    , "CLOUDFLARE_IMAGE_MODEL", "HUGGINGFACE_API_KEY", "HUGGINGFACE_IMAGE_MODEL"
    , "TOGETHER_API_KEY", "TOGETHER_IMAGE_MODEL", "POLLINATIONS_IMAGE_MODEL"
    , "PROMPT_DESCRIBER_MODEL"
    ]
  let providers = resolveImageProviders envMap
  imageModifiedFiles <- case providers of
    [] -> do
      logMsg "  ⚠️  No image providers configured, skipping image backfill"
      pure []
    _  -> do
      logMsg $ "  🎨 Image providers: " <> T.pack (show (length providers))
      let bfConfig = BackfillConfig
            { bfcRepoRoot = repoRoot
            , bfcContentDirs = backfillContentIds
            , bfcAttachmentsDir = repoRoot </> "attachments"
            , bfcProviders = providers
            , bfcMaxImages = 1
            }
      result <- backfillImages manager bfConfig
      logMsg $ "  🖼️  Images: " <> T.pack (show (brImagesGenerated result))
            <> " generated, " <> T.pack (show (brFilesUpdated result))
            <> " files updated, " <> T.pack (show (brFilesSkipped result)) <> " skipped"
      pure (brModifiedFiles result)

  -- 3. Update AI blog nav links
  let aiBlogDir = repoRoot </> "ai-blog"
  navResults <- ensureAllNavLinks aiBlogDir
  let modifiedCount = length (filter (\r -> nlrModified r) navResults)
  logMsg $ "  🔗 Nav links: " <> T.pack (show modifiedCount) <> " files updated"

  -- 4. Sync markdown dirs to vault
  mapM_ (\sid -> do
    let localDir = repoRoot </> T.unpack sid
        vaultTargetDir = vaultDir </> T.unpack sid
    syncMarkdownDir localDir vaultTargetDir
    ) backfillContentIds

  -- 5. Sync attachments
  let attachmentsDir = repoRoot </> "attachments"
  syncAttachmentsDir attachmentsDir (vaultDir </> "attachments")

  -- 6. Add update links from image backfill results
  let reflectionsDir = vaultDir </> "reflections"
  let imageUpdateLinks = fmap (\f ->
        let title = T.replace ".md" "" (T.replace "ai-blog/" "" f)
        in UpdateLink f title
        ) imageModifiedFiles
  case imageUpdateLinks of
    [] -> pure ()
    _  -> do
      _ <- addUpdateLinksToReflection reflectionsDir today imageUpdateLinks
      pure ()

  -- 7. Add update links from nav link changes (each blog post links to its date's reflection)
  aiBlogLinks <- buildReflectionLinks aiBlogDir navResults
  mapM_ (\(relPath, title, date) ->
    addUpdateLinksToReflection reflectionsDir date [UpdateLink relPath title]
    ) aiBlogLinks

  -- 8. Push vault
  pushObsidianVault vaultDir (ocAuthToken creds)
  logMsg "  📤 Vault pushed"

  logMsg "✅ backfill-blog-images"

runInternalLinking :: Manager -> IO ()
runInternalLinking manager = do
  logMsg "▶️  internal-linking"

  creds <- getObsidianCreds
  cacheDir <- getVaultCacheDir

  vaultDir <- syncObsidianVault creds cacheDir

  envModel <- lookupEnvText "INTERNAL_LINKING_MODEL"
  let model = fromMaybe IL.defaultLinkingModel envModel
  result <- IL.run manager model vaultDir
  logMsg $ "  🔗 Internal linking: "
        <> T.pack (show (IL.lrFilesVisited result)) <> " visited, "
        <> T.pack (show (IL.lrFilesModified result)) <> " modified, "
        <> T.pack (show (IL.lrTotalLinksAdded result)) <> " links added"

  pushObsidianVault vaultDir (ocAuthToken creds)
  logMsg "  📤 Vault pushed"
  logMsg "✅ internal-linking"

runSocialPosting :: Manager -> IO ()
runSocialPosting manager = do
  logMsg "▶️  social-posting"
  autoPost manager
  logMsg "✅ social-posting"

runAiFiction :: Manager -> IO ()
runAiFiction manager = do
  logMsg "▶️  ai-fiction"

  creds <- getObsidianCreds
  apiKey <- requireEnv "GEMINI_API_KEY"
  today <- todayPacific

  cacheDir <- getVaultCacheDir
  vaultDir <- syncObsidianVault creds cacheDir
  let reflectionsDir = vaultDir </> "reflections"
      reflectionPath = reflectionsDir </> T.unpack today <> ".md"

  exists <- doesFileExist reflectionPath
  case exists of
    False -> do
      logMsg $ "  📭 No reflection for " <> today <> ", skipping AI fiction"
      logMsg "✅ ai-fiction (skipped)"
    True -> do
      noteContent <- TIO.readFile reflectionPath
      case reflectionNeedsFiction noteContent of
        False -> do
          logMsg $ "  ✅ Reflection " <> today <> " already has AI fiction"
          logMsg "✅ ai-fiction (already done)"
        True -> do
          -- Build model chain
          envModel <- lookupEnvText "FICTION_MODEL"
          let defaultChain = [defaultFictionModel, "gemini-2.5-flash-lite", "gemini-3.1-flash-lite-preview"]
              models = case envModel of
                Just em | not (T.null (T.strip em)) -> T.strip em : defaultChain
                _ -> defaultChain

          let config = FictionConfig
                { fcApiKey = apiKey
                , fcModels = models
                , fcNoteContent = noteContent
                }

          result <- generateFiction config (callGeminiForGenerator manager)

          let wordCount = length (T.words (frFiction result))
          logMsg $ "  🤖🐲 Generated fiction (model=" <> frModel result <> ", " <> T.pack (show wordCount) <> " words)"

          TIO.writeFile reflectionPath (frUpdatedContent result)
          logMsg $ "  ✏️  Updated " <> today <> ".md with AI fiction"

          pushObsidianVault vaultDir (ocAuthToken creds)
          logMsg "✅ ai-fiction"

runReflectionTitle :: Manager -> IO ()
runReflectionTitle manager = do
  logMsg "▶️  reflection-title"

  creds <- getObsidianCreds
  apiKey <- requireEnv "GEMINI_API_KEY"
  today <- todayPacific
  yesterday <- yesterdayPacific

  cacheDir <- getVaultCacheDir
  vaultDir <- syncObsidianVault creds cacheDir
  let reflectionsDir = vaultDir </> "reflections"

  -- Try today first, then yesterday
  todayDone <- tryTitleForDate manager apiKey creds vaultDir reflectionsDir today
  case todayDone of
    True -> pure ()
    False -> do
      logMsg $ "  📅 Checking yesterday (" <> yesterday <> ")..."
      _ <- tryTitleForDate manager apiKey creds vaultDir reflectionsDir yesterday
      pure ()

  logMsg "✅ reflection-title"

tryTitleForDate :: Manager -> Text -> ObsidianCredentials -> FilePath -> FilePath -> Text -> IO Bool
tryTitleForDate manager apiKey creds vaultDir reflectionsDir date = do
  let reflectionPath = reflectionsDir </> T.unpack date <> ".md"

  exists <- doesFileExist reflectionPath
  case exists of
    False -> do
      logMsg $ "  ⏭️  No reflection note for " <> date
      pure False
    True -> do
      content <- TIO.readFile reflectionPath
      case reflectionNeedsTitle content date of
        False -> do
          logMsg $ "  ⏭️  Reflection title already set for " <> date
          pure False
        True -> do
          recentTitles <- extractRecentCreativeTitles reflectionsDir date
          logMsg $ "  📋 Found " <> T.pack (show (length recentTitles)) <> " recent titles for style reference"

          -- Build model chain
          envModel <- lookupEnvText "REFLECTION_TITLE_MODEL"
          let defaultChain = [defaultTitleModel, "gemini-2.5-flash-lite", "gemini-3.1-flash-lite-preview"]
              models = case envModel of
                Just em | not (T.null (T.strip em)) ->
                  T.strip em : filter (/= T.strip em) defaultChain
                _ -> defaultChain

          let config = ReflectionTitleConfig
                { rtcApiKey = apiKey
                , rtcModels = models
                , rtcNoteContent = content
                , rtcDate = date
                , rtcRecentTitles = recentTitles
                }

          result <- generateReflectionTitle config (callGeminiForGenerator manager)

          logMsg $ "  🏷️  Generated title: " <> rtrFullTitle result <> " [" <> rtrModel result <> "]"

          TIO.writeFile reflectionPath (rtrUpdatedContent result)
          pushObsidianVault vaultDir (ocAuthToken creds)
          logMsg "  📤 Vault pushed"
          pure True

-- ---------------------------------------------------------------------------
-- Task dispatch
-- ---------------------------------------------------------------------------

taskRunners :: Manager -> FilePath -> Map TaskId (IO ())
taskRunners manager repoRoot = Map.fromList
  [ (BlogSeriesChickieLoo, runBlogSeries manager repoRoot "chickie-loo")
  , (BlogSeriesAutoBlogZero, runBlogSeries manager repoRoot "auto-blog-zero")
  , (BlogSeriesSystemsForPublicGood, runBlogSeries manager repoRoot "systems-for-public-good")
  , (BackfillBlogImages, runBackfillImages manager repoRoot)
  , (InternalLinking, runInternalLinking manager)
  , (SocialPosting, runSocialPosting manager)
  , (AiFiction, runAiFiction manager)
  , (ReflectionTitle, runReflectionTitle manager)
  ]

-- ---------------------------------------------------------------------------
-- CLI argument parsing
-- ---------------------------------------------------------------------------

data CliArgs = CliArgs
  { cliHourOverride :: Maybe Int
  , cliTaskOverride :: Maybe Text
  }

parseCliArgs :: [String] -> CliArgs
parseCliArgs = go (CliArgs Nothing Nothing)
  where
    go acc [] = acc
    go acc ("--hour" : h : rest) = go (acc { cliHourOverride = Just (read h) }) rest
    go acc ("--task" : t : rest) = go (acc { cliTaskOverride = Just (T.pack t) }) rest
    go acc (_ : rest) = go acc rest

-- ---------------------------------------------------------------------------
-- Main
-- ---------------------------------------------------------------------------

main :: IO ()
main = do
  hSetBuffering stdout LineBuffering

  args <- parseCliArgs <$> getArgs
  hourPacific <- case cliHourOverride args of
    Just h  -> pure h
    Nothing -> nowPacificHour

  -- Repo root: prefer REPO_ROOT env, then GITHUB_WORKSPACE, then "."
  mRepoRoot <- lookupEnv "REPO_ROOT"
  mWorkspace <- lookupEnv "GITHUB_WORKSPACE"
  let repoRoot = case mRepoRoot of
        Just r  -> r
        Nothing -> case mWorkspace of
          Just w  -> w
          Nothing -> "."
  manager <- newManager tlsManagerSettings

  tasks <- case cliTaskOverride args of
    Just taskStr ->
      case isValidTaskId taskStr of
        True -> case taskIdFromText taskStr of
          Just tid -> pure [tid]
          Nothing  -> do
            TIO.hPutStrLn stderr $ "❌ Unknown task: " <> taskStr
            exitFailure
        False -> do
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
      let runners = taskRunners manager repoRoot
      results <- runTasks runners tasks []
      let succeeded = length (filter (\(_, s, _) -> s) results)
          total = length results

      TIO.putStrLn "\n--- Run Summary ---"
      mapM_ (\(tid, success, mErr) ->
        let icon = if success then "✅" else "❌"
            errSuffix = maybe "" (" — " <>) mErr
        in TIO.putStrLn $ "  " <> icon <> " " <> taskIdToText tid <> errSuffix
        ) (fmap (\(tid, s, e) -> (tid, s, e)) (toTriples results))
      TIO.putStrLn $ "  📊 " <> T.pack (show succeeded) <> "/" <> T.pack (show total) <> " succeeded"
      TIO.putStrLn "-------------------\n"
  where
    toTriples :: [(TaskId, Bool, Maybe Text)] -> [(TaskId, Bool, Maybe Text)]
    toTriples = id

    runTasks :: Map TaskId (IO ()) -> [TaskId] -> [(TaskId, Bool, Maybe Text)] -> IO [(TaskId, Bool, Maybe Text)]
    runTasks _ [] acc = pure (reverse acc)
    runTasks runners (tid:rest) acc = do
      -- Inter-task delay (skip for first task)
      case acc of
        [] -> pure ()
        _  -> do
          TIO.putStrLn $ "⏳ Inter-task delay: " <> T.pack (show (interTaskDelayMs `div` 1000000)) <> "s"
          threadDelay interTaskDelayMs

      let mRunner = Map.lookup tid runners
      case mRunner of
        Nothing -> do
          logMsg $ "  ⚠️  Unknown task: " <> taskIdToText tid
          runTasks runners rest ((tid, False, Just "no runner registered") : acc)
        Just runner -> do
          result <- try runner :: IO (Either SomeException ())
          case result of
            Right () -> runTasks runners rest ((tid, True, Nothing) : acc)
            Left err -> do
              let msg = T.pack (show err)
              logMsg $ "❌ " <> taskIdToText tid <> " — " <> msg
              runTasks runners rest ((tid, False, Just msg) : acc)
