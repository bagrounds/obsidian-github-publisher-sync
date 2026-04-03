module Automation.ObsidianSyncTest (tests) where

import Control.Exception (SomeException, try)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, assertEqual, assertBool)

import Automation.ObsidianSync
  ( countVaultFiles
  , validatePrePushFileCount
  , vaultFileCountPath
  , writeEmbedsToNote
  )

tests :: TestTree
tests = testGroup "ObsidianSync"
  [ countVaultFilesTests
  , validatePrePushTests
  , writeEmbedsTests
  ]

--------------------------------------------------------------------------------
-- countVaultFiles
--------------------------------------------------------------------------------

countVaultFilesTests :: TestTree
countVaultFilesTests = testGroup "countVaultFiles"
  [ testCase "returns 0 for nonexistent directory" $ do
      count <- countVaultFiles "/tmp/nonexistent-dir-abc123"
      assertEqual "should be 0" 0 count

  , testCase "counts files excluding hidden entries" $
      withSystemTempDirectory "vault-count" $ \dir -> do
        writeFile (dir </> "note1.md") "content"
        writeFile (dir </> "note2.md") "content"
        writeFile (dir </> ".hidden") "hidden"
        count <- countVaultFiles dir
        assertEqual "should count 2 visible files" 2 count

  , testCase "counts files recursively in subdirectories" $
      withSystemTempDirectory "vault-count" $ \dir -> do
        createDirectoryIfMissing True (dir </> "sub")
        writeFile (dir </> "top.md") "content"
        writeFile (dir </> "sub" </> "nested.md") "content"
        count <- countVaultFiles dir
        assertEqual "should count 2 files across dirs" 2 count

  , testCase "ignores hidden subdirectories" $
      withSystemTempDirectory "vault-count" $ \dir -> do
        createDirectoryIfMissing True (dir </> ".obsidian")
        writeFile (dir </> "note.md") "content"
        writeFile (dir </> ".obsidian" </> "config.json") "{}"
        count <- countVaultFiles dir
        assertEqual "should count only visible file" 1 count
  ]

--------------------------------------------------------------------------------
-- validatePrePushFileCount
--------------------------------------------------------------------------------

validatePrePushTests :: TestTree
validatePrePushTests = testGroup "validatePrePushFileCount"
  [ testCase "passes when no baseline and count above minimum" $
      withSystemTempDirectory "vault-push" $ \dir -> do
        result <- try (validatePrePushFileCount dir 100) :: IO (Either SomeException ())
        assertBool "should pass" (isRight result)

  , testCase "fails when no baseline and count below minimum" $
      withSystemTempDirectory "vault-push" $ \dir -> do
        result <- try (validatePrePushFileCount dir 10) :: IO (Either SomeException ())
        assertBool "should fail (circuit breaker)" (isLeft result)

  , testCase "passes when current count matches baseline" $
      withSystemTempDirectory "vault-push" $ \dir -> do
        writeFile (vaultFileCountPath dir) "200"
        result <- try (validatePrePushFileCount dir 200) :: IO (Either SomeException ())
        assertBool "should pass (no file loss)" (isRight result)

  , testCase "passes when current count exceeds baseline" $
      withSystemTempDirectory "vault-push" $ \dir -> do
        writeFile (vaultFileCountPath dir) "200"
        result <- try (validatePrePushFileCount dir 205) :: IO (Either SomeException ())
        assertBool "should pass (files added)" (isRight result)

  , testCase "fails when current count below baseline" $
      withSystemTempDirectory "vault-push" $ \dir -> do
        writeFile (vaultFileCountPath dir) "200"
        result <- try (validatePrePushFileCount dir 195) :: IO (Either SomeException ())
        assertBool "should fail (files lost)" (isLeft result)

  , testCase "circuit breaker message mentions file loss" $
      withSystemTempDirectory "vault-push" $ \dir -> do
        writeFile (vaultFileCountPath dir) "200"
        result <- try (validatePrePushFileCount dir 195) :: IO (Either SomeException ())
        case result of
          Left err -> assertBool "error mentions CIRCUIT BREAKER"
            (T.isInfixOf "CIRCUIT BREAKER" (T.pack (show err)))
          Right _ -> assertBool "should have failed" False
  ]

--------------------------------------------------------------------------------
-- writeEmbedsToNote
--------------------------------------------------------------------------------

writeEmbedsTests :: TestTree
writeEmbedsTests = testGroup "writeEmbedsToNote"
  [ testCase "skips nonexistent file" $ do
      writeEmbedsToNote "/tmp/nonexistent-note.md"
        [("## Test", "<embed/>", \_content _html -> "\n\n## Test\n<embed/>")]
      assertBool "should not throw" True

  , testCase "appends section when header not present" $
      withSystemTempDirectory "vault-embed" $ \dir -> do
        let notePath = dir </> "note.md"
        TIO.writeFile notePath "# My Note\nSome content\n"
        writeEmbedsToNote notePath
          [("## Embed", "<blockquote>post</blockquote>",
            \_ html -> "\n\n## Embed\n" <> html)]
        result <- TIO.readFile notePath
        assertBool "should contain embed header" $
          T.isInfixOf "## Embed" result
        assertBool "should contain embed html" $
          T.isInfixOf "<blockquote>post</blockquote>" result

  , testCase "does not duplicate section when header already present" $
      withSystemTempDirectory "vault-embed" $ \dir -> do
        let notePath = dir </> "note.md"
        TIO.writeFile notePath "# My Note\n## Embed\n<blockquote>old</blockquote>\n"
        writeEmbedsToNote notePath
          [("## Embed", "<blockquote>new</blockquote>",
            \_ html -> "\n\n## Embed\n" <> html)]
        result <- TIO.readFile notePath
        let occurrences = length (T.splitOn "## Embed" result) - 1
        assertEqual "should have exactly one embed header" 1 occurrences

  , testCase "handles multiple sections independently" $
      withSystemTempDirectory "vault-embed" $ \dir -> do
        let notePath = dir </> "note.md"
        TIO.writeFile notePath "# My Note\n"
        writeEmbedsToNote notePath
          [ ("## Section A", "<a/>", \_ html -> "\n## Section A\n" <> html)
          , ("## Section B", "<b/>", \_ html -> "\n## Section B\n" <> html)
          ]
        result <- TIO.readFile notePath
        assertBool "should contain Section A" $ T.isInfixOf "## Section A" result
        assertBool "should contain Section B" $ T.isInfixOf "## Section B" result
  ]

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

isRight :: Either a b -> Bool
isRight (Right _) = True
isRight _         = False

isLeft :: Either a b -> Bool
isLeft (Left _) = True
isLeft _        = False
