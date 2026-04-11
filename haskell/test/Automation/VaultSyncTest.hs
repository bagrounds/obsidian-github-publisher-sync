module Automation.VaultSyncTest (tests) where

import qualified Data.Bifunctor
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import Test.Tasty.QuickCheck (testProperty)
import qualified Test.QuickCheck as QC

import Automation.VaultSync (findBestMatch, showScore, similarityThreshold, ensureFileInVault, syncRepoPostsToVault)

tests :: TestTree
tests = testGroup "VaultSync"
  [ findBestMatchTests
  , showScoreTests
  , similarityThresholdTests
  , ensureFileInVaultTests
  , syncRepoPostsToVaultTests
  , properties
  ]

findBestMatchTests :: TestTree
findBestMatchTests = testGroup "findBestMatch"
  [ testCase "empty vault returns zero score and none" $
      findBestMatch "some content" [] @?= (0.0, "(none)")

  , testCase "identical content returns score of 1.0" $ do
      let content = "hello world this is a test"
          vault = [("existing.md", content)]
          (score, match) = findBestMatch content vault
      score @?= 1.0
      match @?= "existing.md"

  , testCase "completely different content returns low score" $ do
      let repoContent = "alpha beta gamma delta epsilon"
          vault = [("other.md", "zulu yankee xray whiskey victor")]
          (score, _) = findBestMatch repoContent vault
      assertBool "Score should be below threshold" (score < similarityThreshold)

  , testCase "picks the best match among multiple vault files" $ do
      let repoContent = "hello world foo bar"
          vault = [ ("unrelated.md", "completely different text here")
                   , ("similar.md", "hello world foo baz")
                   , ("also-unrelated.md", "nothing in common at all")
                   ]
          (_, match) = findBestMatch repoContent vault
      match @?= "similar.md"

  , testCase "single vault file with shared words returns that file" $ do
      let repoContent = "test content here"
          vault = [("only.md", "test stuff here")]
          (_, match) = findBestMatch repoContent vault
      match @?= "only.md"
  ]

showScoreTests :: TestTree
showScoreTests = testGroup "showScore"
  [ testCase "rounds to three decimal places" $
      showScore 0.12345 @?= "0.123"

  , testCase "zero stays zero" $
      showScore 0.0 @?= "0.0"

  , testCase "one stays one" $
      showScore 1.0 @?= "1.0"

  , testCase "rounds up correctly" $
      showScore 0.2506 @?= "0.251"

  , testCase "truncates beyond three decimal places" $
      showScore 0.2504 @?= "0.25"
  ]

similarityThresholdTests :: TestTree
similarityThresholdTests = testGroup "similarityThreshold"
  [ testCase "is between 0 and 1" $
      assertBool "threshold in valid range" (similarityThreshold > 0 && similarityThreshold < 1)

  , testCase "is 0.25" $
      similarityThreshold @?= 0.25
  ]

ensureFileInVaultTests :: TestTree
ensureFileInVaultTests = testGroup "ensureFileInVault"
  [ testCase "creates file when it does not exist" $
      withSystemTempDirectory "vault-test" $ \tmpDir -> do
        let filePath = tmpDir </> "the-noise" </> "index.md"
        created <- ensureFileInVault filePath "test content"
        created @?= True
        exists <- doesFileExist filePath
        assertBool "file should exist after creation" exists
        content <- TIO.readFile filePath
        content @?= "test content"

  , testCase "does not overwrite existing file" $
      withSystemTempDirectory "vault-test" $ \tmpDir -> do
        let filePath = tmpDir </> "index.md"
        TIO.writeFile filePath "original content"
        created <- ensureFileInVault filePath "new content"
        created @?= False
        content <- TIO.readFile filePath
        content @?= "original content"

  , testCase "creates parent directories" $
      withSystemTempDirectory "vault-test" $ \tmpDir -> do
        let filePath = tmpDir </> "deep" </> "nested" </> "dir" </> "index.md"
        created <- ensureFileInVault filePath "nested content"
        created @?= True
        content <- TIO.readFile filePath
        content @?= "nested content"

  , testCase "returns False for existing file in subdirectory" $
      withSystemTempDirectory "vault-test" $ \tmpDir -> do
        let seriesDir = tmpDir </> "series"
            filePath = seriesDir </> "index.md"
        createDirectoryIfMissing True seriesDir
        TIO.writeFile filePath "vault-owned content"
        created <- ensureFileInVault filePath "generated content"
        created @?= False
        content <- TIO.readFile filePath
        content @?= "vault-owned content"
  ]

