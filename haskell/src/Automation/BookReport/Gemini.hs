{-# LANGUAGE OverloadedStrings #-}

module Automation.BookReport.Gemini
  ( buildFindMentionsPrompt
  , parseMentionsList
  , buildReportPrompt
  , buildAmazonSearchPrompt
  , findBookMentionsWithGemini
  , generateBookReportWithGemini
  , searchAmazonProductUrl
  ) where

import Automation.Json (decode)
import Automation.Secret (Secret)
import Automation.Url (unUrl)
import qualified Automation.Gemini as Gemini
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text.Encoding as TE
import Data.Maybe (fromMaybe)
import Network.HTTP.Client (Manager)

-- | Build a prompt asking Gemini to find all plain-text book mentions in a document
-- (i.e., titles not already wrapped in [[wikilinks]]).
buildFindMentionsPrompt :: Text -> Text
buildFindMentionsPrompt body = T.intercalate "\n"
  [ "You are a librarian's assistant. Find all books mentioned by title in the following document."
  , ""
  , "Rules:"
  , "- Only include books that appear as plain text — NOT inside [[double-bracket wikilinks]]"
  , "- Only include genuine book references — the text must be discussing, recommending, or citing the book"
  , "- Return the title as it appears in the text (do not normalise or abbreviate)"
  , "- Return a JSON array of title strings. If no books are found, return []."
  , "- No other text, no explanation, no markdown formatting."
  , ""
  , "Example output: [\"The Hitchhiker's Guide to the Galaxy\", \"Thinking, Fast and Slow\"]"
  , ""
  , "Document:"
  , body
  ]

-- | Parse a Gemini response into a list of book title strings.
-- Expects a JSON array; returns empty list on any parse failure.
parseMentionsList :: Text -> [Text]
parseMentionsList raw =
  let cleaned = Gemini.extractJsonArray raw
  in fromMaybe [] (decode (encodeToLbs cleaned) :: Maybe [Text])
  where
    encodeToLbs :: Text -> LBS.ByteString
    encodeToLbs text = LBS.fromStrict (TE.encodeUtf8 text)

-- | Build the book report generation prompt for a given title.
-- Follows the Obsidian book template structure, producing an emojified title
-- on the first line followed by all report sections.
buildReportPrompt :: Text -> Text
buildReportPrompt bookTitle = T.intercalate "\n"
  [ "Act as a world-class, critically-minded expert on the book " <> bookTitle <> "."
  , ""
  , "First, output a single line containing only the emojified book title:"
  , "  <emoji(s)> " <> bookTitle
  , "(Prefix with the smallest set of emojis that accurately capture the book's meaning."
  , "Put 1 space between the final emoji and the first word. Return only the result on that line.)"
  , ""
  , "Then write the following sections in order."
  , "Begin every heading, bullet point, and line of text with a relevant emoji."
  , "Never quote or italicize titles. Be ultra-concise."
  , ""
  , "One sentence TLDR (emojis at the start, plain text, no heading)."
  , ""
  , "## 🤖 AI Summary"
  , "Ultra-concise cheat sheet with ### subsections. Full sentences not required."
  , "E.g.: \"Protein: 1.6 g/kg min. Muscle preservation.\" Nested bullets. No tables."
  , ""
  , "## ⚖️ Evaluation"
  , "Compare the book's main claims with high-quality, unbiased sources."
  , "Cite each point in brackets, e.g. [Source, Year]. No extreme or politically biased sources."
  , ""
  , "## 🔍 Topics for Further Understanding"
  , "Bulleted list of distinct related topics not explicitly covered in the book."
  , ""
  , "## ❓ Frequently Asked Questions (FAQ)"
  , "Questions real readers search for. Each question must be self-contained (use the full book title)."
  , "Format each as:"
  , "### 💡 Q: ...question...?"
  , "✅ A: ...concise authoritative answer..."
  , ""
  , "## 📚 Book Recommendations"
  , "### 📖 Similar"
  , "### ↔️ Contrasting"
  , "### 🔗 Related"
  , ""
  , "## 💭 What Do You Think?"
  , "1-2 open-ended engaging questions inviting readers to share their thoughts in the comments."
  ]

-- | Build a search prompt to find the Amazon.com product URL for a book.
buildAmazonSearchPrompt :: Text -> Text
buildAmazonSearchPrompt bookTitle = T.intercalate "\n"
  [ "Search for the book \"" <> bookTitle <> "\" on Amazon.com."
  , "Return the Amazon.com product page URL for the most popular print version."
  , "The URL must start with https://www.amazon.com/ and contain /dp/ followed by the ASIN."
  , "Return ONLY the URL, nothing else. If not found, return: NOT_FOUND"
  ]

-- | Ask Gemini to identify plain-text book mentions in the given file body.
-- Returns a list of book titles or a Left error if the API call fails permanently.
-- Uses 'Gemini.generateContentWithRetry' to retry on transient rate-limit errors.
findBookMentionsWithGemini :: Manager -> Secret -> Gemini.Model -> Text -> IO (Either Text [Text])
findBookMentionsWithGemini manager apiKey model body = do
  result <- Gemini.generateContentWithRetry manager Gemini.Request
    { Gemini.requestPrompt            = buildFindMentionsPrompt body
    , Gemini.requestSystemInstruction = Nothing
    , Gemini.requestModel             = model
    , Gemini.requestApiKey            = apiKey
    , Gemini.requestGenerationConfig  = Gemini.defaultGenerationConfig
        { Gemini.temperature     = 0.0
        , Gemini.maxOutputTokens = 1024
        , Gemini.searchGrounding = False
        }
    }
  pure $ case result of
    Right response -> Right (parseMentionsList (Gemini.responseText response))
    Left err       -> Left (T.pack (show err))

-- | Generate a book report for the given title using Gemini with Google Search grounding.
-- The response begins with an emojified title line followed by the full report body.
-- Uses 'Gemini.generateContentWithRetry' to retry on transient rate-limit errors.
generateBookReportWithGemini :: Manager -> Secret -> Gemini.Model -> Text -> IO (Either Text Text)
generateBookReportWithGemini manager apiKey model bookTitle = do
  result <- Gemini.generateContentWithRetry manager Gemini.Request
    { Gemini.requestPrompt            = buildReportPrompt bookTitle
    , Gemini.requestSystemInstruction = Nothing
    , Gemini.requestModel             = model
    , Gemini.requestApiKey            = apiKey
    , Gemini.requestGenerationConfig  = Gemini.defaultGenerationConfig
        { Gemini.temperature     = 0.7
        , Gemini.maxOutputTokens = 8192
        , Gemini.searchGrounding = True
        }
    }
  pure $ case result of
    Right response -> Right (Gemini.responseText response)
    Left err       -> Left (T.pack (show err))

-- | Use Gemini with Google Search grounding to find the Amazon.com product URL for a book.
-- Returns Just url if an Amazon product URL is found, Nothing otherwise.
-- Uses 'Gemini.generateContentWithRetry' to retry on transient rate-limit errors.
searchAmazonProductUrl :: Manager -> Secret -> Gemini.Model -> Text -> IO (Maybe Text)
searchAmazonProductUrl manager apiKey model bookTitle = do
  result <- Gemini.generateContentWithRetry manager Gemini.Request
    { Gemini.requestPrompt            = buildAmazonSearchPrompt bookTitle
    , Gemini.requestSystemInstruction = Nothing
    , Gemini.requestModel             = model
    , Gemini.requestApiKey            = apiKey
    , Gemini.requestGenerationConfig  = Gemini.defaultGenerationConfig
        { Gemini.temperature     = 0.0
        , Gemini.maxOutputTokens = 256
        , Gemini.searchGrounding = True
        }
    }
  pure $ case result of
    Left _ -> Nothing
    Right response ->
      let sources = Gemini.responseGroundingSources response
          amazonUrls = filter isAmazonProductUrl (fmap (unUrl . Gemini.groundingSourceUrl) sources)
          responseText = T.strip (Gemini.responseText response)
      in case amazonUrls of
        (url : _) -> Just url
        [] ->
          if isAmazonProductUrl responseText && responseText /= "NOT_FOUND"
            then Just responseText
            else Nothing

isAmazonProductUrl :: Text -> Bool
isAmazonProductUrl url =
  T.isPrefixOf "https://www.amazon.com/" url
    && T.isInfixOf "/dp/" url

