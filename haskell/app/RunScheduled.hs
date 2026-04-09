module Main where

import Control.Concurrent (threadDelay)
import Control.Exception (SomeException, try)
import Data.Char (isDigit)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Data.Time (addDays, defaultTimeLocale, formatTime, fromGregorian, getCurrentTime)
import Network.HTTP.Client (Manager, newManager)
import Network.HTTP.Client.TLS (tlsManagerSettings)
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, doesFileExist, listDirectory, removeFile)
import System.Environment (getArgs, lookupEnv)
import System.Exit (exitFailure)
import System.FilePath ((</>), dropExtension, takeExtension)
import System.IO (hSetBuffering, stdout, stderr, BufferMode(..))

import Automation.AiBlogLinks (NavLinkResult (..), aiBlogConfig, ensureAllNavLinks, buildReflectionLinks)
import Automation.AiFiction
  ( FictionConfig (..)
  , FictionResult (..)
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
  , mkSlug
  , sanitizeTitle
  , todayPacific
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
import Automation.Types (Secret (..), DateStr (..))
import qualified Automation.InternalLinking as IL
import Automation.SocialPosting (autoPost)
import Automation.Text (wordJaccardSimilarity)

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

callGeminiForGenerator :: Manager -> Secret -> [Text] -> (Text, Text) -> IO (Text, Text)
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

requireSecret :: String -> IO Secret
requireSecret key = Secret <$> requireEnv key

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
-- syncNewAiBlogPosts (copy-if-missing with content similarity dedup)
-- ---------------------------------------------------------------------------

-- | Similarity threshold for dedup. Posts scoring above this against any
--   vault file are considered modified versions, not new content.
--
--   Empirically derived from the ai-blog corpus:
--     genuinely new posts:       max Jaccard similarity 0.22
--     renamed/modified versions: min Jaccard similarity 0.53
--   Threshold sits in the middle of a 0.31-wide gap.
similarityThreshold :: Double
similarityThreshold = 0.25

syncNewAiBlogPosts :: FilePath -> FilePath -> IO Int
syncNewAiBlogPosts repoDir vaultDir = do
  repoExists <- doesDirectoryExist repoDir
  case repoExists of
    False -> pure 0
    True -> do
      createDirectoryIfMissing True vaultDir
      -- Read all vault file contents for similarity comparison
      vaultEntries <- listDirectory vaultDir
      let vaultMdFiles = filter isAiBlogPost vaultEntries
          vaultFilenames = fmap T.pack vaultMdFiles
      vaultContents <- traverse (\f -> TIO.readFile (vaultDir </> f)) vaultMdFiles
      -- Check each repo file against vault
      repoEntries <- listDirectory repoDir
      let repoMdFiles = filter isAiBlogPost repoEntries
      counts <- traverse (syncIfNew repoDir vaultDir vaultFilenames (zip vaultMdFiles vaultContents)) repoMdFiles
      pure (sum counts)
  where
    isAiBlogPost f = takeExtension f == ".md" && f /= "index.md" && f /= "AGENTS.md"

syncIfNew :: FilePath -> FilePath -> [Text] -> [(FilePath, Text)] -> FilePath -> IO Int
syncIfNew srcDir dstDir vaultFilenames vaultContents filename = do
  let fnameText = T.pack filename
  case fnameText `elem` vaultFilenames of
    True -> pure 0
    False -> do
      repoContent <- TIO.readFile (srcDir </> filename)
      let (bestScore, bestMatch) = findBestMatch repoContent vaultContents
      case bestScore >= similarityThreshold of
        True -> do
          logMsg $ "  ⏭️  Skipping " <> fnameText
            <> " (Jaccard " <> T.pack (showScore bestScore) <> " with " <> T.pack bestMatch <> ")"
          pure 0
        False -> do
          TIO.writeFile (dstDir </> filename) repoContent
          logMsg $ "  📄 New post → vault: " <> fnameText
            <> " (best Jaccard " <> T.pack (showScore bestScore) <> ")"
          pure 1

findBestMatch :: Text -> [(FilePath, Text)] -> (Double, FilePath)
findBestMatch repoContent = foldl pickBest (0.0, "(none)")
  where
    pickBest (bestScore, bestFile) (vaultFile, vaultContent) =
      let score = wordJaccardSimilarity repoContent vaultContent
      in case score > bestScore of
           True  -> (score, vaultFile)
           False -> (bestScore, bestFile)

showScore :: Double -> String
showScore d =
  let rounded = fromIntegral (round (d * 1000) :: Int) / 1000 :: Double
  in show rounded

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
  let (y, m, d) = parseYMD (unDateStr today)
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

runBlogSeries :: Manager -> FilePath -> FilePath -> Text -> IO ()
runBlogSeries manager repoRoot vaultDir seriesId = do
  let taskName = "blog-series:" <> seriesId
  logMsg $ "▶️  " <> taskName

  let mRunConfig = Map.lookup seriesId blogSeriesRunConfigs
  runConfig <- case mRunConfig of
    Just rc -> pure rc
    Nothing -> error $ "No run config for series: " <> T.unpack seriesId

  apiKey <- requireSecret "GEMINI_API_KEY"
  today <- todayPacific
  let todayText = unDateStr today

  -- 1. Copy vault posts for this series to local repo
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
      case existsForToday of
        True -> do
          logMsg $ "  ⏭️  Already generated for " <> todayText
          pure ()
        False -> pure ()

  -- Recheck after potential removal
  existsNow <- blogPostExistsForToday seriesDir todayText
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

runBackfillImages :: Manager -> FilePath -> FilePath -> IO ()
runBackfillImages manager repoRoot vaultDir = do
  logMsg "▶️  backfill-blog-images"

  today <- todayPacific
  let todayText = unDateStr today

  -- 1. Sync new AI blog posts from repo to vault (copy-if-missing only)
  let repoAiBlogDir = repoRoot </> "ai-blog"
      vaultAiBlogDir = vaultDir </> "ai-blog"
  newPostCount <- syncNewAiBlogPosts repoAiBlogDir vaultAiBlogDir
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
  let modifiedCount = length (filter (\r -> nlrModified r) navResults)
  logMsg $ "  🔗 Nav links: " <> T.pack (show modifiedCount) <> " files updated"

  -- 4. Add update links from image backfill results
  let reflectionsDir = vaultDir </> "reflections"
  imageUpdateLinks <- traverse (\f -> do
        title <- extractTitleFromFile (vaultDir </> T.unpack f)
        pure (UpdateLink f title ["🖼️ added image"])
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

runInternalLinking :: Manager -> FilePath -> IO ()
runInternalLinking manager vaultDir = do
  logMsg "▶️  internal-linking"

  envModel <- lookupEnvText "INTERNAL_LINKING_MODEL"
  let model = fromMaybe IL.defaultLinkingModel envModel
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
      today <- todayPacific
      let todayText = unDateStr today
          reflectionsDir = vaultDir </> "reflections"
      links <- traverse (\fr -> do
        title <- extractTitleFromFile (vaultDir </> T.unpack (IL.frRelativePath fr))
        let n = IL.frLinksAdded fr
            detail = "🔗 added " <> T.pack (show n) <> " internal link" <> (if n == 1 then "" else "s")
        pure (UpdateLink (IL.frRelativePath fr) title [detail])
        ) modifiedResults
      _ <- addUpdateLinksToReflection reflectionsDir todayText links
      pure ()

  logMsg "✅ internal-linking"

runSocialPosting :: Manager -> FilePath -> IO ()
runSocialPosting manager vaultDir = do
  logMsg "▶️  social-posting"
  autoPost manager vaultDir
  logMsg "✅ social-posting"

runAiFiction :: Manager -> FilePath -> IO ()
runAiFiction manager vaultDir = do
  logMsg "▶️  ai-fiction"

  apiKey <- requireSecret "GEMINI_API_KEY"
  today <- todayPacific
  let todayText = unDateStr today

  let reflectionsDir = vaultDir </> "reflections"
      reflectionPath = reflectionsDir </> T.unpack todayText <> ".md"

  exists <- doesFileExist reflectionPath
  case exists of
    False -> do
      logMsg $ "  📭 No reflection for " <> todayText <> ", skipping AI fiction"
      logMsg "✅ ai-fiction (skipped)"
    True -> do
      noteContent <- TIO.readFile reflectionPath
      case reflectionNeedsFiction noteContent of
        False -> do
          logMsg $ "  ✅ Reflection " <> todayText <> " already has AI fiction"
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
          logMsg $ "  ✏️  Updated " <> todayText <> ".md with AI fiction"

          logMsg "✅ ai-fiction"

runReflectionTitle :: Manager -> FilePath -> IO ()
runReflectionTitle manager vaultDir = do
  logMsg "▶️  reflection-title"

  apiKey <- requireSecret "GEMINI_API_KEY"
  today <- todayPacific
  let todayText = unDateStr today
  yesterday <- yesterdayPacific

  let reflectionsDir = vaultDir </> "reflections"

  -- Try today first, then yesterday
  todayDone <- tryTitleForDate manager apiKey vaultDir reflectionsDir todayText
  case todayDone of
    True -> pure ()
    False -> do
      logMsg $ "  📅 Checking yesterday (" <> yesterday <> ")..."
      _ <- tryTitleForDate manager apiKey vaultDir reflectionsDir yesterday
      pure ()

  logMsg "✅ reflection-title"

tryTitleForDate :: Manager -> Secret -> FilePath -> FilePath -> Text -> IO Bool
tryTitleForDate manager apiKey _vaultDir reflectionsDir date = do
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
          logMsg $ "  🏷️  Title written for " <> date
          pure True

-- ---------------------------------------------------------------------------
-- Task dispatch
-- ---------------------------------------------------------------------------

taskRunners :: Manager -> FilePath -> FilePath -> Map TaskId (IO ())
taskRunners manager repoRoot vaultDir = Map.fromList
  [ (BlogSeriesChickieLoo, runBlogSeries manager repoRoot vaultDir "chickie-loo")
  , (BlogSeriesAutoBlogZero, runBlogSeries manager repoRoot vaultDir "auto-blog-zero")
  , (BlogSeriesSystemsForPublicGood, runBlogSeries manager repoRoot vaultDir "systems-for-public-good")
  , (BackfillBlogImages, runBackfillImages manager repoRoot vaultDir)
  , (InternalLinking, runInternalLinking manager vaultDir)
  , (SocialPosting, runSocialPosting manager vaultDir)
  , (AiFiction, runAiFiction manager vaultDir)
  , (ReflectionTitle, runReflectionTitle manager vaultDir)
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
      -- Pull vault ONCE at the start
      creds <- getObsidianCreds
      logMsg "📥 Pulling Obsidian vault..."
      vaultDir <- syncObsidianVault creds
      logMsg $ "📂 Vault ready at " <> T.pack vaultDir

      let runners = taskRunners manager repoRoot vaultDir
      results <- runTasks runners tasks []

      -- Push vault ONCE at the end
      logMsg "📤 Pushing Obsidian vault..."
      pushObsidianVault vaultDir (ocAuthToken creds)
      logMsg "📤 Vault pushed"

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
