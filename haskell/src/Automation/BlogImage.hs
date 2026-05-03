module Automation.BlogImage
  ( BackfillConfig (..)
  , BackfillResult (..)
  , processNote
  , backfillImages
  , syncAttachmentsDir
  , updateFrontmatterFields
  , applyField
  , notePathToImageBaseName
  , resolveUniqueImageName
  , sanitizeForYaml
  , shouldRegenerateImage
  , parseDateFromFrontmatter
  , undatedFileFallback
  ) where

import Control.Applicative ((<|>))
import Control.Exception (SomeException, catch)
import Control.Monad (when)
import qualified Data.ByteString.Lazy as LBS
import Data.Char (isAlphaNum, toLower)
import Data.Foldable (asum)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Data.Time (Day, defaultTimeLocale, formatTime, fromGregorian, getCurrentTime)
import Data.Time.Format (parseTimeM)
import Network.HTTP.Client (Manager)
import System.Directory
  ( copyFile
  , createDirectoryIfMissing
  , doesDirectoryExist
  , doesFileExist
  , listDirectory
  )
import System.FilePath ((</>), takeBaseName, takeDirectory, takeExtension)

import Automation.PacificTime (todayPacificDay)
import Automation.Frontmatter (YamlValue (..), parseFrontmatter, renderYamlValue)

import Automation.BlogImage.TitleExtraction (extractTitle)
import Automation.BlogImage.ContentDirectory
  ( ContentDirectory (..)
  , contentDirectoryToText
  )
import Automation.BlogImage.Eligibility
  ( BackfillCandidate (..)
  , CandidateEligibility (..)
  , checkCandidateEligibility
  , hasEmbeddedImage
  , parseDateFromFilename
  , shouldHaveImage
  , shouldRegenerateImage
  )
import Automation.BlogImage.Markdown
  ( buildImagePrompt
  , insertImageEmbed
  , removeImageEmbed
  )
import Automation.BlogImage.Provider
  ( ImageGenerationResult (..)
  , ImageProviderConfig (..)
  , describeContent
  , generateImage
  , isDailyQuotaError
  , isProviderUnavailableError
  , isQuotaError
  , mimeTypeToExtension
  , providerName
  )

data BackfillConfig = BackfillConfig
  { backfillRepoRoot       :: FilePath
  , backfillContentDirs    :: [ContentDirectory]
  , backfillAttachmentsDir :: FilePath
  , backfillProviders      :: [ImageProviderConfig]
  , backfillMaxImages      :: Int
  }

data BackfillResult = BackfillResult
  { imagesGenerated :: Int
  , filesUpdated    :: Int
  , filesSkipped    :: Int
  , modifiedFiles   :: [Text]
  , errors          :: [Text]
  } deriving (Show, Eq)

notePathToImageBaseName :: FilePath -> Text
notePathToImageBaseName notePath =
  let dir = T.pack (takeBaseName (takeDirectory notePath))
      stem = T.pack (takeBaseName notePath)
      raw = T.toLower (dir <> "-" <> stem)
  in trimDashes (collapseDashes (replaceNonAlphaNumDash raw))

replaceNonAlphaNumDash :: Text -> Text
replaceNonAlphaNumDash = T.map (\c -> if isAlphaNum c || c == '-' then c else '-')

collapseDashes :: Text -> Text
collapseDashes = T.intercalate "-" . filter (not . T.null) . T.splitOn "-"

trimDashes :: Text -> Text
trimDashes = T.dropWhile (== '-') . T.dropWhileEnd (== '-')

sanitizeForYaml :: Text -> Text
sanitizeForYaml =
  T.strip
    . collapseSpaces
    . T.filter (`notElem` ['\"', '\'', '\\', '`'])
    . T.map (\c -> if c == '\n' || c == '\r' || c == '\t' then ' ' else c)

collapseSpaces :: Text -> Text
collapseSpaces = T.intercalate " " . filter (not . T.null) . T.splitOn " "

updateFrontmatterFields :: Text -> [(Text, YamlValue)] -> Text
updateFrontmatterFields content fields =
  let contentLines = T.splitOn "\n" content
  in case contentLines of
    (first : rest)
      | T.strip first == "---" ->
          case break (\l -> T.strip l == "---") rest of
            (_, []) -> content
            (frontmatterLines, _ : body) ->
              let updatedFrontmatter = foldl' applyField frontmatterLines fields
              in T.intercalate "\n" (["---"] <> updatedFrontmatter <> ["---"] <> body)
    _ ->
      let frontmatterLines = fmap (\(k, v) -> k <> ": " <> renderYamlValue v) fields
      in T.intercalate "\n" (["---"] <> frontmatterLines <> ["---", content])

