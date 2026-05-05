{-# LANGUAGE OverloadedStrings #-}

-- | Building a generated book report markdown file.
--
-- Pure logic for:
--   * generating a slug from a book title
--   * assembling YAML frontmatter
--   * building the Gemini prompt that produces the body
--   * composing the full markdown file (frontmatter + nav + heading + image
--     placeholder + affiliate link + body)
module Automation.AutoBookReports.Report
  ( ReportInput (..)
  , generateBookSlug
  , buildReportPrompt
  , assembleBookReport
  ) where

import Data.Char (isAsciiLower, isDigit)
import Data.Text (Text)
import qualified Data.Text as T

import Automation.Frontmatter (quoteYamlValue)
import Automation.Text (isEmoji)

-- | Everything needed to assemble a finished book-report markdown file.
data ReportInput = ReportInput
  { reportTitle        :: Text   -- ^ Canonical title (no emojis, no date prefix).
  , reportAuthor       :: Text
  , reportSlug         :: Text   -- ^ Slug derived from 'reportTitle'.
  , reportAffiliateUrl :: Text   -- ^ Full URL with @?tag=...@.
  , reportBody         :: Text   -- ^ Markdown body returned from Gemini (starts with H2 sections).
  , reportTodayIso     :: Text   -- ^ Today's date as @YYYY-MM-DDT00:00:00Z@.
  , reportModelUsed    :: Text   -- ^ Gemini model identifier for the signature.
  , reportPromptText   :: Text   -- ^ The exact prompt that produced 'reportBody', for traceability.
  } deriving (Show, Eq)

-- | Convert a title into a URL-safe slug.
--
-- - Lower-cases the title
-- - Drops emojis
-- - Replaces non-alphanumeric runs with a single hyphen
-- - Trims leading/trailing hyphens
generateBookSlug :: Text -> Text
generateBookSlug title =
  let withoutEmojis = T.filter (not . isEmoji) title
      lowered = T.toLower (T.strip withoutEmojis)
      mapped = T.map (\c -> if isSlugChar c then c else ' ') lowered
      hyphenated = T.intercalate "-" (T.words mapped)
      trimmed = T.dropWhile (== '-') (T.dropWhileEnd (== '-') hyphenated)
  in trimmed
  where
    isSlugChar c = isAsciiLower c || isDigit c || c == ' ' || c == '-'

-- | The generation prompt asks Gemini to write a structured book report
-- following the established conventions used across @content/books/@.
buildReportPrompt :: Text -> Text -> (Text, Text)
buildReportPrompt title author =
  let systemInstruction = T.intercalate "\n"
        [ "You are writing a book report for a personal knowledge base. The report follows a strict structure."
        , ""
        , "Write the report in markdown, starting at heading level H2. Use bulleted lists liberally; avoid long blocks of prose."
        , "Use a generous sprinkling of relevant emojis throughout — every section heading and most bullet points should begin or end with an emoji."
        , ""
        , "Required sections (in this order, all H2):"
        , "## 📚 Book Report: <full title> by <author>"
        , "### 💡 Overview"
        , "### ✨ Key Themes"
        , "### 📑 Content Highlights"
        , "## 📚 Additional Book Recommendations"
        , "### Similar"
        , "### Contrasting"
        , "### Creatively Related"
        , ""
        , "Each recommendation must be in the form: <Title> by <Author> — <one-sentence reason>."
        , "Do NOT invent ASINs, URLs, or wikilinks. Plain prose only."
        , "Do NOT include a top-level H1, frontmatter, or any preamble. Start directly with the first H2."
        ]
      userPrompt = "Write the book report for:\nTitle: " <> title <> "\nAuthor: " <> author
  in (systemInstruction, userPrompt)

-- | Compose the final markdown file from the generated body + structured input.
assembleBookReport :: ReportInput -> Text
assembleBookReport input =
  let frontmatter = T.intercalate "\n"
        [ "---"
        , "title: " <> quoteYamlValue (reportTitle input)
        , "aliases:"
        , "  - " <> quoteYamlValue (reportTitle input)
        , "URL: " <> quoteYamlValue ("https://bagrounds.org/books/" <> reportSlug input)
        , "share: true"
        , "affiliate link: " <> reportAffiliateUrl input
        , "auto_generated: true"
        , "auto_generated_at: " <> reportTodayIso input
        , "auto_generated_model: " <> quoteYamlValue (reportModelUsed input)
        , "---"
        ]
      navLine = "[Home](../index.md) > [Books](./index.md)  "
      h1Line = "# " <> reportTitle input <> "  "
      imageLine = "![books-" <> reportSlug input <> "](../books-" <> reportSlug input <> ".jpg)  "
      affiliateLine = "[🛒 " <> reportTitle input <> ". As an Amazon Associate I earn from qualifying purchases.](" <> reportAffiliateUrl input <> ")  "
      signatureLine = "## 💬 Auto-Generated Report (" <> reportModelUsed input <> ")\n> " <> reportPromptText input
  in T.intercalate "\n"
       [ frontmatter
       , navLine
       , h1Line
       , imageLine
       , affiliateLine
       , ""
       , T.strip (reportBody input)
       , ""
       , signatureLine
       , ""
       ]
