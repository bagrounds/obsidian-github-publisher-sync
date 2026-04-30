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
import Control.Concurrent (threadDelay)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text.Encoding as TE
import Data.Maybe (fromMaybe)
import Network.HTTP.Client (Manager)

maximumRetries :: Int
maximumRetries = 3

initialBackoffDurationMicroseconds :: Int
initialBackoffDurationMicroseconds = 5_000_000

maximumBackoffDurationMicroseconds :: Int
maximumBackoffDurationMicroseconds = 60_000_000

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
  let cleaned = extractJsonArray raw
  in fromMaybe [] (decode (encodeToLbs cleaned) :: Maybe [Text])
  where
    encodeToLbs :: Text -> LBS.ByteString
    encodeToLbs text = LBS.fromStrict (TE.encodeUtf8 text)

extractJsonArray :: Text -> Text
extractJsonArray txt =
  let stripped = T.strip txt
      unfencedText = stripFences stripped
  in case (T.findIndex (== '[') unfencedText, findLastIndex (== ']') unfencedText) of
    (Just start, Just end) -> T.take (end - start + 1) (T.drop start unfencedText)
    _                      -> unfencedText

stripFences :: Text -> Text
stripFences txt =
  let noStart = fromMaybe txt (T.stripPrefix "```json" txt >>= Just . T.strip)
      noStart' = fromMaybe noStart (T.stripPrefix "```" noStart >>= Just . T.strip)
  in fromMaybe noStart' (T.stripSuffix "```" noStart' >>= Just . T.strip)

findLastIndex :: (Char -> Bool) -> Text -> Maybe Int
findLastIndex predicate txt = go Nothing 0 (T.unpack txt)
  where
    go acc _ [] = acc
    go acc index (character : rest)
      | predicate character = go (Just index) (index + 1) rest
      | otherwise           = go acc (index + 1) rest

-- | Build the book report generation prompt for a given title.
buildReportPrompt :: Text -> Text
buildReportPrompt bookTitle = T.intercalate " "
  [ "Write a markdown-formatted (start headings at level H2) book report,"
  , "followed by a plethora of additional similar, contrasting, and creatively related book"
  , "recommendations on " <> bookTitle <> "."
  , "Be thorough in content discussed but concise and economical with your language."
  , "Structure the report with section headings and bulleted lists to avoid long blocks of text."
  , "Never quote or italicize titles."
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
findBookMentionsWithGemini :: Manager -> Secret -> Gemini.Model -> Text -> IO (Either Text [Text])
findBookMentionsWithGemini manager apiKey model body =
  retryFindMentions manager apiKey model (buildFindMentionsPrompt body) 0 initialBackoffDurationMicroseconds

retryFindMentions :: Manager -> Secret -> Gemini.Model -> Text -> Int -> Int -> IO (Either Text [Text])
retryFindMentions manager apiKey model prompt attempt backoff = do
  result <- Gemini.generateContent manager Gemini.Request
    { Gemini.requestPrompt            = prompt
    , Gemini.requestSystemInstruction = Nothing
    , Gemini.requestModel             = model
    , Gemini.requestApiKey            = apiKey
    , Gemini.requestGenerationConfig  = Gemini.defaultGenerationConfig
        { Gemini.temperature     = 0.0
        , Gemini.maxOutputTokens = 1024
        , Gemini.searchGrounding = False
        }
    }
  case result of
    Right response ->
      pure (Right (parseMentionsList (Gemini.responseText response)))
    Left err
      | Gemini.isRateLimitError err && attempt < maximumRetries -> do
          putStrLn $ "  ⏳ Rate limit, retry " <> show (attempt + 1) <> "/" <> show maximumRetries
            <> " in " <> show (backoff `div` 1_000_000) <> "s"
          threadDelay backoff
          retryFindMentions manager apiKey model prompt (attempt + 1) (min (backoff * 2) maximumBackoffDurationMicroseconds)
      | Gemini.isQuotaExhaustedError err ->
          pure (Left ("QuotaExhausted: " <> T.pack (show err)))
      | otherwise ->
          pure (Left (T.pack (show err)))

-- | Generate a book report for the given title using Gemini.
generateBookReportWithGemini :: Manager -> Secret -> Gemini.Model -> Text -> IO (Either Text Text)
generateBookReportWithGemini manager apiKey model bookTitle = do
  let prompt = buildReportPrompt bookTitle
  result <- Gemini.generateContent manager Gemini.Request
    { Gemini.requestPrompt            = prompt
    , Gemini.requestSystemInstruction = Nothing
    , Gemini.requestModel             = model
    , Gemini.requestApiKey            = apiKey
    , Gemini.requestGenerationConfig  = Gemini.defaultGenerationConfig
        { Gemini.temperature     = 0.7
        , Gemini.maxOutputTokens = 4096
        , Gemini.searchGrounding = False
        }
    }
  case result of
    Right response -> pure (Right (Gemini.responseText response))
    Left err       -> pure (Left (T.pack (show err)))

-- | Use Gemini with Google Search grounding to find the Amazon.com product URL for a book.
-- Returns Just url if an Amazon product URL is found, Nothing otherwise.
searchAmazonProductUrl :: Manager -> Secret -> Gemini.Model -> Text -> IO (Maybe Text)
searchAmazonProductUrl manager apiKey model bookTitle = do
  let prompt = buildAmazonSearchPrompt bookTitle
  result <- Gemini.generateContent manager Gemini.Request
    { Gemini.requestPrompt            = prompt
    , Gemini.requestSystemInstruction = Nothing
    , Gemini.requestModel             = model
    , Gemini.requestApiKey            = apiKey
    , Gemini.requestGenerationConfig  = Gemini.defaultGenerationConfig
        { Gemini.temperature     = 0.0
        , Gemini.maxOutputTokens = 256
        , Gemini.searchGrounding = True
        }
    }
  case result of
    Left _ -> pure Nothing
    Right response ->
      let sources = Gemini.responseGroundingSources response
          amazonUrls = filter isAmazonProductUrl (fmap (unUrl . Gemini.groundingSourceUrl) sources)
          responseText = T.strip (Gemini.responseText response)
      in case amazonUrls of
        (url : _) -> pure (Just url)
        [] ->
          if isAmazonProductUrlText responseText && responseText /= "NOT_FOUND"
            then pure (Just responseText)
            else pure Nothing

isAmazonProductUrl :: Text -> Bool
isAmazonProductUrl = isAmazonProductUrlText

isAmazonProductUrlText :: Text -> Bool
isAmazonProductUrlText url =
  T.isPrefixOf "https://www.amazon.com/" url
    && T.isInfixOf "/dp/" url
