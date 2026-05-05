module Automation.BookReports.Types
  ( BookTitle
  , unBookTitle
  , mkBookTitle
  , BookAuthor
  , unBookAuthor
  , mkBookAuthor
  , BookSlug
  , unBookSlug
  , mkBookSlug
  , slugFromTitle
  , Asin
  , unAsin
  , mkAsin
  , AmazonVariant (..)
  , variantToText
  , variantFromText
  , defaultVariantPriority
  , AmazonResolution (..)
  ) where

import Data.Char (isAlphaNum, isAscii, isUpper)
import Data.Text (Text)
import qualified Data.Text as T

newtype BookTitle = BookTitle { unBookTitle :: Text }
  deriving (Eq, Ord)

instance Show BookTitle where
  show (BookTitle title) = "BookTitle " <> show title

mkBookTitle :: Text -> Either Text BookTitle
mkBookTitle raw
  | T.null trimmed = Left "BookTitle must not be empty or whitespace"
  | otherwise      = Right (BookTitle trimmed)
  where trimmed = T.strip raw

newtype BookAuthor = BookAuthor { unBookAuthor :: Text }
  deriving (Eq, Ord)

instance Show BookAuthor where
  show (BookAuthor author) = "BookAuthor " <> show author

mkBookAuthor :: Text -> Either Text BookAuthor
mkBookAuthor raw
  | T.null trimmed = Left "BookAuthor must not be empty or whitespace"
  | otherwise      = Right (BookAuthor trimmed)
  where trimmed = T.strip raw

newtype BookSlug = BookSlug { unBookSlug :: Text }
  deriving (Eq, Ord)

instance Show BookSlug where
  show (BookSlug slug) = "BookSlug " <> show slug

mkBookSlug :: Text -> Either Text BookSlug
mkBookSlug raw
  | T.null trimmed                       = Left "BookSlug must not be empty"
  | T.any (not . isSlugChar) trimmed =
      Left ("BookSlug must be lowercase ASCII alphanumeric or hyphen, got: " <> trimmed)
  | otherwise                            = Right (BookSlug trimmed)
  where
    trimmed = T.strip raw
    isSlugChar c = (isAscii c && isAlphaNum c && not (isUpper c)) || c == '-'

slugFromTitle :: BookTitle -> BookSlug
slugFromTitle (BookTitle title) =
  BookSlug
    . trimHyphens
    . collapseHyphenRuns
    . T.map normalizeChar
    . T.toLower
    $ title
  where
    normalizeChar character
      | isAscii character && isAlphaNum character = character
      | otherwise                                 = '-'

    collapseHyphenRuns =
      T.pack . squashConsecutiveHyphens . T.unpack
      where
        squashConsecutiveHyphens []         = []
        squashConsecutiveHyphens ('-':rest) = '-' : squashConsecutiveHyphens (dropWhile (== '-') rest)
        squashConsecutiveHyphens (c:rest)   = c   : squashConsecutiveHyphens rest

    trimHyphens =
      T.dropWhile (== '-') . T.dropWhileEnd (== '-')

newtype Asin = Asin { unAsin :: Text }
  deriving (Eq, Ord)

instance Show Asin where
  show (Asin value) = "Asin " <> show value

asinExpectedLength :: Int
asinExpectedLength = 10

mkAsin :: Text -> Either Text Asin
mkAsin raw
  | T.length normalized /= asinExpectedLength =
      Left ("ASIN must be " <> T.pack (show asinExpectedLength) <> " characters, got "
              <> T.pack (show (T.length normalized)) <> ": " <> normalized)
  | T.any (\c -> not (isAscii c && isAlphaNum c)) normalized =
      Left ("ASIN must be ASCII alphanumeric: " <> normalized)
  | otherwise = Right (Asin normalized)
  where
    normalized = T.toUpper (T.strip raw)

data AmazonVariant
  = Hardcover
  | Paperback
  | Kindle
  | Audible
  deriving (Eq, Ord, Show, Enum, Bounded)

variantToText :: AmazonVariant -> Text
variantToText = \case
  Hardcover -> "Hardcover"
  Paperback -> "Paperback"
  Kindle    -> "Kindle"
  Audible   -> "Audible"

variantFromText :: Text -> Maybe AmazonVariant
variantFromText raw =
  case T.toLower (T.strip raw) of
    "hardcover"         -> Just Hardcover
    "hardback"          -> Just Hardcover
    "paperback"         -> Just Paperback
    "softcover"         -> Just Paperback
    "kindle"            -> Just Kindle
    "kindle edition"    -> Just Kindle
    "ebook"             -> Just Kindle
    "audible"           -> Just Audible
    "audiobook"         -> Just Audible
    "audible audiobook" -> Just Audible
    _                   -> Nothing

defaultVariantPriority :: [AmazonVariant]
defaultVariantPriority = [Hardcover, Paperback, Kindle, Audible]

data AmazonResolution = AmazonResolution
  { resolvedAsin    :: Asin
  , resolvedVariant :: AmazonVariant
  } deriving (Eq, Show)
