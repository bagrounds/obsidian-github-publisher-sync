module Automation.SocialPosting.FrontmatterUpdate
  ( updateFrontmatterTimestamp
  , updatePathTimestamps
  , updateFrontmatterUrl
  , upsertFrontmatterField
  ) where

import Control.Monad (when)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Data.Time (defaultTimeLocale, formatTime, getCurrentTime)
import System.Directory (doesFileExist)
import System.FilePath ((</>))

import Automation.Frontmatter (quoteYamlValue)

updateFrontmatterTimestamp :: FilePath -> IO ()
updateFrontmatterTimestamp filePath = do
  exists <- doesFileExist filePath
  when exists $ do
    content <- TIO.readFile filePath
    now <- getCurrentTime
    let timestamp = T.pack $ formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%S" now
        contentLines = T.splitOn "\n" content
    case contentLines of
      (first : rest)
        | T.strip first == "---" ->
            case break (\l -> T.strip l == "---") rest of
              (_, []) -> pure ()
              (frontmatterLines, closingDash : bodyLines) ->
                let updatedFrontmatter = upsertFrontmatterField frontmatterLines "updated" (quoteYamlValue timestamp)
                in TIO.writeFile filePath
                     (T.intercalate "\n" (first : updatedFrontmatter <> [closingDash] <> bodyLines))
      _ -> pure ()

updatePathTimestamps :: FilePath -> [Text] -> IO ()
updatePathTimestamps contentDir =
  mapM_ (\p -> updateFrontmatterTimestamp (contentDir </> T.unpack p))

updateFrontmatterUrl :: FilePath -> Text -> IO ()
updateFrontmatterUrl filePath newUrl = do
  exists <- doesFileExist filePath
  when exists $ do
    content <- TIO.readFile filePath
    let contentLines = T.splitOn "\n" content
    case contentLines of
      (first : rest)
        | T.strip first == "---" ->
            case break (\l -> T.strip l == "---") rest of
              (_, []) -> pure ()
              (frontmatterLines, closingDash : bodyLines) ->
                let updatedFrontmatter = upsertFrontmatterField frontmatterLines "URL" (quoteYamlValue newUrl)
                in TIO.writeFile filePath
                     (T.intercalate "\n" (first : updatedFrontmatter <> [closingDash] <> bodyLines))
      _ -> pure ()

upsertFrontmatterField :: [Text] -> Text -> Text -> [Text]
upsertFrontmatterField contentLines key renderedValue =
  let newLine = key <> ": " <> renderedValue
      keyPattern = key <> ":"
      hasKey = any (T.isPrefixOf keyPattern . T.stripStart) contentLines
      replaced = fmap (\l -> if T.isPrefixOf keyPattern (T.stripStart l) then newLine else l) contentLines
  in if hasKey then replaced else contentLines <> [newLine]
