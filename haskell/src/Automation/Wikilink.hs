module Automation.Wikilink
  ( formatWikilink
  ) where

import Data.Text (Text)

formatWikilink :: Text -> Text -> Text
formatWikilink target alias = "[[" <> target <> "|" <> alias <> "]]"
