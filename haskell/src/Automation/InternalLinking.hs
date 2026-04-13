{-# LANGUAGE OverloadedStrings #-}

module Automation.InternalLinking
  ( FileResult (..)
  , LinkingResult (..)
  , defaultLinkingModel
  , indexableDirs
  , traversableDirs
  , extractBody
  , alreadyAnalyzed
  , applyReplacements
  , buildIdentificationPrompt
  , processFile
  , run
  ) where

import qualified Automation.InternalLinking.CandidateDiscovery as CD
import Automation.InternalLinking.LinkExtraction
  ( bfsTraversal
  , splitSlash
  , joinSlash
  )
import Automation.InternalLinking.Masking (maskProtectedRegions)

import Automation.Frontmatter (YamlValue (..), parseFrontmatter, renderYamlValue)
import qualified Automation.Gemini as Gemini
import Automation.Json (decode)
import Automation.PacificTime (formatDay, todayPacificDay)
import Automation.Types (Secret (..), RelativePath, unRelativePath, unTitle, mkRelativePath)
import Control.Concurrent (threadDelay)
import Control.Monad (when)
import qualified Data.ByteString.Lazy as LBS
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.List (sortBy)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe)
import Data.Ord (Down (..))
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Text.IO as TIO
import Network.HTTP.Client (Manager)
import System.Directory (doesFileExist)
import System.Environment (lookupEnv)
import System.FilePath (takeDirectory, (</>))


defaultLinkingModel :: Gemini.Model
defaultLinkingModel = Gemini.Gemini31FlashLite

indexableDirs :: [Text]
indexableDirs =
  [ "books", "articles", "topics", "software", "people"
  , "products", "games", "videos", "presentations", "tools"
  ]

traversableDirs :: [Text]
traversableDirs =
  indexableDirs
    <> ["reflections", "chickie-loo", "auto-blog-zero", "systems-for-public-good"]


data FileResult = FileResult
  { relativePath   :: RelativePath
  , modified       :: Bool
  , linksAdded     :: Int
  , usedInference  :: Bool
  } deriving (Show, Eq)

data LinkingResult = LinkingResult
  { filesVisited    :: Int
  , filesModified   :: Int
  , totalLinksAdded :: Int
  , filesSkipped    :: Int
  , fileResults     :: [FileResult]
  } deriving (Show, Eq)


extractBody :: Text -> Text
extractBody content =
  let ls = T.splitOn "\n" content
  in case ls of
    (first : rest)
      | T.strip first == "---" ->
          case break (\l -> T.strip l == "---") rest of
            (_, [])          -> content
            (_, _ : bodyLs)  -> T.intercalate "\n" bodyLs
    _ -> content

alreadyAnalyzed :: Text -> Bool
alreadyAnalyzed content =
  let (fm, _) = parseFrontmatter content
  in case Map.lookup "force_analyze_links" fm of
    Just "true" -> False
    _           -> Map.member "link_analysis_model" fm


applyReplacements :: Text -> [CD.LinkCandidate] -> [Bool] -> Text
applyReplacements content candidates validations =
  let validPairs = filter snd (zip candidates validations)
      sorted     = sortBy (\(a, _) (b, _) -> compare (Down (CD.position a)) (Down (CD.position b)))
                     validPairs
  in foldl' applyOne content (fmap fst sorted)
  where
    applyOne :: Text -> CD.LinkCandidate -> Text
    applyOne acc candidate =
      let pos    = CD.position candidate
          len    = T.length (CD.matchedText candidate)
          before = T.take pos acc
          after  = T.drop (pos + len) acc
          wl     = CD.formatWikilink (CD.entry candidate)
      in before <> wl <> after


updateFrontmatterFields :: FilePath -> [(Text, YamlValue)] -> IO ()
updateFrontmatterFields filePath fields = do
  exists <- doesFileExist filePath
  when exists $ do
    raw <- TIO.readFile filePath
    let ls = T.splitOn "\n" raw
    case ls of
      (first : rest)
        | T.strip first == "---" ->
            case break (\l -> T.strip l == "---") rest of
              (_, []) -> pure ()
              (fmLines, closingDash : bodyLines) ->
                let updatedFm = foldl' upsertField fmLines fields
                in TIO.writeFile filePath
                     (T.intercalate "\n" (first : updatedFm <> [closingDash] <> bodyLines))
      _ -> do
        let entries = T.intercalate "\n" $ fmap (\(k, v) -> k <> ": " <> renderYamlValue v) fields
        TIO.writeFile filePath ("---\n" <> entries <> "\n---\n" <> raw)

