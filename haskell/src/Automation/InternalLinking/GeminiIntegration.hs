{-# LANGUAGE OverloadedStrings #-}

module Automation.InternalLinking.GeminiIntegration
  ( buildIdentificationPrompt
  , identifyBooksWithGemini
  ) where

import Automation.InternalLinking.CandidateDiscovery (ContentEntry (..), extractMainTitle)
import Automation.Json (decode)
import Automation.Types (Secret (..), unRelativePath, unTitle)
import qualified Automation.Gemini as Gemini
import Control.Concurrent (threadDelay)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text.Encoding as TE
import Network.HTTP.Client (Manager)

maxGeminiRetries :: Int
maxGeminiRetries = 3

initialBackoffUs :: Int
initialBackoffUs = 5_000_000

maxBackoffUs :: Int
maxBackoffUs = 60_000_000

buildIdentificationPrompt :: Text -> [ContentEntry] -> Text
buildIdentificationPrompt fileBody bookEntries =
  let formatBookLine e =
        let mainNote = case extractMainTitle (unTitle (cePlainTitle e)) of
              Just mt -> " (also known as \"" <> mt <> "\")"
              Nothing -> ""
        in "- \"" <> unTitle (cePlainTitle e) <> "\"" <> mainNote <> " (" <> unRelativePath (ceRelativePath e) <> ")"
      bookList = T.intercalate "\n" $ fmap formatBookLine bookEntries
      systemPrompt = T.intercalate "\n"
        [ "You are a precise editorial assistant for a knowledge base of book reports. Your job is to identify genuine book references in a document."
        , ""
        , "You will receive:"
        , "1. The body text of a document."
        , "2. A list of book titles and their file paths."
        , ""
        , "Your task: Determine which books from the list are genuinely referenced in the document AS BOOKS (literary works). This means the text is discussing, recommending, citing, or listing the book itself — not merely using a word that happens to match a book title."
        , ""
        , "Rules:"
        , "- Return the relativePath of each book that is genuinely referenced as a book."
        , "- A book reference may use the main title without the subtitle."
        , "- DO NOT include a book if the matching word or phrase is used in a generic context."
        , "- DO include a book when the text explicitly discusses, recommends, or cites it as a literary work."
        , "- Be conservative: when in doubt, do NOT include the book."
        , ""
        , "Return ONLY a valid JSON array of relativePath strings for books genuinely referenced. Example: [\"books/thinking-fast-and-slow.md\", \"books/deep-learning.md\"]"
        , "If no books are genuinely referenced, return an empty array: []"
        , "No other text, no explanation, no markdown formatting."
        ]
  in systemPrompt <> "\n\nAvailable books:\n" <> bookList <> "\n\nDocument body:\n" <> fileBody

identifyBooksWithGemini :: Manager -> Secret -> Gemini.Model -> Text -> [ContentEntry] -> IO (Either Text [Text])
identifyBooksWithGemini _ _ _ _ [] = pure (Right [])
identifyBooksWithGemini manager apiKey model fileBody bookEntries = do
  let prompt = buildIdentificationPrompt fileBody bookEntries
  retryLoop manager apiKey model prompt 0 initialBackoffUs

retryLoop :: Manager -> Secret -> Gemini.Model -> Text -> Int -> Int -> IO (Either Text [Text])
retryLoop manager apiKey model prompt attempt backoff = do
  result <- Gemini.generateContent manager Gemini.Request
    { Gemini.grPrompt           = prompt
    , Gemini.grModel            = model
    , Gemini.grApiKey           = apiKey
    , Gemini.grGenerationConfig = Gemini.GenerationConfig
        { Gemini.gcTemperature     = 0.0
        , Gemini.gcMaxOutputTokens = 1024
        }
    }
  case result of
    Right response ->
      pure (parseGeminiBookPaths (Gemini.responseText response))
    Left err
      | Gemini.isRateLimitError err && attempt < maxGeminiRetries -> do
          putStrLn $ "  ⏳ Rate limit, retry " <> show (attempt + 1) <> "/" <> show maxGeminiRetries
            <> " in " <> show (backoff `div` 1_000_000) <> "s"
          threadDelay backoff
          retryLoop manager apiKey model prompt (attempt + 1) (min (backoff * 2) maxBackoffUs)
      | Gemini.isQuotaExhaustedError err ->
          pure (Left ("QuotaExhausted: " <> T.pack (show err)))
      | otherwise ->
          pure (Left (T.pack (show err)))

parseGeminiBookPaths :: Text -> Either Text [Text]
parseGeminiBookPaths raw =
  let cleaned = extractJsonArrayText raw
  in case decode (encodeToLbs cleaned) :: Maybe [Text] of
    Just paths -> Right paths
    Nothing    -> Left ("Failed to parse Gemini response as JSON array: " <> raw)
  where
    encodeToLbs :: Text -> LBS.ByteString
    encodeToLbs t = LBS.fromStrict (TE.encodeUtf8 t)

extractJsonArrayText :: Text -> Text
extractJsonArrayText txt =
  let stripped = T.strip txt
      noFences = stripCodeFences stripped
  in case (T.findIndex (== '[') noFences, findLastIndex (== ']') noFences) of
    (Just start, Just end) -> T.take (end - start + 1) (T.drop start noFences)
    _                      -> noFences

stripCodeFences :: Text -> Text
stripCodeFences txt =
  let noStart = fromMaybe txt (T.stripPrefix "```json" txt >>= Just . T.strip)
      noStart' = fromMaybe noStart (T.stripPrefix "```" noStart >>= Just . T.strip)
  in fromMaybe noStart' (T.stripSuffix "```" noStart' >>= Just . T.strip)

findLastIndex :: (Char -> Bool) -> Text -> Maybe Int
findLastIndex predicate txt = go Nothing 0 (T.unpack txt)
  where
    go acc _ [] = acc
    go acc i (c : cs)
      | predicate c = go (Just i) (i + 1) cs
      | otherwise   = go acc (i + 1) cs
