{-# LANGUAGE OverloadedStrings #-}

-- | Amazon ASIN/variant resolution and affiliate URL formatting.
--
-- Pure logic for:
--   * the variant priority order (which edition we prefer to link to)
--   * formatting the affiliate URL given an ASIN and associates tag
--   * validating an ASIN
--   * building the Gemini lookup prompt
--   * parsing the Gemini lookup response
--
-- The actual Gemini call is in the orchestrator. This module is fully pure so
-- it is trivially testable.
module Automation.AutoBookReports.AmazonLink
  ( AmazonVariant (..)
  , AmazonResolution (..)
  , defaultVariantPriority
  , variantToText
  , variantFromText
  , isValidAsin
  , formatAffiliateUrl
  , buildLookupPrompt
  , parseLookupResponse
  ) where

import Data.Char (isAlphaNum, isAscii)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.ByteString.Lazy as LBS

import Automation.Json (Value (..), decode)
import Automation.Text (stripCodeFences)

-- | The Amazon edition we want to link to. Order of constructors is the
-- preference order — see 'defaultVariantPriority'.
data AmazonVariant
  = Hardcover
  | Paperback
  | Kindle
  | Audible
  deriving (Show, Eq, Ord, Enum, Bounded)

-- | Variant preference order. Earlier entries are preferred.
--
-- Hardcover and paperback are the canonical print editions; Kindle and
-- Audible are functional fallbacks. To change preferences, edit this
-- function — every consumer reads the order from here.
defaultVariantPriority :: [AmazonVariant]
defaultVariantPriority = [Hardcover, Paperback, Kindle, Audible]

variantToText :: AmazonVariant -> Text
variantToText Hardcover = "Hardcover"
variantToText Paperback = "Paperback"
variantToText Kindle    = "Kindle"
variantToText Audible   = "Audible"

variantFromText :: Text -> Maybe AmazonVariant
variantFromText t =
  let normalized = T.toLower (T.strip t)
  in case normalized of
    "hardcover"     -> Just Hardcover
    "hardback"      -> Just Hardcover
    "paperback"     -> Just Paperback
    "softcover"     -> Just Paperback
    "trade paperback" -> Just Paperback
    "mass market paperback" -> Just Paperback
    "kindle"        -> Just Kindle
    "kindle edition" -> Just Kindle
    "ebook"         -> Just Kindle
    "e-book"        -> Just Kindle
    "audible"       -> Just Audible
    "audiobook"     -> Just Audible
    "audible audiobook" -> Just Audible
    "audio"         -> Just Audible
    _               -> Nothing

-- | The result of a successful Amazon lookup: a single variant of a single
-- book with its ASIN.
data AmazonResolution = AmazonResolution
  { resolvedAsin    :: Text
  , resolvedVariant :: AmazonVariant
  } deriving (Show, Eq)

-- | True for strings that look like a valid Amazon ASIN: exactly 10
-- alphanumeric ASCII characters. Real ASINs follow either ISBN-10 (digits +
-- optional X) or @B[0-9A-Z]{9}@; this regex is liberal but sufficient to
-- reject obvious garbage.
isValidAsin :: Text -> Bool
isValidAsin t =
  T.length t == 10 && T.all (\c -> isAscii c && isAlphaNum c) t

-- | Build the affiliate URL for an ASIN, given the user's associates tag.
--
-- Example:
--
-- > formatAffiliateUrl "B08L5W3W7Y" "bryangrounds-20"
-- > == "https://www.amazon.com/dp/B08L5W3W7Y?tag=bryangrounds-20"
formatAffiliateUrl :: Text -> Text -> Text
formatAffiliateUrl asinValue tag =
  "https://www.amazon.com/dp/" <> T.toUpper asinValue <> "?tag=" <> tag

-- | Build the prompt for Gemini's grounded lookup of the Amazon ASIN.
--
-- We ask for a strict JSON shape so the response is parseable. The variant
-- priority is embedded so Gemini knows which edition to prefer.
buildLookupPrompt
  :: Text   -- ^ Title
  -> Text   -- ^ Author
  -> [AmazonVariant] -- ^ Priority order (head = most preferred)
  -> (Text, Text)
buildLookupPrompt title author priority =
  let priorityList = T.intercalate ", " (fmap variantToText priority)
      systemInstruction = T.intercalate "\n"
        [ "You are an Amazon catalog lookup assistant. You have access to web search."
        , ""
        , "Given a book title and author, find the canonical Amazon US product page for that book and return its ASIN and edition (variant)."
        , ""
        , "Variant preference order (use the first one available): " <> priorityList
        , ""
        , "Rules:"
        , "- The ASIN is exactly 10 alphanumeric ASCII characters, found in the Amazon product URL after /dp/ or /gp/product/."
        , "- Verify the product page is for the SAME book (matching title AND author). Different books often share titles."
        , "- If you cannot confidently identify the right book, return {\"found\":false}."
        , "- Prefer Amazon US (amazon.com) over other locales."
        , "- Do NOT guess. If web search returns ambiguous results, say not found."
        , ""
        , "Respond with ONLY a single JSON object. No prose, no markdown, no code fences."
        , "Schema when found: {\"found\":true,\"asin\":\"XXXXXXXXXX\",\"variant\":\"Hardcover\"}"
        , "Schema when not found: {\"found\":false}"
        ]
      userPrompt = "Title: " <> title <> "\nAuthor: " <> author
  in (systemInstruction, userPrompt)

-- | Parse a Gemini lookup response into an 'AmazonResolution'.
--
-- Returns @Left reason@ when the book was not found, the response was not
-- parseable, or the ASIN failed validation.
parseLookupResponse :: Text -> Either Text AmazonResolution
parseLookupResponse raw =
  let cleaned = extractJsonObjectText raw
  in case decode (toLbs cleaned) :: Maybe Value of
    Just (Object fields) -> resolveFields fields
    Just _               -> Left ("Lookup response was valid JSON but not an object: " <> raw)
    Nothing              -> Left ("Could not parse lookup response as JSON: " <> raw)
  where
    toLbs t = LBS.fromStrict (TE.encodeUtf8 t)

resolveFields :: [(Text, Value)] -> Either Text AmazonResolution
resolveFields fields =
  case lookupBool "found" fields of
    Just False -> Left "Resolver reported book not found"
    _          -> do
      asinRaw <- maybe (Left "Missing 'asin' field in lookup response") Right (lookupString "asin" fields)
      let trimmedAsin = T.strip asinRaw
      _ <- if isValidAsin trimmedAsin
            then Right ()
            else Left ("Invalid ASIN in lookup response: " <> trimmedAsin)
      variantText <- maybe (Left "Missing 'variant' field in lookup response") Right (lookupString "variant" fields)
      variant <- maybe (Left ("Unknown variant: " <> variantText)) Right (variantFromText variantText)
      Right AmazonResolution { resolvedAsin = T.toUpper trimmedAsin, resolvedVariant = variant }

lookupString :: Text -> [(Text, Value)] -> Maybe Text
lookupString key fields = case lookup key fields of
  Just (String s) -> Just s
  _               -> Nothing

lookupBool :: Text -> [(Text, Value)] -> Maybe Bool
lookupBool key fields = case lookup key fields of
  Just (Bool b) -> Just b
  _             -> Nothing

extractJsonObjectText :: Text -> Text
extractJsonObjectText txt =
  let stripped = T.strip (stripCodeFences txt)
  in case (T.findIndex (== '{') stripped, findLastIndex (== '}') stripped) of
    (Just start, Just end) | end >= start -> T.take (end - start + 1) (T.drop start stripped)
    _                                     -> stripped

findLastIndex :: (Char -> Bool) -> Text -> Maybe Int
findLastIndex predicate txt =
  let indexed = zip [0 :: Int ..] (T.unpack txt)
      matched = [i | (i, c) <- indexed, predicate c]
  in case matched of
    [] -> Nothing
    is -> Just (last is)
