{-# LANGUAGE OverloadedStrings #-}

-- | Orchestrator for the auto-generated book reports pipeline.
--
-- This module is the only one that performs IO. All decisions are delegated
-- to pure helpers in @Automation.AutoBookReports.*@, keeping the
-- functional core / imperative shell boundary crisp.
--
-- The high-level flow is:
--
-- 1. Enumerate existing book slugs in @<vault>/books/@.
-- 2. Read the most recent reflections.
-- 3. Ask Gemini which book references in those reflections do not have a page yet.
-- 4. For each candidate, in order: look up its Amazon ASIN and variant, then
--    generate the report body, then write the file and update today's reflection.
-- 5. Stop after the first successful publication.
--
-- Every step logs a one-line plain-text summary so failures are immediately
-- diagnosable from CI logs.
module Automation.AutoBookReports
  ( runAutoBookReports
  , maxBooksPerRun
  , defaultModel
  -- exposed for testing
  , autoBookReportsTaskName
  ) where

import Control.Monad (when)
import Data.List.NonEmpty (NonEmpty ((:|)))
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Data.Time (Day)
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, doesFileExist, listDirectory)
import System.Environment (lookupEnv)
import System.FilePath ((</>))
import Network.HTTP.Client (Manager)

import qualified Automation.Context as Context
import qualified Automation.Gemini as Gemini
import Automation.PacificTime (formatDay, todayPacificDay)
import Automation.Secret (Secret (..))
import Automation.TaskRunner (logMsg)

import Automation.AutoBookReports.AmazonLink
  ( AmazonResolution (..)
  , defaultVariantPriority
  , buildLookupPrompt
  , formatAffiliateUrl
  , parseLookupResponse
  , variantToText
  )
import Automation.AutoBookReports.Discovery
  ( extractReflectionBody
  , filterRecentReflections
  , knownBookSlug
  )
import Automation.AutoBookReports.Identify
  ( BookCandidate (..)
  , buildIdentificationPrompt
  , parseIdentificationResponse
  )
import Automation.AutoBookReports.ReflectionLink (insertBookLink)
import Automation.AutoBookReports.Report
  ( ReportInput (..)
  , assembleBookReport
  , buildReportPrompt
  , generateBookSlug
  )

autoBookReportsTaskName :: Text
autoBookReportsTaskName = "auto-book-reports"

-- | Cap on the number of book reports generated per run. Mirrors the
-- per-run limits applied to image backfill and internal linking.
maxBooksPerRun :: Int
maxBooksPerRun = 1

-- | The Gemini model used for identification and report generation.
-- Override at runtime by setting the env var @AUTO_BOOK_REPORTS_MODEL@.
defaultModel :: Gemini.Model
defaultModel = Gemini.Gemini25Flash

-- | Top-level entry point invoked from the task runner.
runAutoBookReports :: Context.AppContext -> IO ()
runAutoBookReports context = do
  logMsg $ "▶️  " <> autoBookReportsTaskName
  let manager = Context.httpManager context
      vault = Context.vaultDir context
      apiKey = Context.geminiApiKey context

  associatesTag <- lookupEnv "AMAZON_ASSOCIATES_TAG"
  case associatesTag of
    Nothing -> logMsg "  ❌ AMAZON_ASSOCIATES_TAG not set — skipping (set it to enable affiliate links)"
    Just "" -> logMsg "  ❌ AMAZON_ASSOCIATES_TAG is empty — skipping"
    Just tag -> do
      modelOverride <- lookupEnv "AUTO_BOOK_REPORTS_MODEL"
      let model = maybe defaultModel (Gemini.modelFromText . T.pack) modelOverride
      logMsg $ "  🤖 Using model: " <> Gemini.modelToText model

      knownSlugs <- listKnownBookSlugs vault
      logMsg $ "  📂 Found " <> T.pack (show (length knownSlugs)) <> " existing books in vault"

      reflectionBodies <- readRecentReflectionBodies vault
      logMsg $ "  📚 Read " <> T.pack (show (length reflectionBodies)) <> " recent reflection(s)"

      if null reflectionBodies
        then logMsg "  ⏭️  No reflections to scan — done"
        else do
          candidates <- identifyCandidates manager apiKey model knownSlugs reflectionBodies
          case candidates of
            [] -> logMsg "  🟢 No new book candidates identified — done"
            _  -> do
              logMsg $ "  🎯 " <> T.pack (show (length candidates)) <> " candidate(s): "
                    <> T.intercalate "; " (fmap candidateLabel candidates)
              today <- todayPacificDay
              attemptCandidates context (T.pack tag) model today knownSlugs candidates
  logMsg $ "✅ " <> autoBookReportsTaskName

