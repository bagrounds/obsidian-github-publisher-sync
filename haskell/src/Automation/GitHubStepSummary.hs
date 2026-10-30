module Automation.GitHubStepSummary
  ( StepSummaryError (..)
  , describeError
  , summaryFileFromEnvironment
  , locateSummaryFile
  , appendMarkdown
  ) where

import Control.Exception (IOException, try)
import Control.Monad (mfilter)
import Data.Bifunctor (first)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Environment (lookupEnv)

data StepSummaryError
  = NotInGitHubActions
  | WriteFailed FilePath IOException
  deriving (Show, Eq)

summaryFileVariable :: String
summaryFileVariable = "GITHUB_STEP_SUMMARY"

describeError :: StepSummaryError -> Text
describeError = \case
  NotInGitHubActions ->
    "ℹ️ " <> T.pack summaryFileVariable <> " is not set, so the job summary was skipped (not running in GitHub Actions)"
  WriteFailed path exception ->
    "⚠️ Could not append to the job summary at " <> T.pack path <> ": " <> T.pack (show exception)

summaryFileFromEnvironment :: Maybe String -> Either StepSummaryError FilePath
summaryFileFromEnvironment = maybe (Left NotInGitHubActions) Right . mfilter (not . null)

locateSummaryFile :: IO (Either StepSummaryError FilePath)
locateSummaryFile = summaryFileFromEnvironment <$> lookupEnv summaryFileVariable

appendMarkdown :: FilePath -> Text -> IO (Either StepSummaryError ())
appendMarkdown path markdown = first (WriteFailed path) <$> try (TIO.appendFile path markdown)
