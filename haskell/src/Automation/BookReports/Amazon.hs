module Automation.BookReports.Amazon
  ( AmazonAffiliateUrl
  , unAmazonAffiliateUrl
  , buildAffiliateUrlFromAsin
  , buildAmazonResolutionPrompt
  , parseAmazonResolutionResponse
  , extractAsinFromUrl
  , AffiliateTag
  , unAffiliateTag
  , mkAffiliateTag
  ) where

import Data.Char (isAlphaNum, isAscii)
import Data.List (find)
import qualified Data.Maybe
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE

import Automation.Json (Value (..))
import qualified Automation.Json as Json
import Automation.BookReports.Types
  ( AmazonResolution (..)
  , AmazonVariant
  , Asin
  , BookTitle
  , mkAsin
  , unAsin
  , unBookTitle
  , variantFromText
  , variantToText
  )

newtype AffiliateTag = AffiliateTag { unAffiliateTag :: Text }
  deriving (Eq, Ord)

instance Show AffiliateTag where
  show (AffiliateTag tag) = "AffiliateTag " <> show tag

mkAffiliateTag :: Text -> Either Text AffiliateTag
mkAffiliateTag raw
  | T.null trimmed                          = Left "AffiliateTag must not be empty"
  | T.any (not . isTagChar) trimmed =
      Left ("AffiliateTag must be ASCII alphanumeric or hyphen: " <> trimmed)
  | otherwise = Right (AffiliateTag trimmed)
  where
    trimmed = T.strip raw
    isTagChar c = (isAscii c && isAlphaNum c) || c == '-'

newtype AmazonAffiliateUrl = AmazonAffiliateUrl { unAmazonAffiliateUrl :: Text }
  deriving (Eq, Ord, Show)

amazonProductDomain :: Text
amazonProductDomain = "https://www.amazon.com"

buildAffiliateUrlFromAsin :: AffiliateTag -> Asin -> AmazonAffiliateUrl
buildAffiliateUrlFromAsin tag asinValue =
  AmazonAffiliateUrl
    ( amazonProductDomain
        <> "/dp/"
        <> unAsin asinValue
        <> "?tag="
        <> unAffiliateTag tag
    )

extractAsinFromUrl :: Text -> Maybe Asin
extractAsinFromUrl rawUrl =
  let pieces      = concatMap (T.splitOn "/") (T.splitOn "?" (T.strip rawUrl))
      asinMarkers = ["dp", "gp", "product"]
      candidates  = mapMaybe (asinFollowingMarker pieces) asinMarkers
  in case candidates of
       []        -> Nothing
       (found:_) -> Just found
  where
    asinFollowingMarker segments marker =
      case dropWhile (\segment -> T.toLower segment /= marker) segments of
        (_ : candidate : _) -> rightToMaybe (mkAsin candidate)
        _                   -> Nothing

buildAmazonResolutionPrompt :: BookTitle -> [AmazonVariant] -> Text
buildAmazonResolutionPrompt title variantPriority =
  T.unlines
    [ "Find the canonical Amazon.com product page for the book titled below."
    , "Return EXACTLY one JSON object on a single line, no markdown, no commentary, with these fields:"
    , "  found:   true | false"
    , "  asin:    the 10-character ASIN (only when found is true)"
    , "  variant: one of " <> T.intercalate ", " (fmap variantToText variantPriority) <> " (only when found is true)"
    , "  url:     the canonical https://www.amazon.com/... URL (only when found is true)"
    , "Choose the variant earliest in this priority order that is currently in print:"
    , "  " <> T.intercalate " > " (fmap variantToText variantPriority)
    , "If you cannot confidently identify the canonical Amazon page, return {\"found\":false}."
    , ""
    , "Title: " <> unBookTitle title
    ]

parseAmazonResolutionResponse :: [AmazonVariant] -> Text -> Either Text AmazonResolution
parseAmazonResolutionResponse variantPriority rawResponse =
  let normalized = extractFirstJsonObject rawResponse
  in case Json.eitherDecodeStrict (TE.encodeUtf8 normalized) of
       Left parseError ->
         Left ("Amazon resolution response was not valid JSON ("
                 <> T.pack parseError <> "): " <> normalized)
       Right value -> interpretObject value
  where
    interpretObject (Object fields) =
      case lookup "found" fields of
        Just (Bool False) -> Left "Amazon resolver returned found:false"
        Just (Bool True)  -> resolveAsinAndVariant fields
        _                 -> Left "Amazon resolution response missing 'found' boolean"
    interpretObject _ = Left "Amazon resolution response was not a JSON object"

    resolveAsinAndVariant fields = do
      asinText    <- lookupString "asin" fields
      asinValue   <- mkAsin asinText
      variantText <- lookupString "variant" fields
      variant     <- maybeToEither
                       ("Unrecognized variant: " <> variantText)
                       (variantFromText variantText)
      _           <- enforceVariantInPriority variantPriority variant
      pure AmazonResolution { resolvedAsin = asinValue, resolvedVariant = variant }

enforceVariantInPriority :: [AmazonVariant] -> AmazonVariant -> Either Text ()
enforceVariantInPriority variantPriority variant =
  case find (== variant) variantPriority of
    Just _  -> Right ()
    Nothing ->
      Left ("Variant " <> variantToText variant
              <> " is not in configured priority list: "
              <> T.intercalate ", " (fmap variantToText variantPriority))

lookupString :: Text -> [(Text, Value)] -> Either Text Text
lookupString key fields =
  case lookup key fields of
    Just (String value) -> Right value
    Just _              -> Left ("Field '" <> key <> "' is not a string")
    Nothing             -> Left ("Field '" <> key <> "' is missing")

extractFirstJsonObject :: Text -> Text
extractFirstJsonObject raw =
  let withoutFences = stripCodeFences raw
      afterOpen     = T.dropWhile (/= '{') withoutFences
  in takeUpToClosingBrace afterOpen

stripCodeFences :: Text -> Text
stripCodeFences raw =
  let trimmedStart = T.stripStart raw
      withoutLeadingFence =
        case T.stripPrefix "```json" trimmedStart of
          Just afterFence -> afterFence
          Nothing         -> Data.Maybe.fromMaybe raw (T.stripPrefix "```" trimmedStart)
      trimmedEnd = T.stripEnd withoutLeadingFence
  in Data.Maybe.fromMaybe trimmedEnd (T.stripSuffix "```" trimmedEnd)

takeUpToClosingBrace :: Text -> Text
takeUpToClosingBrace raw =
  let (prefix, suffix) = T.breakOn "}" raw
  in if T.null suffix then raw else prefix <> "}"

rightToMaybe :: Either e a -> Maybe a
rightToMaybe = either (const Nothing) Just

maybeToEither :: e -> Maybe a -> Either e a
maybeToEither leftValue = maybe (Left leftValue) Right
