{-# LANGUAGE OverloadedStrings #-}

-- | Discovery of book candidates from the vault.
--
-- Pure logic for:
--   * enumerating known book slugs already present in @<vault>/books/@
--   * selecting the recent reflection files we want to scan for candidates
--   * extracting the body text from each reflection (frontmatter stripped)
--
-- All IO is performed by the orchestrator which calls into these pure helpers.
module Automation.AutoBookReports.Discovery
  ( recentReflectionWindow
  , isReflectionFile
  , filterRecentReflections
  , knownBookSlug
  , extractReflectionBody
  ) where

import Data.Char (isDigit)
import Data.List (sortBy)
import Data.Ord (Down (..))
import Data.Text (Text)
import qualified Data.Text as T
import System.FilePath (takeBaseName, takeExtension)

import Automation.Frontmatter (parseFrontmatter)

-- | How many of the most-recent reflection files to scan for candidates.
--
-- A short window keeps the prompt focused on truly recent reading. Increase
-- this if the user typically writes about a book over a longer span.
recentReflectionWindow :: Int
recentReflectionWindow = 7

-- | True for filenames that match the @YYYY-MM-DD.md@ reflection pattern.
isReflectionFile :: FilePath -> Bool
isReflectionFile path =
  let name = takeBaseName path
  in length name == 10
        && takeExtension path == ".md"
        && all isDigit (take 4 name)
        && safeIndex name 4 == Just '-'
        && all isDigit (take 2 (drop 5 name))
        && safeIndex name 7 == Just '-'
        && all isDigit (take 2 (drop 8 name))

safeIndex :: [a] -> Int -> Maybe a
safeIndex xs index
  | index >= 0 && index < length xs = Just (xs !! index)
  | otherwise = Nothing

-- | Pick the most recent reflection filenames (lexicographic = chronological
-- because of the @YYYY-MM-DD@ prefix), capped at 'recentReflectionWindow'.
filterRecentReflections :: [FilePath] -> [FilePath]
filterRecentReflections =
  take recentReflectionWindow
    . sortBy (\left right -> compare (Down left) (Down right))
    . filter isReflectionFile

-- | Convert a markdown filename like @"deep-work.md"@ into its slug
-- @"deep-work"@. Returns 'Nothing' when the file does not have a @.md@
-- extension.
knownBookSlug :: FilePath -> Maybe Text
knownBookSlug path
  | takeExtension path == ".md" = Just (T.pack (takeBaseName path))
  | otherwise = Nothing

-- | Drop the YAML frontmatter from a reflection file, returning the markdown
-- body. The body is what we feed to the identifier prompt.
extractReflectionBody :: Text -> Text
extractReflectionBody content =
  let (_frontmatter, body) = parseFrontmatter content
  in T.strip body
