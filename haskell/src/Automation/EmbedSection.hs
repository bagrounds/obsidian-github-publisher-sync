module Automation.EmbedSection
  ( createSectionBuilder
  , createSectionAppender
  , buildTweetSection
  , buildBlueskySection
  , buildMastodonSection
  , appendTweetSection
  , appendBlueskySection
  , appendMastodonSection
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO

import Automation.Types
  ( blueskySectionHeader
  , mastodonSectionHeader
  , tweetSectionHeader
  )

createSectionBuilder :: Text -> Text -> Text -> Text
createSectionBuilder header existingContent embedHtml =
  let separator = if T.isSuffixOf "\n" existingContent then "\n" else "\n\n"
  in separator <> header <> "  \n" <> embedHtml

createSectionAppender :: Text -> FilePath -> Text -> IO ()
createSectionAppender header filePath embedHtml = do
  content <- TIO.readFile filePath
  case T.isInfixOf header content of
    True  -> putStrLn $ T.unpack header <> " already exists, skipping update"
    False -> TIO.writeFile filePath (content <> createSectionBuilder header content embedHtml)

buildTweetSection :: Text -> Text -> Text
buildTweetSection = createSectionBuilder tweetSectionHeader

buildBlueskySection :: Text -> Text -> Text
buildBlueskySection = createSectionBuilder blueskySectionHeader

buildMastodonSection :: Text -> Text -> Text
buildMastodonSection = createSectionBuilder mastodonSectionHeader

appendTweetSection :: FilePath -> Text -> IO ()
appendTweetSection = createSectionAppender tweetSectionHeader

appendBlueskySection :: FilePath -> Text -> IO ()
appendBlueskySection = createSectionAppender blueskySectionHeader

appendMastodonSection :: FilePath -> Text -> IO ()
appendMastodonSection = createSectionAppender mastodonSectionHeader