candidateLabel :: BookCandidate -> Text
candidateLabel candidate =
  candidateTitle candidate <> " by " <> candidateAuthor candidate

-- | List the slugs of all existing book pages (e.g. @"deep-work"@) in
-- @<vault>/books/@. Returns the empty list when the directory does not exist.
listKnownBookSlugs :: FilePath -> IO [Text]
listKnownBookSlugs vault = do
  let booksDir = vault </> "books"
  exists <- doesDirectoryExist booksDir
  if not exists
    then pure []
    else do
      entries <- listDirectory booksDir
      pure (mapMaybe knownBookSlug entries)

-- | Read the bodies (frontmatter stripped) of the recent reflection files.
readRecentReflectionBodies :: FilePath -> IO [Text]
readRecentReflectionBodies vault = do
  let reflectionsDir = vault </> "reflections"
  exists <- doesDirectoryExist reflectionsDir
  if not exists
    then pure []
    else do
      entries <- listDirectory reflectionsDir
      let recent = filterRecentReflections entries
      traverse (fmap extractReflectionBody . TIO.readFile . (reflectionsDir </>)) recent

-- | Call Gemini to identify candidate books not yet in the vault.
identifyCandidates
  :: Manager
  -> Secret
  -> Gemini.Model
  -> [Text]
  -> [Text]
  -> IO [BookCandidate]
identifyCandidates manager apiKey model knownSlugs reflectionBodies = do
  let (systemInstruction, userPrompt) = buildIdentificationPrompt knownSlugs reflectionBodies
      genConfig = Gemini.defaultGenerationConfig
        { Gemini.temperature = 0.2
        , Gemini.maxOutputTokens = 2048
        }
  result <- Gemini.generateContentWithFallback manager (model :| []) (Just systemInstruction) userPrompt apiKey genConfig
  case result of
    Left err -> do
      logMsg $ "  ⚠️  Identification call failed: " <> T.pack (show err)
      pure []
    Right response -> do
      let raw = Gemini.responseText response
      case parseIdentificationResponse raw of
        Right candidates -> pure (filter (notInKnownSlugs knownSlugs) candidates)
        Left reason -> do
          logMsg $ "  ⚠️  Could not parse identification response: " <> reason
          pure []

-- | Filter out candidates whose generated slug matches an existing book.
-- Belt-and-suspenders against Gemini suggesting a book that's already there.
notInKnownSlugs :: [Text] -> BookCandidate -> Bool
notInKnownSlugs knownSlugs candidate =
  generateBookSlug (candidateTitle candidate) `notElem` knownSlugs

-- | Try each candidate in order. Stop after the first successful publication.
attemptCandidates
  :: Context.AppContext
  -> Text     -- ^ Amazon associates tag
  -> Gemini.Model
  -> Day
  -> [Text]   -- ^ Known slugs (for collision detection)
  -> [BookCandidate]
  -> IO ()
attemptCandidates _ _ _ _ _ [] = logMsg "  🟡 Exhausted candidates without publishing — see warnings above"
attemptCandidates context tag model today knownSlugs (candidate : rest) = do
  let title = candidateTitle candidate
      author = candidateAuthor candidate
      slug = generateBookSlug title
  logMsg $ "  🛒 Looking up Amazon link for: " <> title <> " by " <> author
  if slug `elem` knownSlugs
    then do
      logMsg $ "  ⏭️  Slug " <> slug <> " already exists — skipping"
      attemptCandidates context tag model today knownSlugs rest
    else do
      lookupResult <- lookupAmazon context model title author
      case lookupResult of
        Left reason -> do
          logMsg $ "  ⏭️  Amazon lookup failed (" <> reason <> ") — trying next candidate"
          attemptCandidates context tag model today knownSlugs rest
        Right resolution -> do
          logMsg $ "  ✅ Resolved ASIN " <> resolvedAsin resolution
                <> " (" <> variantToText (resolvedVariant resolution) <> ")"
          published <- publishCandidate context tag model today candidate resolution
          if published
            then logMsg "  🛑 Reached per-run limit — stopping"
            else do
              logMsg "  ⏭️  Generation/write failed — trying next candidate"
              attemptCandidates context tag model today knownSlugs rest

