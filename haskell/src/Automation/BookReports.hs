module Automation.BookReports
  ( runBookReports
  , maxBooksPerRun
  ) where

import Control.Monad (when)
import Data.List.NonEmpty (NonEmpty ((:|)))
import Data.Maybe (isNothing)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Data.Time (Day)
import System.Directory (doesFileExist)
import System.Environment (lookupEnv)
import System.FilePath ((</>))

import qualified Automation.Context as Context
import qualified Automation.Gemini as Gemini
import Automation.PacificTime (formatDay, todayPacificDay)
import Automation.TaskRunner (logMsg)
import Automation.RelativePath (mkRelativePath)
import Automation.Title (mkTitle)
import Automation.DailyUpdates
  ( UpdateDetail (..)
  , UpdateLink (..)
  , addUpdateLinksToReflection
  )
import Automation.DailyReflection (trailingSectionHeaders)

import qualified Automation.BookReports.Amazon as Amazon
import qualified Automation.BookReports.Discovery as Discovery
import qualified Automation.BookReports.PendingState as Pending
import qualified Automation.BookReports.Report as Report
import qualified Automation.BookReports.ReflectionUpdate as ReflectionUpdate
import Automation.BookReports.Discovery (BookCandidate (..))
import Automation.BookReports.Types
  ( AmazonResolution (..)
  , AmazonVariant (..)
  , Asin
  , BookSlug
  , BookTitle
  , defaultVariantPriority
  , slugFromTitle
  , unAsin
  , unBookSlug
  , unBookTitle
  , variantToText
  )

topVariantPriority :: AmazonVariant
topVariantPriority = case defaultVariantPriority of
  (firstChoice : _) -> firstChoice
  []                -> Hardcover  -- defensive: defaultVariantPriority is non-empty by construction


-- generation is intentionally disabled so that failures cannot cascade and so
-- the reflection link insertion stays trivially auditable.
maxBooksPerRun :: Int
maxBooksPerRun = 1

bookReportModelEnvVar :: String
bookReportModelEnvVar = "BOOK_REPORT_MODEL"

amazonAffiliateTagEnvVar :: String
amazonAffiliateTagEnvVar = "AMAZON_ASSOCIATES_TAG"

defaultModelChain :: NonEmpty Gemini.Model
defaultModelChain = Gemini.Gemini25Flash :| [Gemini.Gemini31FlashLite]

runBookReports :: Context.AppContext -> IO ()
runBookReports context = do
  logMsg "▶️  book-reports"

  today <- todayPacificDay
  logMsg $ "  📅 Pacific date: " <> formatDay today

  maybeAffiliateTagText <- fmap (fmap T.pack) (lookupEnv amazonAffiliateTagEnvVar)
  case maybeAffiliateTagText >>= rightToMaybe . Amazon.mkAffiliateTag of
    Nothing -> do
      logMsg $ "  ⚠️  " <> T.pack amazonAffiliateTagEnvVar
        <> " is not set or invalid — refusing to publish report without affiliate link."
      logMsg "✅ book-reports (skipped)"
    Just affiliateTag -> do
      let vaultDir       = Context.vaultDir context
          booksDir       = vaultDir </> "books"
          booksIndexPath = booksDir </> "index.md"

      logMsg $ "  📂 Vault books directory: " <> T.pack booksDir

      pending <- Pending.readPendingField booksIndexPath
      logMsg $ "  📒 Pending state — title=" <> showMaybe unBookTitle (Pending.pendingTitle pending)
        <> ", asin=" <> showMaybe unAsin (Pending.pendingAsin pending)
        <> ", lastGenerated=" <> showMaybe (T.pack . show) (Pending.lastGeneratedOnDay pending)

      if alreadyDoneToday today pending
        then do
          logMsg $ "  ⏭️  A book report has already been generated today (" <> formatDay today <> ") — skipping."
          logMsg "✅ book-reports"
        else processOrDiscover context affiliateTag today booksIndexPath pending

alreadyDoneToday :: Day -> Pending.PendingState -> Bool
alreadyDoneToday today state =
     Pending.lastGeneratedOnDay state == Just today
  && isNothing (Pending.pendingTitle state)
  && isNothing (Pending.pendingAsin state)

processOrDiscover
  :: Context.AppContext
  -> Amazon.AffiliateTag
  -> Day
  -> FilePath          -- ^ books index path (frontmatter we read/write)
  -> Pending.PendingState
  -> IO ()
processOrDiscover context affiliateTag today booksIndexPath pending = do
  case Pending.pendingTitle pending of
    Just title -> do
      logMsg $ "  ▶️  Resuming pending book: " <> unBookTitle title
      generateForTitle context affiliateTag today booksIndexPath
        title (Pending.pendingAsin pending)
    Nothing -> do
      logMsg "  🔍 No pending book — discovering candidates from recent reflections"
      discoverAndStart context affiliateTag today booksIndexPath

discoverAndStart
  :: Context.AppContext
  -> Amazon.AffiliateTag
  -> Day
  -> FilePath
  -> IO ()