applyField :: [Text] -> (Text, YamlValue) -> [Text]
applyField frontmatterLines (key, value) =
  let keyPrefix = key <> ":"
      newLine = key <> ": " <> renderYamlValue value
      keyExists = any (\l -> keyPrefix `T.isPrefixOf` T.stripStart l) frontmatterLines
      replaced = replaceWithContinuation keyPrefix newLine frontmatterLines
  in if keyExists then replaced else frontmatterLines <> [newLine]

replaceWithContinuation :: Text -> Text -> [Text] -> [Text]
replaceWithContinuation _ _ [] = []
replaceWithContinuation keyPrefix newLine (l : rest)
  | keyPrefix `T.isPrefixOf` T.stripStart l =
      newLine : dropContinuationLines rest
  | otherwise = l : replaceWithContinuation keyPrefix newLine rest

dropContinuationLines :: [Text] -> [Text]
dropContinuationLines [] = []
dropContinuationLines (l : rest)
  | isContinuationLine l = dropContinuationLines rest
  | otherwise = l : rest

isContinuationLine :: Text -> Bool
isContinuationLine l = not (T.null l) && T.isPrefixOf " " l

extractFrontmatterValue :: Text -> Text -> Maybe Text
extractFrontmatterValue content key =
  let (frontmatter, _) = parseFrontmatter content
  in Map.lookup key frontmatter

resolveUniqueImageName :: Text -> Text -> FilePath -> IO Text
resolveUniqueImageName baseName extension attachmentsDir = do
  let candidate = baseName <> extension
  exists <- doesFileExist (attachmentsDir </> T.unpack candidate)
  if not exists
    then pure candidate
    else findUnique (2 :: Int)
  where
    findUnique n = do
      let name = baseName <> "-" <> T.pack (show n) <> extension
      exists <- doesFileExist (attachmentsDir </> T.unpack name)
      if not exists
        then pure name
        else findUnique (n + 1)

processNote :: Manager -> ImageProviderConfig -> FilePath -> FilePath -> IO ImageGenerationResult
processNote manager provider notePath attachmentsDir = do
  rawContent <- TIO.readFile notePath
  content <- handleRegeneration notePath attachmentsDir rawContent
  let skippedResult = ImageGenerationResult True Nothing Nothing Nothing
  if hasEmbeddedImage content
    then pure skippedResult
    else do
      let title = extractTitle content
      if T.null title
        then pure skippedResult
        else do
          let baseName = notePathToImageBaseName notePath
          if T.null baseName
            then pure skippedResult
            else generateAndSaveImage manager provider notePath attachmentsDir content baseName

handleRegeneration :: FilePath -> FilePath -> Text -> IO Text
handleRegeneration notePath _attachmentsDir content =
  if shouldRegenerateImage content
    then do
      let (cleaned, _) = removeImageEmbed content
          updated = updateFrontmatterFields cleaned
            [("regenerate_image", YamlBool False), ("image_prompt", YamlText "")]
      TIO.writeFile notePath updated
      pure updated
    else pure content

generateAndSaveImage
  :: Manager -> ImageProviderConfig -> FilePath -> FilePath -> Text -> Text -> IO ImageGenerationResult
generateAndSaveImage manager provider notePath attachmentsDir content baseName = do
  promptResult <- resolvePrompt manager provider content
  case promptResult of
    Left err -> do
      putStrLn $ "⚠️ Failed to resolve prompt: " <> T.unpack err
      pure $ ImageGenerationResult True Nothing Nothing Nothing
    Right prompt -> do
      imageResult <- generateImage manager provider prompt
      case imageResult of
        Left err -> do
          putStrLn $ "❌ Image generation failed: " <> T.unpack err
          pure $ ImageGenerationResult True Nothing Nothing Nothing
        Right (imageData, mimeType) -> do
          let extension = mimeTypeToExtension mimeType
          imageName <- resolveUniqueImageName baseName extension attachmentsDir
          let imagePath = attachmentsDir </> T.unpack imageName
          createDirectoryIfMissing True attachmentsDir
          LBS.writeFile imagePath imageData
          let withEmbed = insertImageEmbed content imageName
          now <- formatTimestamp
          let withMeta = updateFrontmatterFields withEmbed
                [ ("image_date", YamlText now)
                , ("image_model", YamlText (ipcModel provider))
                , ("image_prompt", YamlText (sanitizeForYaml prompt))
                ]
          TIO.writeFile notePath withMeta
          pure $ ImageGenerationResult False (Just imagePath) (Just imageName) (Just prompt)

