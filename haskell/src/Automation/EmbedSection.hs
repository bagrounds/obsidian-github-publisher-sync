module Automation.EmbedSection
  ( EmbedSection (..)
  , createSectionBuilder
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

import qualified Automation.Platforms.Bluesky as Bluesky
import qualified Automation.Platforms.Mastodon as Mastodon
import qualified Automation.Platforms.Twitter as Twitter

data EmbedSection = EmbedSection
  { esHeader :: Text
  , esEmbedHtml :: Text
  , esBuildSection :: Text -> Text -> Text
  }

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
buildTweetSection = createSectionBuilder Twitter.sectionHeader

buildBlueskySection :: Text -> Text -> Text
buildBlueskySection = createSectionBuilder Bluesky.sectionHeader

buildMastodonSection :: Text -> Text -> Text
buildMastodonSection = createSectionBuilder Mastodon.sectionHeader

appendTweetSection :: FilePath -> Text -> IO ()
appendTweetSection = createSectionAppender Twitter.sectionHeader

appendBlueskySection :: FilePath -> Text -> IO ()
appendBlueskySection = createSectionAppender Bluesky.sectionHeader

appendMastodonSection :: FilePath -> Text -> IO ()
appendMastodonSection = createSectionAppender Mastodon.sectionHeader
