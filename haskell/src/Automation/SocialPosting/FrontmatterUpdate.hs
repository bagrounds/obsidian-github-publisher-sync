module Automation.SocialPosting.FrontmatterUpdate
  ( updateFrontmatterTimestamp
  , updatePathTimestamps
  , updateFrontmatterUrl
  , upsertFmField
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
        ls = T.splitOn "\n" content
    case ls of
      (first : rest)
        | T.strip first == "---" ->
            case break (\l -> T.strip l == "---") rest of
              (_, []) -> pure ()
              (fmLines, closingDash : bodyLines) ->
                let updatedFm = upsertFmField fmLines "updated" (quoteYamlValue timestamp)
                in TIO.writeFile filePath
                     (T.intercalate "\n" (first : updatedFm <> [closingDash] <> bodyLines))
      _ -> pure ()

updatePathTimestamps :: FilePath -> [Text] -> IO ()
updatePathTimestamps contentDir =
  mapM_ (\p -> updateFrontmatterTimestamp (contentDir </> T.unpack p))

updateFrontmatterUrl :: FilePath -> Text -> IO ()
updateFrontmatterUrl filePath newUrl = do
  exists <- doesFileExist filePath
  when exists $ do
    content <- TIO.readFile filePath
    let ls = T.splitOn "\n" content
    case ls of
      (first : rest)
        | T.strip first == "---" ->
            case break (\l -> T.strip l == "---") rest of
              (_, []) -> pure ()
              (fmLines, closingDash : bodyLines) ->
                let updatedFm = upsertFmField fmLines "URL" (quoteYamlValue newUrl)
                in TIO.writeFile filePath
                     (T.intercalate "\n" (first : updatedFm <> [closingDash] <> bodyLines))
      _ -> pure ()

upsertFmField :: [Text] -> Text -> Text -> [Text]
upsertFmField ls key renderedVal =
  let newLine = key <> ": " <> renderedVal
      pat = key <> ":"
      has = any (T.isPrefixOf pat . T.stripStart) ls
      replaced = fmap (\l -> if T.isPrefixOf pat (T.stripStart l) then newLine else l) ls
  in if has then replaced else ls <> [newLine]