upsertField :: [Text] -> (Text, YamlValue) -> [Text]
upsertField ls (key, val) =
  let newLine   = key <> ": " <> renderYamlValue val
      pat       = T.pack (T.unpack key <> ":")
      didReplace = any (matchesKey pat) ls
      replaced = replaceWithContinuation pat newLine ls
  in if didReplace then replaced else ls <> [newLine]
  where
    matchesKey :: Text -> Text -> Bool
    matchesKey p line = T.isPrefixOf p (T.stripStart line)

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

recordLinkAnalysis :: FilePath -> Gemini.Model -> Text -> IO ()
recordLinkAnalysis filePath model timestamp =
  updateFrontmatterFields filePath
    [ ("link_analysis_model", YamlText (Gemini.modelToText model))
    , ("link_analysis_time", YamlText timestamp)
    , ("force_analyze_links", YamlBool False)
    ]


processFile :: Manager -> Secret -> Gemini.Model -> FilePath -> [CD.ContentEntry] -> IO (Maybe FileResult)
processFile manager apiKey model filePath index = do
  let contentDir      = takeDirectory (takeDirectory filePath)
      fileRelativePath = makeRelPathFromContentDir contentDir filePath
  case mkRelativePath (T.pack fileRelativePath) of
    Left reason -> do
      putStrLn $ "  ⚠️  Skipping " <> filePath <> ": " <> T.unpack reason
      pure Nothing
    Right relPath -> do
      content <- TIO.readFile filePath
      if alreadyAnalyzed content
        then pure $ Just FileResult
          { relativePath = relPath
          , modified     = False
          , linksAdded   = 0
          , usedInference = False
          }
        else do
          let body = extractBody content
              eligibleBooks = filter
                (\e -> CD.relativePath e /= relPath
                    && not (CD.contentAlreadyLinksTo content e))
                index
          case eligibleBooks of
            [] -> do
              timestamp <- nowIso
              recordLinkAnalysis filePath model timestamp
              pure $ Just FileResult
                { relativePath = relPath
                , modified     = False
                , linksAdded   = 0
                , usedInference = False
                }
            _ -> do
              geminiResult <- identifyBooksWithGemini manager apiKey model body eligibleBooks
              timestamp <- nowIso
              recordLinkAnalysis filePath model timestamp
              case geminiResult of
                Left _err -> pure $ Just FileResult
                  { relativePath = relPath
                  , modified     = False
                  , linksAdded   = 0
                  , usedInference = True
                  }
                Right identifiedPaths
                  | null identifiedPaths -> pure $ Just FileResult
                      { relativePath = relPath
                      , modified     = False
                      , linksAdded   = 0
                      , usedInference = True
                      }
                  | otherwise -> do
                      let identifiedSet = Set.fromList identifiedPaths
                      contentAfterFm <- TIO.readFile filePath
                      let masked          = maskProtectedRegions contentAfterFm
                          identifiedIndex = filter (\e -> Set.member (unRelativePath (CD.relativePath e)) identifiedSet) index
                          candidates      = CD.findLinkCandidates identifiedIndex contentAfterFm masked relPath
                      case candidates of
                        [] -> pure $ Just FileResult
                          { relativePath = relPath
                          , modified     = False
                          , linksAdded   = 0
                          , usedInference = True
                          }
                        _  -> do
                          let validations = replicate (length candidates) True
                              newContent  = applyReplacements contentAfterFm candidates validations
                          TIO.writeFile filePath newContent
                          putStrLn $ "  ✏️  " <> fileRelativePath <> ": "
                            <> show (length candidates) <> " link(s) applied"
                          pure $ Just FileResult
                            { relativePath = relPath
                            , modified     = True
                            , linksAdded   = length candidates
                            , usedInference = True
                            }

