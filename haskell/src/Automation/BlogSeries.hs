module Automation.BlogSeries
  ( buildBlogContext
  , generateSeriesIndex
  , extractSlug
  , parseGeneratedPost
  , appendModelSignature
  , updatePreviousPost
  ) where

import Data.Char (isDigit)
import Data.List (find)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Directory (doesFileExist)
import System.FilePath ((</>))

import Automation.BlogComments (BlogComment)
import Automation.BlogPosts (BlogPost (..), readAgentsMd, readSeriesPosts)
import Automation.BlogPrompt
  ( BlogContext (..)
  , buildForwardLink
  , filterCommentsAfterLastPost
  , quoteForYaml
  )
import Automation.BlogSeriesConfig (BlogSeriesConfig (..), lookupSeries)

buildBlogContext :: Text -> FilePath -> [BlogComment] -> Text -> IO BlogContext
buildBlogContext seriesId seriesDir comments today = do
  let series = either (error . T.unpack) id (lookupSeries seriesId)
  posts <- readSeriesPosts seriesDir
  agentsMd <- readAgentsMd seriesDir
  let filteredComments = filterCommentsAfterLastPost series posts comments
  pure BlogContext
    { bcxSeries        = series
    , bcxAgentsMd      = agentsMd
    , bcxPreviousPosts = posts
    , bcxComments      = filteredComments
    , bcxToday         = today
    }

generateSeriesIndex :: BlogSeriesConfig -> [BlogPost] -> Text
generateSeriesIndex series _posts =
  T.intercalate "\n"
    [ "---"
    , "share: true"
    , "title: " <> quoteForYaml (bscIcon series <> " " <> bscName series)
    , "---"
    , ""
    , bscNavLink series
    , ""
    , "```dataview"
    , "TABLE WITHOUT ID"
    , "  file.link AS \"Post\","
    , "  title AS \"Title\","
    , "  date AS \"Date\""
    , "FROM \"" <> bscId series <> "\""
    , "WHERE file.name != \"index\""
    , "SORT date DESC"
    , "```"
    ]

extractSlug :: Text -> Text
extractSlug filename =
  let withoutMd = fromMaybe filename (T.stripSuffix ".md" filename)
  in stripDatePrefix withoutMd

parseGeneratedPost :: Text -> Maybe (Text, Text)
parseGeneratedPost raw =
  let trimmed = T.strip raw
  in case T.length trimmed < 200 of
    True  -> Nothing
    False ->
      case find isHeading (T.lines trimmed) of
        Nothing -> Nothing
        Just h  -> Just (trimmed, extractHeadingText h)

appendModelSignature :: Text -> Text -> Text
appendModelSignature body model = body <> "\n\n✍️ Written by " <> model

updatePreviousPost :: FilePath -> BlogPost -> BlogSeriesConfig -> Text -> IO ()
updatePreviousPost seriesDir prevPost series newFilename = do
  let filePath = seriesDir </> T.unpack (bpFilename prevPost)
  exists <- doesFileExist filePath
  case exists of
    False -> pure ()
    True  -> do
      content <- TIO.readFile filePath
      let fwdLink = buildForwardLink series newFilename
          navPrefix = bscNavLink series
          ls = T.splitOn "\n" content
          updatedLines = fmap (updateNavLine navPrefix fwdLink) ls
          updated = T.intercalate "\n" updatedLines
      case updated == content of
        True  -> pure ()
        False -> TIO.writeFile filePath updated

stripDatePrefix :: Text -> Text
stripDatePrefix t
  | T.length t >= 10 && isDatePrefix (T.take 10 t) =
      case T.uncons (T.drop 10 t) of
        Just ('-', rest) -> rest
        _                -> T.drop 10 t
  | otherwise = t

isDatePrefix :: Text -> Bool
isDatePrefix t =
  T.all isDigit (T.take 4 t)
    && T.index t 4 == '-'
    && T.all isDigit (T.take 2 (T.drop 5 t))
    && T.index t 7 == '-'
    && T.all isDigit (T.take 2 (T.drop 8 t))

isHeading :: Text -> Bool
isHeading line =
  let stripped = T.stripStart line
  in T.isPrefixOf "## " stripped || T.isPrefixOf "# " stripped

extractHeadingText :: Text -> Text
extractHeadingText line =
  let stripped = T.stripStart line
  in case T.stripPrefix "## " stripped of
    Just title -> T.strip title
    Nothing    -> case T.stripPrefix "# " stripped of
      Just title -> T.strip title
      Nothing    -> T.strip stripped

updateNavLine :: Text -> Text -> Text -> Text
updateNavLine navPrefix fwdLink line
  | T.isPrefixOf navPrefix line =
      let cleaned = removeExistingForward line
      in T.stripEnd cleaned <> " " <> fwdLink
  | otherwise = line

removeExistingForward :: Text -> Text
removeExistingForward line =
  case T.breakOn "|⏭️]]" line of
    (_, "") -> line
    (before, after) ->
      let afterLink = T.drop (T.length "|⏭️]]") after
      in case T.breakOnEnd "[[" before of
          ("", _) -> line
          (prefix, _) -> T.dropEnd 2 prefix <> afterLink
