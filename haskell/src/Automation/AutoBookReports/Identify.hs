{-# LANGUAGE OverloadedStrings #-}

-- | Identification of book references not yet present in the vault.
--
-- Pure logic for building the prompt and parsing the Gemini response. The IO
-- side of the call (HTTP, retry) is in the orchestrator.
module Automation.AutoBookReports.Identify
  ( BookCandidate (..)
  , buildIdentificationPrompt
  , parseIdentificationResponse
  ) where

import Data.Maybe (fromMaybe, mapMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.ByteString.Lazy as LBS

import Automation.Json (Value (..), decode)
import Automation.Text (stripCodeFences)

-- | A book that the identifier has flagged as referenced in recent content
-- but missing from the existing book index.
--
-- Author is stored separately so we can disambiguate (many books share
-- titles) and so we can pass it to the Amazon resolver.
data BookCandidate = BookCandidate
  { candidateTitle  :: Text
  , candidateAuthor :: Text
  , candidateContext :: Text -- ^ A short snippet of the surrounding prose for debugging.
  } deriving (Show, Eq)

-- | Build the system + user prompt asking Gemini to extract genuinely
-- referenced books that we do not already have a page for.
--
-- The prompt is written to be conservative — when in doubt, omit the book.
buildIdentificationPrompt
  :: [Text]   -- ^ Slugs of existing book pages (e.g. @["deep-work", "thinking-fast-and-slow"]@).
  -> [Text]   -- ^ Body text of recent reflections.
  -> (Text, Text) -- ^ (systemInstruction, userPrompt)
buildIdentificationPrompt knownSlugs reflectionBodies =
  let knownSection = case knownSlugs of
        [] -> "(none)"
        _  -> T.intercalate "\n" (fmap ("- " <>) knownSlugs)
      reflectionSection = case reflectionBodies of
        [] -> "(no recent reflections)"
        _  -> T.intercalate "\n\n---\n\n" reflectionBodies
      systemInstruction = T.intercalate "\n"
        [ "You are a careful editorial assistant maintaining a personal knowledge base of book reports."
        , ""
        , "You will receive:"
        , "1. A list of slugs for books that already have a dedicated page in the knowledge base."
        , "2. The body text of several recent journal reflections."
        , ""
        , "Your task: Identify books that are *genuinely referenced* in the reflections but do *not* yet have a corresponding slug."
        , ""
        , "Rules:"
        , "- Only include real, published books — not articles, podcasts, videos, films, or songs."
        , "- The reference must be unambiguous; the text must clearly discuss, quote, recommend, or cite the book as a literary work."
        , "- Do NOT include a book if its title only appears as a generic phrase (e.g. \"deep work\" used as a regular noun phrase)."
        , "- Do NOT include a book whose slug is already in the known list. Compare slugs by lower-casing the title and replacing non-alphanumeric runs with hyphens."
        , "- For each book, return its canonical full title and primary author (one author, the most recognized one)."
        , "- Prefer fewer, higher-confidence picks over many uncertain ones."
        , "- If unsure, return an empty list."
        , ""
        , "Respond with ONLY a JSON array of objects with exactly these keys: title, author, context."
        , "- title: canonical full title of the book"
        , "- author: primary author's full name"
        , "- context: a verbatim ~120-char excerpt from the reflection that mentions the book"
        , ""
        , "Example: [{\"title\":\"Foo Bar\",\"author\":\"Baz Qux\",\"context\":\"...as Baz Qux argues in Foo Bar, the only path is...\"}]"
        , "If no genuine new book references exist, return: []"
        , "No prose, no markdown, no code fences."
        ]
      userPrompt = T.intercalate "\n"
        [ "Existing book slugs:"
        , knownSection
        , ""
        , "Recent reflections:"
        , reflectionSection
        ]
  in (systemInstruction, userPrompt)

-- | Parse a Gemini response into a list of 'BookCandidate's.
--
-- Tolerates code-fenced JSON and trailing prose. Returns an empty list when
-- the response is not parseable as a JSON array — the caller logs the raw
-- response for debugging.
parseIdentificationResponse :: Text -> Either Text [BookCandidate]
parseIdentificationResponse raw =
  let cleaned = extractJsonArrayText raw
  in case decode (toLbs cleaned) :: Maybe Value of
    Just (Array items) -> Right (mapMaybe parseCandidate items)
    Just _             -> Left ("Identification response was valid JSON but not an array: " <> raw)
    Nothing            -> Left ("Could not parse identification response as JSON: " <> raw)
  where
    toLbs t = LBS.fromStrict (TE.encodeUtf8 t)

parseCandidate :: Value -> Maybe BookCandidate
parseCandidate (Object fields) = do
  title <- lookupString "title" fields
  author <- lookupString "author" fields
  let context = fromMaybe "" (lookupString "context" fields)
  if T.null (T.strip title) || T.null (T.strip author)
    then Nothing
    else Just BookCandidate
      { candidateTitle = T.strip title
      , candidateAuthor = T.strip author
      , candidateContext = T.strip context
      }
parseCandidate _ = Nothing

lookupString :: Text -> [(Text, Value)] -> Maybe Text
lookupString key fields =
  case lookup key fields of
    Just (String s) -> Just s
    _               -> Nothing

extractJsonArrayText :: Text -> Text
extractJsonArrayText txt =
  let stripped = T.strip (stripCodeFences txt)
  in case (T.findIndex (== '[') stripped, findLastIndex (== ']') stripped) of
    (Just start, Just end) | end >= start -> T.take (end - start + 1) (T.drop start stripped)
    _                                     -> stripped

findLastIndex :: (Char -> Bool) -> Text -> Maybe Int
findLastIndex predicate txt =
  let indexed = zip [0 :: Int ..] (T.unpack txt)
      matched = [i | (i, c) <- indexed, predicate c]
  in case matched of
    [] -> Nothing
    is -> Just (last is)
