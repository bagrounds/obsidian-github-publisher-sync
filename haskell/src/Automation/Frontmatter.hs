module Automation.Frontmatter
  ( parseFrontmatter
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

import Automation.Types
  ( ReflectionData (..)
  , blueskySectionHeader
  , mastodonSectionHeader
  , tweetSectionHeader
  )

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

hasSectionHeader :: Text -> Text -> Bool
hasSectionHeader content header = T.isInfixOf header content

detectSections :: Text -> (Bool, Bool, Bool)
detectSections content =
  ( hasSectionHeader content tweetSectionHeader
  , hasSectionHeader content blueskySectionHeader
  , hasSectionHeader content mastodonSectionHeader
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
  in case isValidDatePrefix prefix of
    True  -> pure prefix
    False -> T.pack . formatTime defaultTimeLocale "%Y-%m-%d" <$> getCurrentTime

deriveUrl :: Map Text Text -> Text -> Text
deriveUrl fm relativePath =
  let slug = fromMaybe relativePath (T.stripSuffix ".md" relativePath)
  in fromMaybe ("https://bagrounds.org/" <> slug) (Map.lookup "URL" fm)

readReflection :: Text -> FilePath -> IO (Maybe ReflectionData)
readReflection date contentDir = do
  let filePath = getReflectionPath date contentDir
  exists <- doesFileExist filePath
  case exists of
    False -> pure Nothing
    True  -> do
      content <- TIO.readFile filePath
      let (fm, body) = parseFrontmatter content
          sections = detectSections content
          (hasTweet, hasBluesky, hasMastodon) = sections
      pure $ Just ReflectionData
        { rdDate = date
        , rdTitle = fromMaybe date (Map.lookup "title" fm)
        , rdUrl = fromMaybe ("https://bagrounds.org/reflections/" <> date) (Map.lookup "URL" fm)
        , rdBody = body
        , rdFilePath = T.pack filePath
        , rdHasTweetSection = hasTweet
        , rdHasBlueskySection = hasBluesky
        , rdHasMastodonSection = hasMastodon
        }

readNote :: Text -> FilePath -> IO (Maybe ReflectionData)
readNote relativePath contentDir = do
  let filePath = contentDir </> T.unpack relativePath
  exists <- doesFileExist filePath
  case exists of
    False -> pure Nothing
    True  -> do
      content <- TIO.readFile filePath
      let (fm, body) = parseFrontmatter content
          (hasTweet, hasBluesky, hasMastodon) = detectSections content
      date <- extractDateFromFilename relativePath
      pure $ Just ReflectionData
        { rdDate = date
        , rdTitle = fromMaybe (T.pack $ takeBaseName $ T.unpack relativePath) (Map.lookup "title" fm)
        , rdUrl = deriveUrl fm relativePath
        , rdBody = body
        , rdFilePath = T.pack filePath
        , rdHasTweetSection = hasTweet
        , rdHasBlueskySection = hasBluesky
        , rdHasMastodonSection = hasMastodon
        }