syncRepoPostsToVaultTests :: TestTree
syncRepoPostsToVaultTests = testGroup "syncRepoPostsToVault"
  [ testCase "syncs date-prefixed post from repo to vault" $
      withSystemTempDirectory "sync-test" $ \tmpDir -> do
        let repoRoot = tmpDir </> "repo"
            vaultDir = tmpDir </> "vault"
            repoSeriesDir = repoRoot </> "the-noise"
        createDirectoryIfMissing True repoSeriesDir
        createDirectoryIfMissing True (vaultDir </> "the-noise")
        TIO.writeFile (repoSeriesDir </> "2026-04-11-first-broadcast.md") "first post content"
        synced <- syncRepoPostsToVault repoRoot "the-noise" vaultDir (const (pure ()))
        synced @?= 1
        content <- TIO.readFile (vaultDir </> "the-noise" </> "2026-04-11-first-broadcast.md")
        content @?= "first post content"

  , testCase "skips posts that already exist in vault" $
      withSystemTempDirectory "sync-test" $ \tmpDir -> do
        let repoRoot = tmpDir </> "repo"
            vaultDir = tmpDir </> "vault"
            repoSeriesDir = repoRoot </> "the-noise"
            vaultSeriesDir = vaultDir </> "the-noise"
        createDirectoryIfMissing True repoSeriesDir
        createDirectoryIfMissing True vaultSeriesDir
        TIO.writeFile (repoSeriesDir </> "2026-04-11-first-broadcast.md") "repo version"
        TIO.writeFile (vaultSeriesDir </> "2026-04-11-first-broadcast.md") "vault version"
        synced <- syncRepoPostsToVault repoRoot "the-noise" vaultDir (const (pure ()))
        synced @?= 0
        content <- TIO.readFile (vaultSeriesDir </> "2026-04-11-first-broadcast.md")
        content @?= "vault version"

  , testCase "ignores non-date files like AGENTS.md" $
      withSystemTempDirectory "sync-test" $ \tmpDir -> do
        let repoRoot = tmpDir </> "repo"
            vaultDir = tmpDir </> "vault"
            repoSeriesDir = repoRoot </> "the-noise"
        createDirectoryIfMissing True repoSeriesDir
        createDirectoryIfMissing True (vaultDir </> "the-noise")
        TIO.writeFile (repoSeriesDir </> "AGENTS.md") "agent content"
        TIO.writeFile (repoSeriesDir </> "index.md") "index content"
        synced <- syncRepoPostsToVault repoRoot "the-noise" vaultDir (const (pure ()))
        synced @?= 0

  , testCase "returns zero when repo directory does not exist" $ do
      synced <- syncRepoPostsToVault "/nonexistent" "the-noise" "/also-nonexistent" (const (pure ()))
      synced @?= 0

  , testCase "creates vault series directory if missing" $
      withSystemTempDirectory "sync-test" $ \tmpDir -> do
        let repoRoot = tmpDir </> "repo"
            vaultDir = tmpDir </> "vault"
            repoSeriesDir = repoRoot </> "new-series"
        createDirectoryIfMissing True repoSeriesDir
        TIO.writeFile (repoSeriesDir </> "2026-04-11-hello.md") "hello"
        synced <- syncRepoPostsToVault repoRoot "new-series" vaultDir (const (pure ()))
        synced @?= 1
        exists <- doesFileExist (vaultDir </> "new-series" </> "2026-04-11-hello.md")
        assertBool "post should exist in vault" exists
  ]

properties :: TestTree
properties = testGroup "properties"
  [ testProperty "findBestMatch score is non-negative" $
      QC.forAll genNonEmptyText $ \content ->
        QC.forAll (QC.listOf genVaultEntry) $ \vault ->
          fst (findBestMatch (T.pack content) (fmap (Data.Bifunctor.second T.pack) vault)) >= 0.0

  , testProperty "findBestMatch with identical content in vault scores 1.0" $
      QC.forAll genNonEmptyText $ \content ->
        let textContent = T.pack content
            vault = [("match.md", textContent)]
        in fst (findBestMatch textContent vault) == 1.0

  , testProperty "showScore produces parseable output" $
      QC.forAll (QC.choose (0.0, 1.0)) $ \score ->
        let rendered = showScore score
            parsed = reads rendered :: [(Double, String)]
        in not (null parsed)
  ]

genNonEmptyText :: QC.Gen String
genNonEmptyText = QC.listOf1 (QC.elements (['a'..'z'] <> [' ']))

genVaultEntry :: QC.Gen (FilePath, String)
genVaultEntry = do
  filename <- QC.listOf1 (QC.elements (['a'..'z'] <> ['-', '.']))
  body <- QC.listOf1 (QC.elements (['a'..'z'] <> [' ']))
  pure (filename, body)
