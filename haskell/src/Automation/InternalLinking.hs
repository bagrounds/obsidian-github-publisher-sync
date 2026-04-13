{-# LANGUAGE OverloadedStrings #-}

module Automation.InternalLinking
  ( -- * Re-exports from sub-modules for backward compatibility
    -- ** Masking
    maskProtectedRegions
    -- ** LinkExtraction
  , extractLinkedPaths
  , findMostRecentReflection
  , bfsTraversal
  , normalizeFilePath
    -- ** CandidateDiscovery
  , ContentEntry (..)
  , LinkCandidate (..)
  , linkableDirs
  , stripEmojis
  , escapeRegex
  , formatWikilink
  , extractContext
  , extractMainTitle
  , contentAlreadyLinksTo
  , buildContentIndex
  , findLinkCandidates
    -- ** GeminiIntegration
  , buildIdentificationPrompt
  , identifyBooksWithGemini
    -- * Defined in this module
  , FileResult (..)
  , LinkingResult (..)
  , defaultLinkingModel
  , indexableDirs
  , traversableDirs
  , extractBody
  , alreadyAnalyzed
  , applyReplacements
  , processFile
  , run
  ) where

import Automation.InternalLinking.CandidateDiscovery
  ( ContentEntry (..)
  , LinkCandidate (..)
  , linkableDirs
  , stripEmojis
  , escapeRegex
  , formatWikilink
  , extractContext
  , extractMainTitle
  , contentAlreadyLinksTo
  , buildContentIndex
  , findLinkCandidates
  )
import Automation.InternalLinking.GeminiIntegration
  ( buildIdentificationPrompt
  , identifyBooksWithGemini
  )
import Automation.InternalLinking.LinkExtraction
  ( extractLinkedPaths
  , findMostRecentReflection
  , bfsTraversal
  , normalizeFilePath
  , splitSlash
  , joinSlash
  )
import Automation.InternalLinking.Masking (maskProtectedRegions)

import Automation.PacificTime (formatDay, todayPacificDay)
import Automation.Frontmatter (YamlValue (..), parseFrontmatter, renderYamlValue)
import qualified Automation.Gemini as Gemini
import Automation.Types (Secret (..), RelativePath, unRelativePath, mkRelativePath)
import Control.Monad (when)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.List (sortBy)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Ord (Down (..))
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Network.HTTP.Client (Manager)
import System.Directory (doesFileExist)
import System.Environment (lookupEnv)
import System.FilePath (takeDirectory, (</>))

-- --------------------------------------------------------------------------
-- Constants
-- --------------------------------------------------------------------------

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

-- --------------------------------------------------------------------------
-- Types
-- --------------------------------------------------------------------------

data FileResult = FileResult
  { frRelativePath  :: RelativePath
  , frModified      :: Bool
  , frLinksAdded    :: Int
  , frUsedInference :: Bool
  } deriving (Show, Eq)

data LinkingResult = LinkingResult
  { lrFilesVisited    :: Int
  , lrFilesModified   :: Int
  , lrTotalLinksAdded :: Int
  , lrFilesSkipped    :: Int
  , lrFileResults     :: [FileResult]
  } deriving (Show, Eq)

-- --------------------------------------------------------------------------
-- Pure utility functions
-- --------------------------------------------------------------------------

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

-- --------------------------------------------------------------------------
-- Replacement application
-- --------------------------------------------------------------------------

applyReplacements :: Text -> [LinkCandidate] -> [Bool] -> Text
applyReplacements content candidates validations =
  let validPairs = filter snd (zip candidates validations)
      sorted     = sortBy (\(a, _) (b, _) -> compare (Down (lcPosition a)) (Down (lcPosition b)))
                     validPairs
  in foldl' applyOne content (fmap fst sorted)
  where
    applyOne :: Text -> LinkCandidate -> Text
    applyOne acc candidate =
      let pos    = lcPosition candidate
          len    = T.length (lcMatchedText candidate)
          before = T.take pos acc
          after  = T.drop (pos + len) acc
          wl     = formatWikilink (lcEntry candidate)
      in before <> wl <> after

-- --------------------------------------------------------------------------
-- Frontmatter updates
-- --------------------------------------------------------------------------

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

-- --------------------------------------------------------------------------
-- File processing
-- --------------------------------------------------------------------------

processFile :: Manager -> Secret -> Gemini.Model -> FilePath -> [ContentEntry] -> IO (Maybe FileResult)
processFile manager apiKey model filePath index = do
  let contentDir   = takeDirectory (takeDirectory filePath)
      relativePath = makeRelPathFromContentDir contentDir filePath
  case mkRelativePath (T.pack relativePath) of
    Left reason -> do
      putStrLn $ "  ⚠️  Skipping " <> filePath <> ": " <> T.unpack reason
      pure Nothing
    Right relPath -> do
      content <- TIO.readFile filePath
      if alreadyAnalyzed content
        then pure $ Just FileResult
          { frRelativePath  = relPath
          , frModified      = False
          , frLinksAdded    = 0
          , frUsedInference = False
          }
        else do
          let body = extractBody content
              eligibleBooks = filter
                (\e -> ceRelativePath e /= relPath
                    && not (contentAlreadyLinksTo content e))
                index
          case eligibleBooks of
            [] -> do
              timestamp <- nowIso
              recordLinkAnalysis filePath model timestamp
              pure $ Just FileResult
                { frRelativePath  = relPath
                , frModified      = False
                , frLinksAdded    = 0
                , frUsedInference = False
                }
            _ -> do
              geminiResult <- identifyBooksWithGemini manager apiKey model body eligibleBooks
              timestamp <- nowIso
              recordLinkAnalysis filePath model timestamp
              case geminiResult of
                Left _err -> pure $ Just FileResult
                  { frRelativePath  = relPath
                  , frModified      = False
                  , frLinksAdded    = 0
                  , frUsedInference = True
                  }
                Right identifiedPaths
                  | null identifiedPaths -> pure $ Just FileResult
                      { frRelativePath  = relPath
                      , frModified      = False
                      , frLinksAdded    = 0
                      , frUsedInference = True
                      }
                  | otherwise -> do
                      let identifiedSet = Set.fromList identifiedPaths
                      contentAfterFm <- TIO.readFile filePath
                      let masked          = maskProtectedRegions contentAfterFm
                          identifiedIndex = filter (\e -> Set.member (unRelativePath (ceRelativePath e)) identifiedSet) index
                          candidates      = findLinkCandidates identifiedIndex contentAfterFm masked relPath
                      case candidates of
                        [] -> pure $ Just FileResult
                          { frRelativePath  = relPath
                          , frModified      = False
                          , frLinksAdded    = 0
                          , frUsedInference = True
                          }
                        _  -> do
                          let validations = replicate (length candidates) True
                              newContent  = applyReplacements contentAfterFm candidates validations
                          TIO.writeFile filePath newContent
                          putStrLn $ "  ✏️  " <> relativePath <> ": "
                            <> show (length candidates) <> " link(s) applied"
                          pure $ Just FileResult
                            { frRelativePath  = relPath
                            , frModified      = True
                            , frLinksAdded    = length candidates
                            , frUsedInference = True
                            }

makeRelPathFromContentDir :: FilePath -> FilePath -> FilePath
makeRelPathFromContentDir contentDir filePath =
  joinSlash $ drop (length (splitSlash contentDir)) (splitSlash filePath)

nowIso :: IO Text
nowIso = do
  today <- todayPacificDay
  pure (formatDay today <> "T00:00:00Z")

-- --------------------------------------------------------------------------
-- Orchestration
-- --------------------------------------------------------------------------

run :: Manager -> Gemini.Model -> FilePath -> IO LinkingResult
run manager model contentDir = do
  putStrLn $ "🔗 Internal linking: model=" <> T.unpack (Gemini.modelToText model)

  index <- buildContentIndex contentDir
  putStrLn $ "  📚 Index: " <> show (length index) <> " books"

  filesToVisit <- bfsTraversal contentDir
  putStrLn $ "  🔍 BFS: " <> show (length filesToVisit) <> " files reachable"

  apiKey <- lookupSecret
  fileResults <- processFiles manager apiKey model contentDir index filesToVisit

  let filesModified  = length $ filter frModified fileResults
      totalLinks     = sum $ fmap frLinksAdded fileResults
      filesSkipped   = length $ filter (\r -> not (frModified r) && frLinksAdded r == 0) fileResults

  let result = LinkingResult
        { lrFilesVisited    = length filesToVisit
        , lrFilesModified   = filesModified
        , lrTotalLinksAdded = totalLinks
        , lrFilesSkipped    = filesSkipped
        , lrFileResults     = fileResults
        }

  putStrLn $ "  🏁 Complete: " <> show (lrFilesVisited result) <> " visited, "
    <> show filesModified <> " modified, " <> show totalLinks <> " links added, "
    <> show filesSkipped <> " skipped"

  pure result

processFiles :: Manager -> Secret -> Gemini.Model -> FilePath -> [ContentEntry] -> [Text] -> IO [FileResult]
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
          if frUsedInference fileResult
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