resolvePrompt :: Manager -> ImageProviderConfig -> Text -> IO (Either Text Text)
resolvePrompt manager provider content =
  case extractFrontmatterValue content "image_prompt" of
    Just cached | not (T.null (T.strip cached)) -> pure (Right cached)
    _ -> case ipcDescriber provider of
      Just describer -> do
        result <- describeContent manager describer content
        pure $ fmap sanitizeForYaml result
      Nothing -> pure $ Right (buildImagePrompt content)

formatTimestamp :: IO Text
formatTimestamp =
  T.pack . formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" <$> getCurrentTime

backfillImages :: Manager -> BackfillConfig -> IO BackfillResult
backfillImages manager config = do
  today <- todayPacificDay
  candidates <- collectCandidates (backfillRepoRoot config) (backfillContentDirs config) today
  putStrLn $ "📋 Candidates: " <> show (length candidates) <> " notes need images"
         <> " | providers: " <> show (length (backfillProviders config))
         <> " | max: " <> show (backfillMaxImages config)
  processWithProviders manager config candidates 0 emptyResult

emptyResult :: BackfillResult
emptyResult = BackfillResult 0 0 0 [] []

collectCandidates :: FilePath -> [ContentDirectory] -> Day -> IO [BackfillCandidate]
collectCandidates repoRoot contentDirectories today = do
  candidateLists <- traverse (collectFromDirectory repoRoot today) contentDirectories
  let allCandidates = concat candidateLists
      sorted = sortByDateDesc allCandidates
  pure sorted

collectFromDirectory :: FilePath -> Day -> ContentDirectory -> IO [BackfillCandidate]
collectFromDirectory repoRoot today directory = do
  let directoryText = contentDirectoryToText directory
      directoryPath = repoRoot </> T.unpack directoryText
  exists <- doesDirectoryExist directoryPath
  if exists
    then do
      entries <- listDirectory directoryPath
      let contentFiles = filter shouldHaveImage (fmap T.pack entries)
          sortedFiles = sortByTextDesc contentFiles
      concat <$> traverse (checkCandidate directoryPath directory today) sortedFiles
    else do
      putStrLn $ "📁 Directory missing: " <> T.unpack directoryText
      pure []

checkCandidate :: FilePath -> ContentDirectory -> Day -> Text -> IO [BackfillCandidate]
checkCandidate directoryPath directory today filename = do
  let fileDate = parseDateFromFilename filename
      filePath = directoryPath </> T.unpack filename
  case fileDate of
    Just date | directory == Reflections && date > today -> pure []
    _ -> do
      content <- TIO.readFile filePath
      case checkCandidateEligibility directory today filename content of
        Ineligible _              -> pure []
        Eligible requiresRegeneration ->
          let (frontmatter, _) = parseFrontmatter content
              candidateDate = fromMaybe undatedFileFallback
                (fileDate <|> parseDateFromFrontmatter frontmatter)
          in pure [BackfillCandidate filePath directory filename
                                    candidateDate requiresRegeneration]

parseDateFromFrontmatter :: Map.Map Text Text -> Maybe Day
parseDateFromFrontmatter frontmatter =
  asum (fmap tryField ["updated", "modified", "date", "created"])
  where
    tryField field = Map.lookup field frontmatter >>= parseDateValue
    parseDateValue value = parseTimeM True defaultTimeLocale "%Y-%m-%d" (T.unpack (T.take 10 value))

undatedFileFallback :: Day
undatedFileFallback = fromGregorian 1970 1 1

sortByDateDesc :: [BackfillCandidate] -> [BackfillCandidate]
sortByDateDesc = foldl' insertSorted []
  where
    insertSorted [] c = [c]
    insertSorted (x : xs) c
      | date c >= date x = c : x : xs
      | otherwise        = x : insertSorted xs c

sortByTextDesc :: [Text] -> [Text]
sortByTextDesc = foldl' ins []
  where
    ins [] t = [t]
    ins (x : xs) t
      | t >= x    = t : x : xs
      | otherwise  = x : ins xs t

processWithProviders
  :: Manager -> BackfillConfig -> [BackfillCandidate]
  -> Int -> BackfillResult -> IO BackfillResult
processWithProviders _ _ [] _ result = do
  putStrLn $ "📭 No more candidates | generated: " <> show (imagesGenerated result)
          <> " | skipped: " <> show (filesSkipped result)
          <> " | errors: " <> show (length (errors result))
  pure result
processWithProviders _ config _ _ result
  | null (backfillProviders config) = do
      putStrLn "🚫 No providers available"
      pure result { errors = errors result <> ["No providers available"] }