makeRelPathFromContentDir :: FilePath -> FilePath -> FilePath
makeRelPathFromContentDir contentDir filePath =
  joinSlash $ drop (length (splitSlash contentDir)) (splitSlash filePath)

nowIso :: IO Text
nowIso = do
  today <- todayPacificDay
  pure (formatDay today <> "T00:00:00Z")


run :: Manager -> Gemini.Model -> FilePath -> IO LinkingResult
run manager model contentDir = do
  putStrLn $ "🔗 Internal linking: model=" <> T.unpack (Gemini.modelToText model)

  index <- CD.buildContentIndex contentDir
  putStrLn $ "  📚 Index: " <> show (length index) <> " books"

  filesToVisit <- bfsTraversal contentDir
  putStrLn $ "  🔍 BFS: " <> show (length filesToVisit) <> " files reachable"

  apiKey <- lookupSecret
  results <- processFiles manager apiKey model contentDir index filesToVisit

  let modifiedCount  = length $ filter modified results
      totalLinks     = sum $ fmap linksAdded results
      skippedCount   = length $ filter (\r -> not (modified r) && linksAdded r == 0) results

  let result = LinkingResult
        { filesVisited    = length filesToVisit
        , filesModified   = modifiedCount
        , totalLinksAdded = totalLinks
        , filesSkipped    = skippedCount
        , fileResults     = results
        }

  putStrLn $ "  🏁 Complete: " <> show (filesVisited result) <> " visited, "
    <> show modifiedCount <> " modified, " <> show totalLinks <> " links added, "
    <> show skippedCount <> " skipped"

  pure result

processFiles :: Manager -> Secret -> Gemini.Model -> FilePath -> [CD.ContentEntry] -> [Text] -> IO [FileResult]
processFiles manager apiKey model contentDir index filesToVisit = do
  inferenceRef <- newIORef (0 :: Int)
  resultRef    <- newIORef ([] :: [FileResult])
  go inferenceRef resultRef filesToVisit
  reverse <$> readIORef resultRef
  where
    maxInferencePerRun :: Int
    maxInferencePerRun = 10

    go :: IORef Int -> IORef [FileResult] -> [Text] -> IO ()
    go _ _ [] = pure ()
    go infRef resRef (relPath : rest) = do
      let filePath = contentDir </> T.unpack relPath
      mFileResult <- processFile manager apiKey model filePath index
      case mFileResult of
        Nothing -> go infRef resRef rest
        Just fileResult -> do
          modifyIORef' resRef (fileResult :)
          if usedInference fileResult
            then do
              infCount <- readIORef infRef
              modifyIORef' infRef (+ 1)
              let newCount = infCount + 1
              if newCount >= maxInferencePerRun
                then
                  putStrLn $ "  ⏹️  Inference limit reached: " <> show newCount <> "/" <> show maxInferencePerRun
                else go infRef resRef rest
            else go infRef resRef rest

lookupSecret :: IO Secret
lookupSecret = do
  mKey <- lookupEnv "GEMINI_API_KEY"
  pure $ Secret (maybe "" T.pack mKey)


maxGeminiRetries :: Int
maxGeminiRetries = 3

initialBackoffUs :: Int
initialBackoffUs = 5_000_000

maxBackoffUs :: Int
maxBackoffUs = 60_000_000

buildIdentificationPrompt :: Text -> [CD.ContentEntry] -> Text
buildIdentificationPrompt fileBody bookEntries =
  let formatBookLine e =
        let mainNote = case CD.extractMainTitle (unTitle (CD.plainTitle e)) of
              Just mt -> " (also known as \"" <> mt <> "\")"
              Nothing -> ""
        in "- \"" <> unTitle (CD.plainTitle e) <> "\"" <> mainNote <> " (" <> unRelativePath (CD.relativePath e) <> ")"
      bookList = T.intercalate "\n" $ fmap formatBookLine bookEntries
      systemPrompt = T.intercalate "\n"
        [ "You are a precise editorial assistant for a knowledge base of book reports. Your job is to identify genuine book references in a document."
        , ""
        , "You will receive:"
        , "1. The body text of a document."
        , "2. A list of book titles and their file paths."
        , ""
        , "Your task: Determine which books from the list are genuinely referenced in the document AS BOOKS (literary works). This means the text is discussing, recommending, citing, or listing the book itself — not merely using a word that happens to match a book title."
        , ""
        , "Rules:"
        , "- Return the relativePath of each book that is genuinely referenced as a book."
        , "- A book reference may use the main title without the subtitle."
        , "- DO NOT include a book if the matching word or phrase is used in a generic context."
        , "- DO include a book when the text explicitly discusses, recommends, or cites it as a literary work."
        , "- Be conservative: when in doubt, do NOT include the book."
        , ""
        , "Return ONLY a valid JSON array of relativePath strings for books genuinely referenced. Example: [\"books/thinking-fast-and-slow.md\", \"books/deep-learning.md\"]"
        , "If no books are genuinely referenced, return an empty array: []"
        , "No other text, no explanation, no markdown formatting."
        ]
  in systemPrompt <> "\n\nAvailable books:\n" <> bookList <> "\n\nDocument body:\n" <> fileBody

