module Automation.Frontmatter
  ( parseFrontmatter
  , YamlValue (..)
  , renderYamlValue
  , quoteYamlValue
  , updateFrontmatterFields
  , getReflectionPath
  , readReflection
  , readNote
  ) where

import Control.Monad (when)
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
  let ls = T.splitOn "\n" content
  in case ls of
    (first : rest)
      | T.strip first == "---" ->
          case break (\l -> T.strip l == "---") rest of
            (_, [])              -> (Map.empty, content)
            (fmLines, _ : body) ->
              ( Map.fromList $ concatMap parseLine fmLines
              , T.intercalate "\n" body
              )
    _ -> (Map.empty, content)

parseLine :: Text -> [(Text, Text)]
parseLine line =
  let (key, rest) = T.span (\c -> c == '_' || isAlphaNum c) line
  in case T.uncons rest of
    Just (':', value) | not (T.null key) ->
      [(key, stripQuotes (T.stripStart value))]
    _ -> []

stripQuotes :: Text -> Text
stripQuotes = stripTrailing . stripLeading
  where
    stripLeading t = case T.uncons t of
      Just (c, rest) | c == '"' || c == '\'' -> rest
      _ -> t
    stripTrailing t = case T.unsnoc t of
      Just (init', c) | c == '"' || c == '\'' -> init'
      _ -> t

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
quoteYamlValue v = "\"" <> escapeYamlString v <> "\""

escapeYamlString :: Text -> Text
escapeYamlString = T.concatMap escapeChar
  where
    escapeChar '\\' = "\\\\"
    escapeChar '"'  = "\\\""
    escapeChar '\n' = "\\n"
    escapeChar '\r' = "\\r"
    escapeChar '\t' = "\\t"
    escapeChar '\0' = ""
    escapeChar c    = T.singleton c

hasSectionHeader :: Text -> Text -> Bool
hasSectionHeader content header = T.isInfixOf header content

detectSections :: Text -> (Bool, Bool, Bool)
detectSections content =
  ( hasSectionHeader content Twitter.sectionHeader
  , hasSectionHeader content Bluesky.sectionHeader
  , hasSectionHeader content Mastodon.sectionHeader
  )

getReflectionPath :: Text -> FilePath -> FilePath
getReflectionPath date contentDir = contentDir </> T.unpack date <> ".md"

isValidDatePrefix :: Text -> Bool
isValidDatePrefix t =
  T.length t >= 10
    && T.index t 4 == '-'
    && T.index t 7 == '-'
    && T.all isDigit (T.take 4 t)
    && T.all isDigit (T.take 2 (T.drop 5 t))
    && T.all isDigit (T.take 2 (T.drop 8 t))

extractDateFromFilename :: Text -> IO Text
extractDateFromFilename filename =
  let prefix = T.take 10 $ T.pack $ takeBaseName $ T.unpack filename
  in if isValidDatePrefix prefix
    then pure prefix
    else T.pack . formatTime defaultTimeLocale "%Y-%m-%d" <$> getCurrentTime

deriveUrl :: Map Text Text -> Text -> Text
deriveUrl fm relativePath =
  let slug = fromMaybe relativePath (T.stripSuffix ".md" relativePath)
  in fromMaybe ("https://bagrounds.org/" <> slug) (Map.lookup "URL" fm)

readReflection :: Text -> FilePath -> IO (Maybe ReflectionData)
readReflection date contentDir = do
  let filePath = getReflectionPath date contentDir
  exists <- doesFileExist filePath
  if exists
    then do
      content <- TIO.readFile filePath
      let (fm, body) = parseFrontmatter content
          (hasTweet, hasBluesky, hasMastodon) = detectSections content
          titleText = fromMaybe date (Map.lookup "title" fm)
          urlText = fromMaybe ("https://bagrounds.org/reflections/" <> date) (Map.lookup "URL" fm)
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
readNote relativePath contentDir = do
  let filePath = contentDir </> T.unpack relativePath
  exists <- doesFileExist filePath
  if exists
    then do
      content <- TIO.readFile filePath
      let (fm, body) = parseFrontmatter content
          (hasTweet, hasBluesky, hasMastodon) = detectSections content
      date <- extractDateFromFilename relativePath
      let titleText = fromMaybe (T.pack $ takeBaseName $ T.unpack relativePath) (Map.lookup "title" fm)
          urlText = deriveUrl fm relativePath
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

-- | Update or insert frontmatter fields in a file. Preserves all existing
-- fields not listed in the update, and adds new fields that don't exist yet.
-- If a field's value is empty string, the field is set to an empty string
-- rather than removed.
updateFrontmatterFields :: FilePath -> [(Text, YamlValue)] -> IO ()
updateFrontmatterFields filePath fields = do
  exists <- doesFileExist filePath
  when exists $ do
    raw <- TIO.readFile filePath
    let ls = T.splitOn "\n" raw
    case ls of
      (first : rest)
        | T.strip first == "---" ->
            case break (\l -> T.strip l == "---") rest of
              (_, []) -> pure ()
              (fmLines, closingDash : bodyLines) ->
                let updatedFm = foldl upsertField fmLines fields
                in TIO.writeFile filePath
                     (T.intercalate "\n" (first : updatedFm <> [closingDash] <> bodyLines))
      _ -> do
        let entries = T.intercalate "\n" $ fmap (\(k, v) -> k <> ": " <> renderYamlValue v) fields
        TIO.writeFile filePath ("---\n" <> entries <> "\n---\n" <> raw)

upsertField :: [Text] -> (Text, YamlValue) -> [Text]
upsertField ls (key, val) =
  let newLine    = key <> ": " <> renderYamlValue val
      keyPrefix  = key <> ":"
      didReplace = any (T.isPrefixOf keyPrefix . T.stripStart) ls
      replaced   = replaceFieldLine keyPrefix newLine ls
  in if didReplace then replaced else ls <> [newLine]

replaceFieldLine :: Text -> Text -> [Text] -> [Text]
replaceFieldLine _ _ [] = []
replaceFieldLine keyPrefix newLine (l : rest)
  | keyPrefix `T.isPrefixOf` T.stripStart l =
      newLine : dropContinuationLines rest
  | otherwise = l : replaceFieldLine keyPrefix newLine rest

dropContinuationLines :: [Text] -> [Text]
dropContinuationLines [] = []
dropContinuationLines (l : rest)
  | not (T.null l) && T.isPrefixOf " " l = dropContinuationLines rest
  | otherwise                             = l : rest


