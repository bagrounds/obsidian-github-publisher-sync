module Automation.Wikilink
  ( formatWikilink
  , buildBackLink
  , buildForwardLink
  , backMarker
  , forwardMarker
  , NavigableDirectory (..)
  , directoryIndexLink
  , buildNavBackLink
  , buildNavForwardLink
  , insertForwardNavLink
  ) where

import Control.Applicative ((<|>))
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T

import Automation.BlogSeriesConfig (BlogSeriesConfig (..))

backMarker :: Text
backMarker = "⏮️"

forwardMarker :: Text
forwardMarker = "⏭️"

formatWikilink :: Text -> Text -> Text
formatWikilink target alias = "[[" <> target <> "|" <> alias <> "]]"

buildBackLink :: BlogSeriesConfig -> Text -> Text
buildBackLink series filename =
  let slug = fromMaybe filename (T.stripSuffix ".md" filename)
  in formatWikilink (identifier series <> "/" <> slug) backMarker

buildForwardLink :: BlogSeriesConfig -> Text -> Text
buildForwardLink series filename =
  let slug = fromMaybe filename (T.stripSuffix ".md" filename)
  in formatWikilink (identifier series <> "/" <> slug) forwardMarker

data NavigableDirectory
  = Reflections
  | Changes
  deriving (Eq, Show)

navigableDirectoryPath :: NavigableDirectory -> Text
navigableDirectoryPath Reflections = "reflections"
navigableDirectoryPath Changes = "changes"

navigableDirectoryDisplayName :: NavigableDirectory -> Text
navigableDirectoryDisplayName Reflections = "Reflections"
navigableDirectoryDisplayName Changes = "Changes"

directoryIndexLink :: NavigableDirectory -> Text
directoryIndexLink directory =
  formatWikilink
    (navigableDirectoryPath directory <> "/index")
    (navigableDirectoryDisplayName directory)

buildNavBackLink :: NavigableDirectory -> Text -> Text
buildNavBackLink directory date =
  formatWikilink (navigableDirectoryPath directory <> "/" <> date) backMarker

buildNavForwardLink :: NavigableDirectory -> Text -> Text
buildNavForwardLink directory date =
  formatWikilink (navigableDirectoryPath directory <> "/" <> date) forwardMarker

insertForwardNavLink :: NavigableDirectory -> Text -> Text -> Text
insertForwardNavLink directory content targetDate
  | T.isInfixOf forwardMarker content = content
  | otherwise = fromMaybe content
      (insertAfterBackLink forwardLink content
       <|> insertAfterAnchor (directoryIndexLink directory) forwardLink content)
  where
    forwardLink = buildNavForwardLink directory targetDate

insertAfterBackLink :: Text -> Text -> Maybe Text
insertAfterBackLink forwardLink content =
  let backClose = backMarker <> "]]"
  in if T.isInfixOf backClose content
    then Just (T.replace backClose (backClose <> " " <> forwardLink) content)
    else Nothing

insertAfterAnchor :: Text -> Text -> Text -> Maybe Text
insertAfterAnchor anchor forwardLink content =
  if T.isInfixOf anchor content
    then Just (T.replace anchor (anchor <> " | " <> forwardLink) content)
    else Nothing
