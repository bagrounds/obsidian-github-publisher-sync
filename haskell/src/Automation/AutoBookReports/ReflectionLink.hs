{-# LANGUAGE OverloadedStrings #-}

-- | Insert a wikilink to a newly-generated book report into a daily reflection.
--
-- All logic is pure. The orchestrator reads/writes the reflection file.
module Automation.AutoBookReports.ReflectionLink
  ( booksSectionHeading
  , booksLinkPrefix
  , buildBookListItem
  , insertBookLink
  ) where

import Data.Text (Text)
import qualified Data.Text as T

-- | The exact text of the H2 heading that introduces the Books section in a
-- daily reflection. We match against this verbatim — keeping it as a top-level
-- value makes the convention obvious and easy to change.
--
-- Example reflection content:
--
-- > ## [📚 Books](../books/index.md)
-- > - ⏯️ Continuing [🧪⚙️🧠 The Art of Doing Science and Engineering](../books/the-art-of-doing-science-and-engineering.md)
booksSectionHeading :: Text
booksSectionHeading = "## [📚 Books](../books/index.md)"

-- | Prefix used to mark a list item as an auto-generated book report.
--
-- The 🆕 distinguishes auto-discovered books from the user's own reading
-- entries (which use ▶️ Starting / ⏯️ Continuing / ⏹️ Finished). This makes
-- it easy to grep for and easy to revert if the user disagrees with a pick.
booksLinkPrefix :: Text
booksLinkPrefix = "- 🆕📚 Auto-generated report on "

-- | Build a list item linking to the new book report.
--
-- Uses an Obsidian wikilink so the format matches the vault. The publisher
-- converts wikilinks to relative markdown links at build time.
buildBookListItem :: Text -> Text -> Text
buildBookListItem slug title =
  booksLinkPrefix <> "[[books/" <> slug <> "|" <> title <> "]]"

-- | Insert (or de-duplicate) a book list item under the Books section.
--
-- - If the section exists and already contains a link to this slug → no-op.
-- - If the section exists → append the new item after the last existing list item.
-- - If the section does not exist → create it just before the first H2 that
--   isn't the Books section, or at the end of the file otherwise.
insertBookLink :: Text -> Text -> Text -> Text
insertBookLink content slug title =
  let target = "[[books/" <> slug <> "|"
  in if T.isInfixOf target content
       then content
       else
         let item = buildBookListItem slug title
             contentLines = T.splitOn "\n" content
         in case sectionIndex contentLines of
              Just sectionLineIndex ->
                appendInSection contentLines sectionLineIndex item
              Nothing ->
                insertNewSection content item

sectionIndex :: [Text] -> Maybe Int
sectionIndex contentLines =
  let indexed = zip [0 :: Int ..] contentLines
      matches = [i | (i, l) <- indexed, T.stripEnd l == booksSectionHeading]
  in case matches of
    []      -> Nothing
    (i : _) -> Just i

appendInSection :: [Text] -> Int -> Text -> Text
appendInSection contentLines sectionLineIndex item =
  let (before, fromHeading) = splitAt (sectionLineIndex + 1) contentLines
      (listItems, rest) = span isListOrTrailing fromHeading
      (head', trailing) = spanEnd T.null listItems
  in T.intercalate "\n" (before <> head' <> [item] <> trailing <> rest)
  where
    isListOrTrailing line =
      T.isPrefixOf "- " (T.stripStart line) || T.null (T.strip line)

-- | 'span' from the end of the list. Returns @(prefix, suffix)@ where every
-- element of @suffix@ satisfies the predicate.
spanEnd :: (a -> Bool) -> [a] -> ([a], [a])
spanEnd predicate xs =
  let (sufRev, prefRev) = span predicate (reverse xs)
  in (reverse prefRev, reverse sufRev)

insertNewSection :: Text -> Text -> Text
insertNewSection content item =
  let block = booksSectionHeading <> "\n" <> item
  in T.stripEnd content <> "\n\n" <> block <> "\n"
