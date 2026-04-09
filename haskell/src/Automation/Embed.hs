module Automation.Embed
  ( EmbedResult (..)
  , EmbedSection (..)
  , OgMetadata (..)
  , LinkCard (..)
  ) where

import Data.Text (Text)

import Automation.Title (Title)
import Automation.Url (Url)

newtype EmbedResult = EmbedResult
  { erHtml :: Text
  } deriving (Show, Eq)

data EmbedSection = EmbedSection
  { esHeader :: Text
  , esEmbedHtml :: Text
  , esBuildSection :: Text -> Text -> Text
  }

data OgMetadata = OgMetadata
  { ogTitle :: Maybe Title
  , ogDescription :: Maybe Text
  , ogImageUrl :: Maybe Text
  } deriving (Show, Eq)

data LinkCard = LinkCard
  { lcUri :: Url
  , lcTitle :: Title
  , lcDescription :: Text
  , lcThumbUrl :: Maybe Text
  } deriving (Show, Eq)