processWithProviders _manager config _candidates providerIdx result
  | providerIdx >= length (backfillProviders config) = do
      putStrLn $ "🛑 All providers exhausted | generated: " <> show (imagesGenerated result)
             <> " | errors: " <> show (length (errors result))
      pure result { errors = errors result <> ["All providers exhausted"] }
  | imagesGenerated result >= backfillMaxImages config = do
      putStrLn $ "🎯 Max images reached: " <> show (imagesGenerated result)
             <> "/" <> show (backfillMaxImages config)
      pure result
processWithProviders manager config (candidate : rest) providerIdx result = do
  let provider = backfillProviders config !! providerIdx
      action = if requiresRegeneration candidate then "Regenerating" else "Generating"
      progress = show (imagesGenerated result + 1) <> "/" <> show (backfillMaxImages config)
      directoryLabel = T.unpack (contentDirectoryToText (directory candidate))
  putStrLn $ "🎨 [" <> progress <> "] " <> action <> " image for "
          <> directoryLabel <> "/" <> T.unpack (filename candidate)
          <> " via " <> T.unpack (providerName (ipcProvider provider))
  genResult <- tryGenerate manager provider candidate (backfillAttachmentsDir config)
  case genResult of
    Right imgResult
      | not (igrSkipped imgResult) -> do
          putStrLn $ "✅ Generated: " <> maybe "?" T.unpack (igrImageName imgResult)
          let relativePath = contentDirectoryToText (directory candidate) <> "/" <> filename candidate
              newResult = result
                { imagesGenerated = imagesGenerated result + 1
                , filesUpdated = filesUpdated result + 1
                , modifiedFiles = modifiedFiles result <> [relativePath]
                }
          if imagesGenerated newResult >= backfillMaxImages config
            then do
              putStrLn $ "🎯 Max images reached: " <> show (imagesGenerated newResult)
                     <> "/" <> show (backfillMaxImages config)
              pure newResult
            else processWithProviders manager config rest providerIdx newResult
      | otherwise -> do
          putStrLn $ "⏭️  Skipped: " <> directoryLabel <> "/" <> T.unpack (filename candidate)
          let newResult = result { filesSkipped = filesSkipped result + 1 }
          processWithProviders manager config rest providerIdx newResult
    Left err
      | isDailyQuotaError err || isQuotaError err || isProviderUnavailableError err -> do
          putStrLn $ "⚠️  Quota/unavailable on " <> T.unpack (providerName (ipcProvider provider)) <> ": " <> T.unpack err
          let nextIdx = providerIdx + 1
          if nextIdx < length (backfillProviders config)
            then do
              let nextProvider = backfillProviders config !! nextIdx
              putStrLn $ "🔄 Switching to provider " <> show (nextIdx + 1)
                     <> "/" <> show (length (backfillProviders config))
                     <> ": " <> T.unpack (providerName (ipcProvider nextProvider))
              processWithProviders manager config (candidate : rest) nextIdx result
            else do
              putStrLn $ "🛑 All " <> show (length (backfillProviders config)) <> " providers exhausted"
              pure result { errors = errors result <> [err] }
      | otherwise -> do
          putStrLn $ "❌ Error on " <> directoryLabel <> "/" <> T.unpack (filename candidate)
                  <> ": " <> T.unpack err
          let newResult = result { errors = errors result <> [err] }
          processWithProviders manager config rest providerIdx newResult

tryGenerate
  :: Manager -> ImageProviderConfig -> BackfillCandidate -> FilePath
  -> IO (Either Text ImageGenerationResult)
tryGenerate manager provider candidate attachmentsDir =
  safeIO $ processNote manager provider (filePath candidate) attachmentsDir

safeIO :: IO a -> IO (Either Text a)
safeIO action =
  fmap Right action `catch` handler
  where
    handler :: SomeException -> IO (Either Text a)
    handler e = pure $ Left $ T.pack (show e)

syncAttachmentsDir :: FilePath -> FilePath -> IO ()
syncAttachmentsDir srcDir dstDir = do
  srcExists <- doesDirectoryExist srcDir
  when srcExists $ do
    createDirectoryIfMissing True dstDir
    entries <- listDirectory srcDir
    let imageFiles = filter isImageFile entries
    mapM_ (syncIfMissing srcDir dstDir) imageFiles

syncIfMissing :: FilePath -> FilePath -> FilePath -> IO ()
syncIfMissing srcDir dstDir filename = do
  let dst = dstDir </> filename
  exists <- doesFileExist dst
  if exists
    then pure ()
    else copyFile (srcDir </> filename) dst

isImageFile :: FilePath -> Bool
isImageFile f =
  let ext = fmap toLower (takeExtension f)
  in ext `elem` [".jpg", ".jpeg", ".png", ".gif", ".webp"]
