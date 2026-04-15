module Automation.Wikilink
  ( formatWikilink
  , buildBackLink
  , buildForwardLink
  ) where

import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T

import Automation.BlogSeriesConfig (BlogSeriesConfig (..))

formatWikilink :: Text -> Text -> Text
formatWikilink target alias = "[[" <> target <> "|" <> alias <> "]]"

buildBackLink :: BlogSeriesConfig -> Text -> Text
buildBackLink series filename =
  let slug = fromMaybe filename (T.stripSuffix ".md" filename)
  in formatWikilink (bscId series <> "/" <> slug) "⏮️"

buildForwardLink :: BlogSeriesConfig -> Text -> Text
buildForwardLink series filename =
  let slug = fromMaybe filename (T.stripSuffix ".md" filename)
  in formatWikilink (bscId series <> "/" <> slug) "⏭️"
