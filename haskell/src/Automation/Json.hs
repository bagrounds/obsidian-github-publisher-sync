module Automation.Json
  ( Value (..)
  , FromValue (..)
  , ToValue (..)
  , encode
  , encodeStrict
  , encodeText
  , decode
  , eitherDecode
  , eitherDecodeStrict
  , object
  , (.=)
  , (.:)
  , (.:?)
  , withObject
  , parseMaybe
  ) where

import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import Data.Char (chr, digitToInt)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Text.Lazy as TL
import qualified Data.Text.Lazy.Encoding as TLE
import Numeric (showHex)
import Text.Parsec
  ( ParsecT
  , char
  , count
  , eof
  , hexDigit
  , many
  , many1
  , oneOf
  , option
  , parse
  , satisfy
  , sepBy
  , spaces
  , try
  , (<|>)
  )
import Text.Parsec.Char (digit, string)
import Text.Parsec.Text (Parser)

data Value
  = Object [(Text, Value)]
  | Array [Value]
  | String Text
  | Number Double
  | Bool Bool
  | Null
  deriving (Show, Eq)

class FromValue a where
  fromValue :: Value -> Either String a

class ToValue a where
  toValue :: a -> Value

instance FromValue Value where
  fromValue = Right

instance FromValue Text where
  fromValue (String t) = Right t
  fromValue v = Left $ "Expected string, got: " <> take 50 (show v)

instance FromValue Int where
  fromValue (Number d) = Right (round d)
  fromValue v = Left $ "Expected number, got: " <> take 50 (show v)

instance FromValue Double where
  fromValue (Number d) = Right d
  fromValue v = Left $ "Expected number, got: " <> take 50 (show v)

instance FromValue Bool where
  fromValue (Bool b) = Right b
  fromValue v = Left $ "Expected bool, got: " <> take 50 (show v)

instance FromValue a => FromValue [a] where
  fromValue (Array xs) = traverse fromValue xs
  fromValue v = Left $ "Expected array, got: " <> take 50 (show v)

instance FromValue a => FromValue (Maybe a) where
  fromValue Null = Right Nothing
  fromValue v = Just <$> fromValue v

instance ToValue Value where
  toValue = id

instance ToValue Text where
  toValue = String

instance ToValue Int where
  toValue = Number . fromIntegral

instance ToValue Double where
  toValue = Number

instance ToValue Bool where
  toValue = Bool

instance ToValue a => ToValue [a] where
  toValue = Array . fmap toValue

instance ToValue a => ToValue (Maybe a) where
  toValue Nothing = Null
  toValue (Just a) = toValue a

object :: [(Text, Value)] -> Value
object = Object

(.=) :: ToValue a => Text -> a -> (Text, Value)
(.=) key val = (key, toValue val)
infixr 8 .=

(.:) :: FromValue a => [(Text, Value)] -> Text -> Either String a
(.:) obj key = case lookup key obj of
  Nothing -> Left $ "Key not found: " <> T.unpack key
  Just v  -> fromValue v
infixl 5 .:

(.:?) :: FromValue a => [(Text, Value)] -> Text -> Either String (Maybe a)
(.:?) obj key = case lookup key obj of
  Nothing   -> Right Nothing
  Just Null -> Right Nothing
  Just v    -> Just <$> fromValue v
infixl 5 .:?

withObject :: String -> ([(Text, Value)] -> Either String a) -> Value -> Either String a
withObject _ f (Object obj) = f obj
withObject label _ v = Left $ "Expected object at " <> label <> ", got: " <> take 50 (show v)

parseMaybe :: (Value -> Either String a) -> Value -> Maybe a
parseMaybe f v = case f v of
  Right a -> Just a
  Left _  -> Nothing

encode :: Value -> LBS.ByteString
encode = TLE.encodeUtf8 . TL.fromStrict . encodeText

encodeStrict :: Value -> BS.ByteString
encodeStrict = TE.encodeUtf8 . encodeText

encodeText :: Value -> Text
encodeText = \case
  Null -> "null"
  Bool True -> "true"
  Bool False -> "false"
  Number d
    | isInfinite d || isNaN d -> "null"
    | d == fromInteger (round d) -> T.pack (show (round d :: Integer))
    | otherwise -> T.pack (show d)
  String t -> encodeString t
  Array xs -> "[" <> T.intercalate "," (fmap encodeText xs) <> "]"
  Object kvs -> "{" <> T.intercalate "," (fmap encodePair kvs) <> "}"
  where
    encodePair (k, v) = encodeString k <> ":" <> encodeText v