identifyBooksWithGemini :: Manager -> Secret -> Gemini.Model -> Text -> [CD.ContentEntry] -> IO (Either Text [Text])
identifyBooksWithGemini _ _ _ _ [] = pure (Right [])
identifyBooksWithGemini manager apiKey model fileBody bookEntries = do
  let prompt = buildIdentificationPrompt fileBody bookEntries
  retryLoop manager apiKey model prompt 0 initialBackoffUs

retryLoop :: Manager -> Secret -> Gemini.Model -> Text -> Int -> Int -> IO (Either Text [Text])
retryLoop manager apiKey model prompt attempt backoff = do
  result <- Gemini.generateContent manager Gemini.Request
    { Gemini.grPrompt           = prompt
    , Gemini.grModel            = model
    , Gemini.grApiKey           = apiKey
    , Gemini.grGenerationConfig = Gemini.GenerationConfig
        { Gemini.gcTemperature     = 0.0
        , Gemini.gcMaxOutputTokens = 1024
        }
    }
  case result of
    Right response ->
      pure (parseGeminiBookPaths (Gemini.responseText response))
    Left err
      | Gemini.isRateLimitError err && attempt < maxGeminiRetries -> do
          putStrLn $ "  ⏳ Rate limit, retry " <> show (attempt + 1) <> "/" <> show maxGeminiRetries
            <> " in " <> show (backoff `div` 1_000_000) <> "s"
          threadDelay backoff
          retryLoop manager apiKey model prompt (attempt + 1) (min (backoff * 2) maxBackoffUs)
      | Gemini.isQuotaExhaustedError err ->
          pure (Left ("QuotaExhausted: " <> T.pack (show err)))
      | otherwise ->
          pure (Left (T.pack (show err)))

parseGeminiBookPaths :: Text -> Either Text [Text]
parseGeminiBookPaths raw =
  let cleaned = extractJsonArrayText raw
  in case decode (encodeToLbs cleaned) :: Maybe [Text] of
    Just paths -> Right paths
    Nothing    -> Left ("Failed to parse Gemini response as JSON array: " <> raw)
  where
    encodeToLbs :: Text -> LBS.ByteString
    encodeToLbs = LBS.fromStrict . TE.encodeUtf8

extractJsonArrayText :: Text -> Text
extractJsonArrayText txt =
  let stripped = T.strip txt
      noFences = stripCodeFences stripped
  in case (T.findIndex (== '[') noFences, findLastIndex (== ']') noFences) of
    (Just start, Just end) -> T.take (end - start + 1) (T.drop start noFences)
    _                      -> noFences

stripCodeFences :: Text -> Text
stripCodeFences txt =
  let noStart = fromMaybe txt (T.stripPrefix "```json" txt >>= Just . T.strip)
      noStart' = fromMaybe noStart (T.stripPrefix "```" noStart >>= Just . T.strip)
  in fromMaybe noStart' (T.stripSuffix "```" noStart' >>= Just . T.strip)

findLastIndex :: (Char -> Bool) -> Text -> Maybe Int
findLastIndex predicate txt = go Nothing 0 (T.unpack txt)
  where
    go acc _ [] = acc
    go acc i (c : cs)
      | predicate c = go (Just i) (i + 1) cs
      | otherwise   = go acc (i + 1) cs
