module Automation.Wikilink
  ( formatWikilink
  , buildBackLink
  , buildForwardLink
  , backMarker
  , forwardMarker
  , addForwardNavLink
  ) where

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
  in formatWikilink (bscId series <> "/" <> slug) backMarker

buildForwardLink :: BlogSeriesConfig -> Text -> Text
buildForwardLink series filename =
  let slug = fromMaybe filename (T.stripSuffix ".md" filename)
  in formatWikilink (bscId series <> "/" <> slug) forwardMarker

addForwardNavLink :: Text -> Text -> Text -> Text -> Text
addForwardNavLink directory fallbackMarker content targetDate =
  let forwardLink = formatWikilink (directory <> "/" <> targetDate) forwardMarker
  in if T.isInfixOf forwardMarker content
    then content
    else if T.isInfixOf (backMarker <> "]]") content
      then T.replace (backMarker <> "]]") (backMarker <> "]] " <> forwardLink) content
      else if T.isInfixOf fallbackMarker content
        then T.replace fallbackMarker (fallbackMarker <> " | " <> forwardLink) content
        else content