discoverAndStart context affiliateTag today booksIndexPath = do
  let vaultDir       = Context.vaultDir context
      booksDir       = vaultDir </> "books"
      reflectionsDir = vaultDir </> "reflections"

  knownSlugs       <- Discovery.listExistingBookSlugs booksDir
  recentReflections <- Discovery.listRecentReflectionFiles reflectionsDir
  logMsg $ "  📚 Known book slugs: " <> T.pack (show (Set.size knownSlugs))
  logMsg $ "  📅 Reflections in window (last " <> T.pack (show Discovery.recentReflectionWindow)
            <> "): " <> T.pack (show (length recentReflections))

  candidates <- collectAcrossFiles knownSlugs recentReflections
  logMsg $ "  🎯 Candidates discovered: " <> T.pack (show (length candidates))

  case take maxBooksPerRun candidates of
    [] -> do
      logMsg "  ⏭️  Nothing to generate — every recently linked book already has a page."
      logMsg "✅ book-reports"
    (firstCandidate : _) -> do
      let title = candidateTitle firstCandidate
      logMsg $ "  📝 Selected candidate: " <> unBookTitle title
                <> " (slug=" <> unBookSlug (candidateSlug firstCandidate)
                <> ", from=" <> T.pack (candidateSourceFile firstCandidate) <> ")"
      Pending.writePendingState booksIndexPath
        (Pending.emptyPendingState { Pending.pendingTitle = Just title })
      generateForTitle context affiliateTag today booksIndexPath title Nothing

collectAcrossFiles :: Set.Set BookSlug -> [FilePath] -> IO [BookCandidate]
collectAcrossFiles knownSlugs files =
  fmap concat (traverse scanOne files)
  where
    scanOne reflectionPath = do
      content <- TIO.readFile reflectionPath
      let candidates = Discovery.extractBookCandidatesFromReflection knownSlugs reflectionPath content
      pure candidates

generateForTitle
  :: Context.AppContext
  -> Amazon.AffiliateTag
  -> Day
  -> FilePath
  -> BookTitle
  -> Maybe Asin
  -> IO ()
generateForTitle context affiliateTag today booksIndexPath title cachedAsin = do
  let slug         = slugFromTitle title
      vaultDir     = Context.vaultDir context
      bookFilePath' = Report.bookFilePath vaultDir slug
  logMsg $ "  🐌 Slug: " <> unBookSlug slug
  alreadyExists <- doesFileExist bookFilePath'
  if alreadyExists
    then do
      logMsg $ "  ⚠️  Book file already exists at " <> T.pack bookFilePath'
                <> " — clearing pending state and stopping."
      Pending.recordCompletedToday booksIndexPath today
      logMsg "✅ book-reports"
    else proceedWithResolution context affiliateTag today booksIndexPath title slug cachedAsin

proceedWithResolution
  :: Context.AppContext
  -> Amazon.AffiliateTag
  -> Day
  -> FilePath
  -> BookTitle
  -> BookSlug
  -> Maybe Asin
  -> IO ()
proceedWithResolution context affiliateTag today booksIndexPath title slug cachedAsin = do
  resolutionResult <- case cachedAsin of
    Just cached -> do
      logMsg $ "  🛒 Using cached ASIN from prior run: " <> unAsin cached
      pure (Right cached)
    Nothing -> resolveAsinViaGemini context title

  case resolutionResult of
    Left resolutionError -> do
      logMsg $ "  ❌ Amazon resolution failed for " <> unBookTitle title <> ": " <> resolutionError
      logMsg "✅ book-reports (skipped)"
    Right resolvedAsinValue -> do
      Pending.writePendingState booksIndexPath
        Pending.emptyPendingState
          { Pending.pendingTitle = Just title
          , Pending.pendingAsin  = Just resolvedAsinValue
          }
      let affiliateUrl = Amazon.buildAffiliateUrlFromAsin affiliateTag resolvedAsinValue
      logMsg $ "  🔗 Affiliate URL: " <> Amazon.unAmazonAffiliateUrl affiliateUrl

      reportResult <- generateReportBody context title affiliateUrl
      case reportResult of
        Left reportError -> do
          logMsg $ "  ❌ Report generation failed for " <> unBookTitle title <> ": " <> reportError
          logMsg "✅ book-reports (skipped — pending state preserved for retry)"
        Right (modelText, body) -> do
          let reportFile = Report.assembleReportFile title slug affiliateUrl
                            topVariantPriority
                            today modelText body
              reportPath = Report.bookFilePath (Context.vaultDir context) slug
          logMsg $ "  📝 Writing report (" <> T.pack (show (T.length body)) <> " chars body, "
                    <> T.pack (show (T.length reportFile)) <> " chars total) to "
                    <> T.pack reportPath
          TIO.writeFile reportPath reportFile

          updateReflectionAndChanges context today slug title
          Pending.recordCompletedToday booksIndexPath today
          logMsg "✅ book-reports"

