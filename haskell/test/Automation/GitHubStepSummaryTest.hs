module Automation.GitHubStepSummaryTest (tests) where

import qualified Data.Text.IO as TIO
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, assertEqual, assertBool)

import Automation.GitHubStepSummary
  ( StepSummaryError (..)
  , appendMarkdown
  , summaryFileFromEnvironment
  )

tests :: TestTree
tests = testGroup "GitHubStepSummary"
  [ testCase "the summary file comes from the environment variable value" $
      assertEqual "path" (Right "/tmp/step-summary") (summaryFileFromEnvironment (Just "/tmp/step-summary"))

  , testCase "a missing environment variable means we are not in GitHub Actions" $
      assertBool "missing" (isNotInGitHubActions (summaryFileFromEnvironment Nothing))

  , testCase "an empty environment variable means we are not in GitHub Actions" $
      assertBool "empty" (isNotInGitHubActions (summaryFileFromEnvironment (Just "")))

  , testCase "appending keeps earlier sections" $
      withSystemTempDirectory "step-summary" $ \directory -> do
        let summaryFile = directory </> "summary.md"
        TIO.writeFile summaryFile "earlier\n"
        pullWrite <- appendMarkdown summaryFile "pull\n"
        pushWrite <- appendMarkdown summaryFile "push\n"
        contents <- TIO.readFile summaryFile
        assertEqual "pull write" (Right ()) pullWrite
        assertEqual "push write" (Right ()) pushWrite
        assertEqual "contents" "earlier\npull\npush\n" contents

  , testCase "a write failure is returned instead of thrown" $
      withSystemTempDirectory "step-summary" $ \directory -> do
        result <- appendMarkdown directory "pull\n"
        assertBool "write failed" (isWriteFailure result)
  ]

isNotInGitHubActions :: Either StepSummaryError a -> Bool
isNotInGitHubActions (Left NotInGitHubActions) = True
isNotInGitHubActions _ = False

isWriteFailure :: Either StepSummaryError a -> Bool
isWriteFailure (Left (WriteFailed _ _)) = True
isWriteFailure _ = False
