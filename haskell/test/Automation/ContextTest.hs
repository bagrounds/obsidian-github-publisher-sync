module Automation.ContextTest (tests) where

import Data.List (isInfixOf)
import Network.HTTP.Client (Manager, newManager, defaultManagerSettings)
import System.IO.Unsafe (unsafePerformIO)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import Test.Tasty.QuickCheck (testProperty)
import qualified Test.QuickCheck as QC

import Automation.Context (AppContext (vaultDir, repoRoot, geminiApiKey, obsidianCredentials), mkAppContext)
import Automation.ObsidianSync (ObsidianCredentials (..))
import Automation.Secret (Secret (..))

{-# NOINLINE testManager #-}
testManager :: Manager
testManager = unsafePerformIO (newManager defaultManagerSettings)

testObsidianCredentials :: ObsidianCredentials
testObsidianCredentials = ObsidianCredentials
  { ocAuthToken = Secret "token"
  , ocVaultName = "test-vault"
  , ocVaultPassword = Nothing
  }

tests :: TestTree
tests = testGroup "Context"
  [ mkAppContextTests
  , showTests
  ]

mkAppContextTests :: TestTree
mkAppContextTests = testGroup "mkAppContext"
  [ testCase "succeeds with valid inputs" $
      case mkAppContext testManager "/vault" "/repo" (Secret "key") testObsidianCredentials of
        Right context -> do
          vaultDir context @?= "/vault"
          repoRoot context @?= "/repo"
          geminiApiKey context @?= Secret "key"
          obsidianCredentials context @?= testObsidianCredentials
        Left err -> fail $ "Expected Right, got Left: " <> err

  , testCase "rejects empty vault directory" $
      case mkAppContext testManager "" "/repo" (Secret "key") testObsidianCredentials of
        Left message -> message @?= "Vault directory path cannot be empty"
        Right _ -> fail "Expected Left for empty vault directory"

  , testCase "rejects empty repo root" $
      case mkAppContext testManager "/vault" "" (Secret "key") testObsidianCredentials of
        Left message -> message @?= "Repository root path cannot be empty"
        Right _ -> fail "Expected Left for empty repo root"

  , testCase "rejects both paths empty" $
      case mkAppContext testManager "" "" (Secret "key") testObsidianCredentials of
        Left _ -> pure ()
        Right _ -> fail "Expected Left for empty paths"

  , testProperty "valid paths always produce Right" $
      QC.forAll genNonEmptyPath $ \vault ->
        QC.forAll genNonEmptyPath $ \repo ->
          case mkAppContext testManager vault repo (Secret "key") testObsidianCredentials of
            Right context -> vaultDir context == vault && repoRoot context == repo
            Left _ -> False
  ]

showTests :: TestTree
showTests = testGroup "Show"
  [ testCase "Show redacts gemini API key" $
      case mkAppContext testManager "/vault" "/repo" (Secret "super-secret-key") testObsidianCredentials of
        Right context -> do
          let shown = show context
          assertBool "Should contain vaultDir" ("vaultDir" `isInfixOf` shown)
          assertBool "Should contain repoRoot" ("repoRoot" `isInfixOf` shown)
          assertBool "Should contain <redacted>" ("<redacted>" `isInfixOf` shown)
          assertBool "Should contain obsidianCredentials" ("obsidianCredentials" `isInfixOf` shown)
          assertBool "Should NOT contain the secret" (not ("super-secret-key" `isInfixOf` shown))
        Left err -> fail $ "Expected Right, got Left: " <> err
  ]

genNonEmptyPath :: QC.Gen FilePath
genNonEmptyPath = do
  segments <- QC.listOf1 (QC.listOf1 (QC.elements (['a'..'z'] <> ['0'..'9'] <> ['-', '_'])))
  pure ("/" <> foldr1 (\segment path -> segment <> "/" <> path) segments)
