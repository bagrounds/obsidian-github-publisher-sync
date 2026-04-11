module Automation.VaultSync
  ( syncFileToVault
  , syncNewAiBlogPosts
  , copySeriesPosts
  , ensureFileInVault
  , findBestMatch
  , showScore
  , similarityThreshold
  ) where

import Data.Char (isDigit)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, doesFileExist, listDirectory)
import System.FilePath (takeExtension, (</>))

import Automation.Text (wordJaccardSimilarity)

-- ---------------------------------------------------------------------------
-- syncFileToVault (local implementation matching TypeScript)
-- ---------------------------------------------------------------------------

syncFileToVault :: FilePath -> FilePath -> FilePath -> IO Bool
syncFileToVault localPath vaultRelativePath vaultDirectory = do
  let vaultPath = vaultDirectory </> vaultRelativePath
  localExists <- doesFileExist localPath
  if not localExists
    then pure False
    else do
      localContent <- TIO.readFile localPath
      vaultExists <- doesFileExist vaultPath
      if vaultExists
        then do
          vaultContent <- TIO.readFile vaultPath
          if localContent == vaultContent
            then pure False
            else do
              createDirectoryIfMissing True (takeDirectory vaultPath)
              TIO.writeFile vaultPath localContent
              pure True
        else do
          createDirectoryIfMissing True (takeDirectory vaultPath)
          TIO.writeFile vaultPath localContent
          pure True
  where
    takeDirectory = reverse . dropWhile (/= '/') . reverse

-- ---------------------------------------------------------------------------
-- syncNewAiBlogPosts (copy-if-missing with content similarity dedup)
-- ---------------------------------------------------------------------------

-- | Similarity threshold for dedup. Posts scoring above this against any
--   vault file are considered modified versions, not new content.
--
--   Empirically derived from the ai-blog corpus:
--     genuinely new posts:       max Jaccard similarity 0.22
--     renamed/modified versions: min Jaccard similarity 0.53
--   Threshold sits in the middle of a 0.31-wide gap.
similarityThreshold :: Double
similarityThreshold = 0.25

syncNewAiBlogPosts :: FilePath -> FilePath -> (Text -> IO ()) -> IO Int
syncNewAiBlogPosts repoDirectory vaultDirectory logger = do
  repoExists <- doesDirectoryExist repoDirectory
  if not repoExists
    then pure 0
    else do
      createDirectoryIfMissing True vaultDirectory
      vaultEntries <- listDirectory vaultDirectory
      let vaultMarkdownFiles = filter isAiBlogPost vaultEntries
          vaultFilenames = fmap T.pack vaultMarkdownFiles
      vaultContents <- traverse (\filename -> TIO.readFile (vaultDirectory </> filename)) vaultMarkdownFiles
      repoEntries <- listDirectory repoDirectory
      let repoMarkdownFiles = filter isAiBlogPost repoEntries
      counts <- traverse (syncIfNew repoDirectory vaultDirectory vaultFilenames (zip vaultMarkdownFiles vaultContents) logger) repoMarkdownFiles
      pure (sum counts)
  where
    isAiBlogPost filename = takeExtension filename == ".md" && filename /= "index.md" && filename /= "AGENTS.md"

syncIfNew :: FilePath -> FilePath -> [Text] -> [(FilePath, Text)] -> (Text -> IO ()) -> FilePath -> IO Int
syncIfNew sourceDirectory destinationDirectory vaultFilenames vaultContents logger filename = do
  let filenameText = T.pack filename
  if filenameText `elem` vaultFilenames
    then pure 0
    else do
      repoContent <- TIO.readFile (sourceDirectory </> filename)
      let (bestScore, bestMatch) = findBestMatch repoContent vaultContents
      if bestScore >= similarityThreshold
        then do
          logger $ "  ⏭️  Skipping " <> filenameText
            <> " (Jaccard " <> T.pack (showScore bestScore) <> " with " <> T.pack bestMatch <> ")"
          pure 0
        else do
          TIO.writeFile (destinationDirectory </> filename) repoContent
          logger $ "  📄 New post → vault: " <> filenameText
            <> " (best Jaccard " <> T.pack (showScore bestScore) <> ")"
          pure 1

findBestMatch :: Text -> [(FilePath, Text)] -> (Double, FilePath)
findBestMatch repoContent = foldl pickBest (0.0, "(none)")
  where
    pickBest (bestScore, bestFile) (vaultFile, vaultContent) =
      let score = wordJaccardSimilarity repoContent vaultContent
      in if score > bestScore
           then (score, vaultFile)
           else (bestScore, bestFile)

showScore :: Double -> String
showScore value =
  let rounded = fromIntegral (round (value * 1000) :: Int) / 1000 :: Double
  in show rounded

-- ---------------------------------------------------------------------------
-- copySeriesPosts (matches TypeScript pull-vault-posts.ts)
-- ---------------------------------------------------------------------------

copySeriesPosts :: FilePath -> Text -> FilePath -> IO Int
copySeriesPosts vaultDirectory seriesIdentifier repoRoot = do
  let vaultSeriesDirectory = vaultDirectory </> T.unpack seriesIdentifier
      localSeriesDirectory = repoRoot </> T.unpack seriesIdentifier
  vaultExists <- doesDirectoryExist vaultSeriesDirectory
  if not vaultExists
    then pure 0
    else do
      entries <- listDirectory vaultSeriesDirectory
      let dateFiles = filter isDateFile entries
      createDirectoryIfMissing True localSeriesDirectory
      mapM_ (copyFile' vaultSeriesDirectory localSeriesDirectory) dateFiles
      pure (length dateFiles)
  where
    isDateFile filename =
      length filename >= 14
        && takeExtension filename == ".md"
        && all isDigit (take 4 filename)
        && filename !! 4 == '-'
    copyFile' sourceDirectory destinationDirectory filename = do
      content <- TIO.readFile (sourceDirectory </> filename)
      TIO.writeFile (destinationDirectory </> filename) content

-- ---------------------------------------------------------------------------
-- ensureFileInVault (create-if-not-exists for bootstrap files)
-- ---------------------------------------------------------------------------

ensureFileInVault :: FilePath -> Text -> IO Bool
ensureFileInVault vaultPath content = do
  exists <- doesFileExist vaultPath
  if exists
    then pure False
    else do
      createDirectoryIfMissing True (takeDirectory vaultPath)
      TIO.writeFile vaultPath content
      pure True
  where
    takeDirectory = reverse . dropWhile (/= '/') . reverse
