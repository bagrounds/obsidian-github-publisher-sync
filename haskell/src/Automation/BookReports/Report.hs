module Automation.BookReports.Report
  ( buildReportPrompt
  , reportSystemInstruction
  , assembleReportFile
  , bookFilePath
  , reportFrontmatter
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (Day)
import System.FilePath ((</>))

import Automation.PacificTime (formatDay)
import Automation.BookReports.Amazon (AmazonAffiliateUrl, unAmazonAffiliateUrl)
import Automation.BookReports.Types
  ( AmazonVariant
  , BookSlug
  , BookTitle
  , unBookSlug
  , unBookTitle
  , variantToText
  )

reportSystemInstruction :: Text
reportSystemInstruction =
  T.unlines
    [ "You are a thoughtful, opinionated reader writing a book report for a personal knowledge base."
    , "Output Obsidian-flavored markdown only — no JSON, no commentary, no code fences."
    , "Every heading, sentence, list item, and table cell MUST begin with a relevant emoji."
    , "Never put book titles in italics or quotes — write them plainly."
    , "Write for text-to-speech listening: prefer descriptive prose over tables and inline code."
    , "Cite reputable sources where appropriate but do not invent quotations."
    ]

buildReportPrompt :: BookTitle -> AmazonAffiliateUrl -> AmazonVariant -> Text
buildReportPrompt title affiliateUrl variant =
  T.unlines
    [ "Write a complete book report for the book titled below, following this exact structure:"
    , ""
    , "1. The very first line of the body MUST be `# <emoji-rich title>` — emojis BEFORE the words, capturing the book's themes."
    , "2. A one-paragraph TL;DR."
    , "3. ## 🤖 AI Summary — a tight cheat-sheet covering: New or Surprising Perspective, Topics, Methods and Research, Theories and Mental Models."
    , "4. ## 📊 Evaluation — strengths, weaknesses, and how the book holds up under scrutiny. Cite reputable sources where relevant."
    , "5. ## 🧠 Topics for Further Understanding — adjacent ideas worth exploring next."
    , "6. ## ❓ FAQ — three to six anticipated reader questions with concise answers."
    , "7. ## 📚 Book Recommendations — three sub-sections (### 📖 Similar, ### ↔️ Contrasting, ### 🔗 Related). Each item: `Title by Author — explanation of why it is relevant`."
    , "8. ## 💬 What Do You Think? — three to five open discussion prompts."
    , ""
    , "Constraints:"
    , "- Every heading, sentence, list item begins with an emoji."
    , "- Never quote or italicize book titles."
    , "- Do NOT include the affiliate link, frontmatter, navigation, or any meta content. Those are added programmatically."
    , "- Do NOT wrap output in code fences."
    , ""
    , "Book to report on:"
    , "  Title:   "   <> unBookTitle title
    , "  Variant: "   <> variantToText variant
    , "  Amazon:  "   <> unAmazonAffiliateUrl affiliateUrl <> " (for context only — do not include in body)"
    ]

bookFilePath :: FilePath -> BookSlug -> FilePath
bookFilePath vaultDir slug =
  vaultDir </> "books" </> T.unpack (unBookSlug slug) <> ".md"

reportFrontmatter
  :: BookTitle
  -> AmazonAffiliateUrl
  -> AmazonVariant
  -> Day
  -> Text          -- ^ generation model identifier
  -> [Text]
reportFrontmatter title affiliateUrl variant generatedOn modelText =
  [ "---"
  , "share: true"
  , "aliases:"
  , "  - " <> unBookTitle title
  , "title: "         <> unBookTitle title
  , "URL: https://bagrounds.org/books/" <> "{{slug}}"
  , "Author:"
  , "tags:"
  , "affiliate link: " <> unAmazonAffiliateUrl affiliateUrl
  , "amazon_variant: " <> variantToText variant
  , "auto_generated: true"
  , "auto_generated_by: " <> modelText
  , "auto_generated_on: " <> formatDay generatedOn
  , "---"
  ]

assembleReportFile
  :: BookTitle
  -> BookSlug
  -> AmazonAffiliateUrl
  -> AmazonVariant
  -> Day
  -> Text          -- ^ Gemini model identifier (for traceability)
  -> Text          -- ^ raw report body (already emoji-rich, starts with `# title`)
  -> Text
assembleReportFile title slug affiliateUrl variant today modelText body =
  let urlLine = "URL: https://bagrounds.org/books/" <> unBookSlug slug
      frontmatter = fmap (replaceUrlPlaceholder urlLine)
                      (reportFrontmatter title affiliateUrl variant today modelText)
      navigation =
        [ "[Home](../index.md) > [Books](./index.md)"
        , ""
        ]
      affiliateAttribution =
        [ "[🛒 " <> unBookTitle title <> ". As an Amazon Associate I earn from qualifying purchases.]("
            <> unAmazonAffiliateUrl affiliateUrl <> ")"
        , ""
        ]
  in T.intercalate "\n"
       (frontmatter <> navigation <> affiliateAttribution <> [T.stripEnd body, ""])
  where
    replaceUrlPlaceholder canonical line =
      if T.isPrefixOf "URL:" line then canonical else line