-- | Call Gemini (with grounding) to resolve an ASIN for the candidate.
lookupAmazon
  :: Context.AppContext
  -> Gemini.Model
  -> Text -- title
  -> Text -- author
  -> IO (Either Text AmazonResolution)
lookupAmazon context model title author = do
  let manager = Context.httpManager context
      apiKey = Context.geminiApiKey context
      (systemInstruction, userPrompt) = buildLookupPrompt title author defaultVariantPriority
      genConfig = Gemini.defaultGenerationConfig
        { Gemini.temperature = 0.0
        , Gemini.maxOutputTokens = 256
        , Gemini.searchGrounding = True
        }
  result <- Gemini.generateContentWithFallback manager (model :| []) (Just systemInstruction) userPrompt apiKey genConfig
  case result of
    Left err -> pure (Left ("Gemini error: " <> T.pack (show err)))
    Right response -> pure (parseLookupResponse (Gemini.responseText response))

-- | Generate the report body and write everything to disk + reflection.
-- Returns 'True' on success, 'False' when any non-fatal step fails.
publishCandidate
  :: Context.AppContext
  -> Text -- tag
  -> Gemini.Model
  -> Day
  -> BookCandidate
  -> AmazonResolution
  -> IO Bool
publishCandidate context tag model today candidate resolution = do
  let manager = Context.httpManager context
      vault = Context.vaultDir context
      apiKey = Context.geminiApiKey context
      title = candidateTitle candidate
      author = candidateAuthor candidate
      slug = generateBookSlug title
      (systemInstruction, userPrompt) = buildReportPrompt title author
      affiliateUrl = formatAffiliateUrl (resolvedAsin resolution) tag
      genConfig = Gemini.defaultGenerationConfig
        { Gemini.temperature = 0.7
        , Gemini.maxOutputTokens = 4096
        }
  logMsg "  📝 Generating book report body"
  result <- Gemini.generateContentWithFallback manager (model :| []) (Just systemInstruction) userPrompt apiKey genConfig
  case result of
    Left err -> do
      logMsg $ "  ⚠️  Report generation failed: " <> T.pack (show err)
      pure False
    Right response -> do
      let body = Gemini.responseText response
          modelUsed = Gemini.modelToText (Gemini.responseModel response)
          input = ReportInput
            { reportTitle = title
            , reportAuthor = author
            , reportSlug = slug
            , reportAffiliateUrl = affiliateUrl
            , reportBody = body
            , reportTodayIso = formatDay today <> "T00:00:00Z"
            , reportModelUsed = modelUsed
            , reportPromptText = userPrompt
            }
          markdown = assembleBookReport input
          booksDir = vault </> "books"
          bookPath = booksDir </> T.unpack slug <> ".md"
      -- Sanity check: do not overwrite an existing file.
      alreadyExists <- doesFileExist bookPath
      if alreadyExists
        then do
          logMsg $ "  ⚠️  File already exists at " <> T.pack bookPath <> " — skipping"
          pure False
        else do
          createDirectoryIfMissing True booksDir
          TIO.writeFile bookPath markdown
          logMsg $ "  💾 Wrote " <> T.pack bookPath
          updateTodayReflection vault today slug title
          pure True

-- | Insert the new book wikilink into today's reflection (best-effort).
updateTodayReflection :: FilePath -> Day -> Text -> Text -> IO ()
updateTodayReflection vault today slug title = do
  let reflectionPath = vault </> "reflections" </> T.unpack (formatDay today) <> ".md"
  exists <- doesFileExist reflectionPath
  if not exists
    then logMsg $ "  ⚠️  Today's reflection not found at " <> T.pack reflectionPath <> " — skipping link"
    else do
      content <- TIO.readFile reflectionPath
      let updated = insertBookLink content slug title
      when (updated /= content) $ do
        TIO.writeFile reflectionPath updated
        logMsg $ "  🔗 Linked book into reflection: " <> formatDay today
