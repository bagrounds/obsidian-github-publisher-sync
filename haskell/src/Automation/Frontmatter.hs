module Automation.Frontmatter
  ( parseFrontmatter
  , YamlValue (..)
  , renderYamlValue
  , quoteYamlValue
  , getReflectionPath
  , readReflection
  , readNote
  ) where

import Data.Char (isAlphaNum, isDigit)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Data.Time (defaultTimeLocale, formatTime, getCurrentTime)
import System.Directory (doesFileExist)
import System.FilePath ((</>), takeBaseName)

import qualified Automation.Platforms.Bluesky as Bluesky
import qualified Automation.Platforms.Mastodon as Mastodon
import qualified Automation.Platforms.Twitter as Twitter
import Automation.Reflection (ReflectionData (..))
import Automation.Title (mkTitle)
import Automation.Url (mkUrl)

parseFrontmatter :: Text -> (Map Text Text, Text)
parseFrontmatter content =
  let contentLines = T.splitOn "\n" content
  in case contentLines of
    (first : rest)
      | T.strip first == "---" ->
          case break (\line -> T.strip line == "---") rest of
            (_, [])              -> (Map.empty, content)
            (frontmatterLines, _ : body) ->
              ( Map.fromList $ concatMap parseLine frontmatterLines
              , T.intercalate "\n" body
              )
    _ -> (Map.empty, content)

parseLine :: Text -> [(Text, Text)]
parseLine line =
  let (key, rest) = T.span (\character -> character == '_' || isAlphaNum character) line
  in case T.uncons rest of
    Just (':', value) | not (T.null key) ->
      [(key, stripQuotes (T.stripStart value))]
    _ -> []

stripQuotes :: Text -> Text
stripQuotes = stripTrailing . stripLeading
  where
    stripLeading text = case T.uncons text of
      Just (character, rest) | character == '"' || character == '\'' -> rest
      _ -> text
    stripTrailing text = case T.unsnoc text of
      Just (init', character) | character == '"' || character == '\'' -> init'
      _ -> text

-- | A typed YAML scalar, mirroring TypeScript's @string | boolean | null@.
--
-- Using a sum type ensures booleans are serialized as native YAML booleans
-- (unquoted) while strings are always double-quoted with proper escaping,
-- following the YAML 1.2 specification.
data YamlValue
  = YamlText Text
  | YamlBool Bool
  deriving (Show, Eq)

renderYamlValue :: YamlValue -> Text
renderYamlValue (YamlBool True)  = "true"
renderYamlValue (YamlBool False) = "false"
renderYamlValue (YamlText t)     = quoteYamlValue t

quoteYamlValue :: Text -> Text
quoteYamlValue value = "\"" <> escapeYamlString value <> "\""

escapeYamlString :: Text -> Text
escapeYamlString = T.concatMap escapeChar
  where
    escapeChar '\\' = "\\\\"
    escapeChar '"'  = "\\\""
    escapeChar '\n' = "\\n"
    escapeChar '\r' = "\\r"
    escapeChar '\t' = "\\t"
    escapeChar '\0' = ""
    escapeChar character    = T.singleton character

hasSectionHeader :: Text -> Text -> Bool
hasSectionHeader content header = T.isInfixOf header content

detectSections :: Text -> (Bool, Bool, Bool)
detectSections content =
  ( hasSectionHeader content Twitter.sectionHeader
  , hasSectionHeader content Bluesky.sectionHeader
  , hasSectionHeader content Mastodon.sectionHeader
  )

getReflectionPath :: Text -> FilePath -> FilePath
getReflectionPath date contentDirectory = contentDirectory </> T.unpack date <> ".md"

isValidDatePrefix :: Text -> Bool
isValidDatePrefix text =
  T.length text >= 10
    && T.index text 4 == '-'
    && T.index text 7 == '-'
    && T.all isDigit (T.take 4 text)
    && T.all isDigit (T.take 2 (T.drop 5 text))
    && T.all isDigit (T.take 2 (T.drop 8 text))

extractDateFromFilename :: Text -> IO Text
extractDateFromFilename filename =
  let prefix = T.take 10 $ T.pack $ takeBaseName $ T.unpack filename
  in if isValidDatePrefix prefix
    then pure prefix
    else T.pack . formatTime defaultTimeLocale "%Y-%m-%d" <$> getCurrentTime

deriveUrl :: Map Text Text -> Text -> Text
deriveUrl frontmatter relativePath =
  let slug = fromMaybe relativePath (T.stripSuffix ".md" relativePath)
  in fromMaybe ("https://bagrounds.org/" <> slug) (Map.lookup "URL" frontmatter)

readReflection :: Text -> FilePath -> IO (Maybe ReflectionData)
readReflection date contentDirectory = do
  let filePath = getReflectionPath date contentDirectory
  exists <- doesFileExist filePath
  if exists
    then do
      content <- TIO.readFile filePath
      let (frontmatter, body) = parseFrontmatter content
          (hasTweet, hasBluesky, hasMastodon) = detectSections content
          titleText = fromMaybe date (Map.lookup "title" frontmatter)
          urlText = fromMaybe ("https://bagrounds.org/reflections/" <> date) (Map.lookup "URL" frontmatter)
          validated = do
            title <- mkTitle titleText
            url <- mkUrl urlText
            pure ReflectionData
              { date = date
              , title = title
              , url = url
              , body = body
              , filePath = T.pack filePath
              , hasTweetSection = hasTweet
              , hasBlueskySection = hasBluesky
              , hasMastodonSection = hasMastodon
              }
      case validated of
        Right reflection -> pure (Just reflection)
        Left reason -> do
          putStrLn $ "  ⚠️  Skipping " <> filePath <> ": " <> T.unpack reason
          pure Nothing
    else pure Nothing

readNote :: Text -> FilePath -> IO (Maybe ReflectionData)
readNote relativePath contentDirectory = do
  let filePath = contentDirectory </> T.unpack relativePath
  exists <- doesFileExist filePath
  if exists
    then do
      content <- TIO.readFile filePath
      let (frontmatter, body) = parseFrontmatter content
          (hasTweet, hasBluesky, hasMastodon) = detectSections content
      date <- extractDateFromFilename relativePath
      let titleText = fromMaybe (T.pack $ takeBaseName $ T.unpack relativePath) (Map.lookup "title" frontmatter)
          urlText = deriveUrl frontmatter relativePath
          validated = do
            title <- mkTitle titleText
            url <- mkUrl urlText
            pure ReflectionData
              { date = date
              , title = title
              , url = url
              , body = body
              , filePath = T.pack filePath
              , hasTweetSection = hasTweet
              , hasBlueskySection = hasBluesky
              , hasMastodonSection = hasMastodon
              }
      case validated of
        Right note -> pure (Just note)
        Left reason -> do
          putStrLn $ "  ⚠️  Skipping " <> filePath <> ": " <> T.unpack reason
          pure Nothing
    else pure Nothing