encodeString :: Text -> Text
encodeString t = "\"" <> T.concatMap escapeChar t <> "\""
  where
    escapeChar '"'  = "\\\""
    escapeChar '\\' = "\\\\"
    escapeChar '\n' = "\\n"
    escapeChar '\r' = "\\r"
    escapeChar '\t' = "\\t"
    escapeChar '\b' = "\\b"
    escapeChar '\f' = "\\f"
    escapeChar c
      | c < '\x20' = "\\u" <> T.justifyRight 4 '0' (T.pack (showHex (fromEnum c) ""))
      | otherwise   = T.singleton c

decode :: FromValue a => LBS.ByteString -> Maybe a
decode bs = case eitherDecode bs of
  Right a -> Just a
  Left _  -> Nothing

eitherDecode :: FromValue a => LBS.ByteString -> Either String a
eitherDecode bs = do
  txt <- case TLE.decodeUtf8' bs of
    Right t  -> Right (TL.toStrict t)
    Left err -> Left $ "UTF-8 decode error: " <> show err
  val <- parseJsonText txt
  fromValue val

eitherDecodeStrict :: FromValue a => BS.ByteString -> Either String a
eitherDecodeStrict bs = do
  txt <- case TE.decodeUtf8' bs of
    Right t  -> Right t
    Left err -> Left $ "UTF-8 decode error: " <> show err
  val <- parseJsonText txt
  fromValue val

parseJsonText :: Text -> Either String Value
parseJsonText txt = case parse (jsonValue <* eof) "json" txt of
  Left err -> Left $ show err
  Right v  -> Right v

jsonValue :: Parser Value
jsonValue = spaces *> jsonValueInner <* spaces

jsonValueInner :: Parser Value
jsonValueInner =
      jsonNull
  <|> jsonBool
  <|> jsonString
  <|> jsonNumber
  <|> jsonArray
  <|> jsonObject

jsonNull :: Parser Value
jsonNull = Null <$ try (string "null")

jsonBool :: Parser Value
jsonBool = (Bool True <$ try (string "true"))
       <|> (Bool False <$ try (string "false"))

jsonNumber :: Parser Value
jsonNumber = do
  sign <- option "" (string "-")
  intPart <- many1 digit
  fracPart <- option "" $ do
    d <- char '.'
    ds <- many1 digit
    pure (d : ds)
  expPart <- option "" $ do
    e <- oneOf "eE"
    s <- option "" (string "+" <|> string "-")
    ds <- many1 digit
    pure (e : s <> ds)
  let numStr = sign <> intPart <> fracPart <> expPart
  case (reads numStr :: [(Double, String)]) of
    [(d, "")] -> pure (Number d)
    _         -> fail $ "Invalid number: " <> numStr

jsonString :: Parser Value
jsonString = String <$> jsonStringLiteral

jsonStringLiteral :: Parser Text
jsonStringLiteral = do
  _ <- char '"'
  cs <- many stringChar
  _ <- char '"'
  pure (T.pack cs)

stringChar :: Parser Char
stringChar = (char '\\' *> escapedChar) <|> satisfy (\c -> c /= '"' && c /= '\\')

escapedChar :: Parser Char
escapedChar =
      ('"'  <$ char '"')
  <|> ('\\' <$ char '\\')
  <|> ('/'  <$ char '/')
  <|> ('\b' <$ char 'b')
  <|> ('\f' <$ char 'f')
  <|> ('\n' <$ char 'n')
  <|> ('\r' <$ char 'r')
  <|> ('\t' <$ char 't')
  <|> unicodeEscape

unicodeEscape :: Parser Char
unicodeEscape = do
  _ <- char 'u'
  hex <- count 4 hexDigit
  let code = foldl (\acc d -> acc * 16 + digitToInt d) 0 hex
  pure (chr code)

jsonArray :: Parser Value
jsonArray = do
  _ <- char '[' <* spaces
  vals <- sepBy (jsonValue <* spaces) (char ',' <* spaces)
  _ <- char ']'
  pure (Array vals)

jsonObject :: Parser Value
jsonObject = do
  _ <- char '{' <* spaces
  pairs <- sepBy keyValuePair (char ',' <* spaces)
  _ <- char '}'
  pure (Object pairs)

keyValuePair :: Parser (Text, Value)
keyValuePair = do
  key <- spaces *> jsonStringLiteral <* spaces
  _ <- char ':' <* spaces
  val <- jsonValue
  pure (key, val)