resolveAsinViaGemini :: Context.AppContext -> BookTitle -> IO (Either Text Asin)
resolveAsinViaGemini context title = do
  envModel <- fmap (fmap T.pack) (lookupEnv bookReportModelEnvVar)
  let models = Gemini.overrideModelChain envModel defaultModelChain
      prompt = Amazon.buildAmazonResolutionPrompt title defaultVariantPriority
      config = Gemini.defaultGenerationConfig
        { Gemini.temperature     = 0.0
        , Gemini.maxOutputTokens = 256
        , Gemini.searchGrounding = True
        }
  logMsg $ "  🛒 Asking Gemini for canonical Amazon ASIN of: " <> unBookTitle title
  result <- Gemini.generateContentWithFallback
              (Context.httpManager context) models Nothing prompt
              (Context.geminiApiKey context) config
  case result of
    Left geminiError ->
      pure (Left ("Gemini call failed: " <> T.pack (show geminiError)))
    Right response -> do
      logMsg $ "  📥 Gemini ASIN response model: " <> Gemini.modelToText (Gemini.responseModel response)
      logMsg $ "  📥 Gemini ASIN response text (first 200): "
                <> T.take 200 (Gemini.responseText response)
      case Amazon.parseAmazonResolutionResponse defaultVariantPriority (Gemini.responseText response) of
        Right resolution -> do
          logMsg $ "  ✅ Resolved ASIN " <> unAsin (resolvedAsin resolution)
                    <> " (variant=" <> variantToText (resolvedVariant resolution) <> ")"
          pure (Right (resolvedAsin resolution))
        Left parseError -> pure (Left parseError)

generateReportBody
  :: Context.AppContext
  -> BookTitle
  -> Amazon.AmazonAffiliateUrl
  -> IO (Either Text (Text, Text))   -- ^ (model identifier, body markdown)
generateReportBody context title affiliateUrl = do
  envModel <- fmap (fmap T.pack) (lookupEnv bookReportModelEnvVar)
  let models = Gemini.overrideModelChain envModel defaultModelChain
      variant = topVariantPriority
      prompt = Report.buildReportPrompt title affiliateUrl variant
      config = Gemini.defaultGenerationConfig
        { Gemini.temperature     = 0.7
        , Gemini.maxOutputTokens = 4096
        , Gemini.searchGrounding = True
        }
  logMsg $ "  ✍️  Generating report body for: " <> unBookTitle title
  result <- Gemini.generateContentWithFallback
              (Context.httpManager context) models
              (Just Report.reportSystemInstruction) prompt
              (Context.geminiApiKey context) config
  case result of
    Left geminiError ->
      pure (Left ("Gemini call failed: " <> T.pack (show geminiError)))
    Right response -> do
      let modelText = Gemini.modelToText (Gemini.responseModel response)
          body      = Gemini.responseText response
      if T.null (T.strip body)
        then pure (Left ("Empty body returned by " <> modelText))
        else pure (Right (modelText, body))

updateReflectionAndChanges
  :: Context.AppContext
  -> Day
  -> BookSlug
  -> BookTitle
  -> IO ()
updateReflectionAndChanges context today slug title = do
  let vaultDir       = Context.vaultDir context
      reflectionPath = vaultDir </> "reflections" </> T.unpack (formatDay today) <> ".md"

  reflectionExists <- doesFileExist reflectionPath
  when reflectionExists $ do
    existing <- TIO.readFile reflectionPath
    let updated = ReflectionUpdate.insertOrUpdateBooksSection
                    trailingSectionHeaders slug title existing
    if updated == existing
      then logMsg $ "  ⏭️  Reflection already links to " <> unBookSlug slug <> " — skipping insertion."
      else do
        TIO.writeFile reflectionPath updated
        logMsg $ "  📓 Inserted wikilink to books/" <> unBookSlug slug <> " in reflection."

  recordInDailyChangesTable vaultDir today slug title

recordInDailyChangesTable :: FilePath -> Day -> BookSlug -> BookTitle -> IO ()
recordInDailyChangesTable vaultDir today slug title = do
  case (mkRelativePath ("books/" <> unBookSlug slug <> ".md"), mkTitle (unBookTitle title)) of
    (Right relPath, Right titleDomain) -> do
      let updateLink = UpdateLink
            { updateRelativePath = relPath
            , updateTitle        = titleDomain
            , updateDetails      = [BookReportGenerated]
            }
      _ <- addUpdateLinksToReflection vaultDir today [updateLink]
      logMsg $ "  📊 Recorded book report in daily changes table: " <> unBookSlug slug
    (Left relErr, _) ->
      logMsg $ "  ⚠️  Could not build RelativePath for changes table: " <> relErr
    (_, Left titleErr) ->
      logMsg $ "  ⚠️  Could not build Title for changes table: " <> titleErr

showMaybe :: (a -> Text) -> Maybe a -> Text
showMaybe _ Nothing      = "—"
showMaybe render (Just x) = render x

rightToMaybe :: Either e a -> Maybe a
rightToMaybe = either (const Nothing) Just
