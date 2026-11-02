module Automation.SocialPosting.FrontmatterUpdate
  ( updateFrontmatterTimestamp
  , updateFrontmatterUrl
  , setUpdatedTimestamp
  , setCanonicalUrl
  , setFrontmatterField
  , upsertFrontmatterField
  ) where

import Control.Monad (when)
import Data.Bool (bool)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Data.Time (UTCTime, defaultTimeLocale, formatTime)
import System.Directory (doesFileExist)

import Automation.Frontmatter (parseFrontmatter, quoteYamlValue)

updateFrontmatterTimestamp :: UTCTime -> FilePath -> IO ()
updateFrontmatterTimestamp now filePath =
  rewriteNoteWhenChanged filePath (setUpdatedTimestamp now)

updateFrontmatterUrl :: FilePath -> Text -> IO ()
updateFrontmatterUrl filePath newUrl =
  rewriteNoteWhenChanged filePath (setCanonicalUrl newUrl)

setUpdatedTimestamp :: UTCTime -> Text -> Text
setUpdatedTimestamp now =
  setFrontmatterField "updated" (quoteYamlValue (T.pack (formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%S" now)))

setCanonicalUrl :: Text -> Text -> Text
setCanonicalUrl newUrl content =
  let (frontmatter, _) = parseFrontmatter content
      alreadyCanonical = fmap T.strip (Map.lookup "URL" frontmatter) == Just newUrl
  in bool (setFrontmatterField "URL" (quoteYamlValue newUrl) content) content alreadyCanonical

rewriteNoteWhenChanged :: FilePath -> (Text -> Text) -> IO ()
rewriteNoteWhenChanged filePath transform = do
  exists <- doesFileExist filePath
  when exists $ do
    content <- TIO.readFile filePath
    let updated = transform content
    when (updated /= content) $
      TIO.writeFile filePath updated

setFrontmatterField :: Text -> Text -> Text -> Text
setFrontmatterField key renderedValue content =
  case T.splitOn "\n" content of
    (first : rest)
      | T.strip first == "---" ->
          case break (\line -> T.strip line == "---") rest of
            (_, []) -> content
            (frontmatterLines, closingDash : bodyLines) ->
              T.intercalate "\n"
                (first : upsertFrontmatterField frontmatterLines key renderedValue <> [closingDash] <> bodyLines)
    _ -> content

upsertFrontmatterField :: [Text] -> Text -> Text -> [Text]
upsertFrontmatterField contentLines key renderedValue =
  let newLine = key <> ": " <> renderedValue
      keyPattern = key <> ":"
      hasKey = any (T.isPrefixOf keyPattern . T.stripStart) contentLines
      replaced = fmap (\line -> if T.isPrefixOf keyPattern (T.stripStart line) then newLine else line) contentLines
  in if hasKey then replaced else contentLines <> [newLine]
