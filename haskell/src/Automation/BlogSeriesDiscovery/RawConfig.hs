module Automation.BlogSeriesDiscovery.RawConfig
  ( RawConfig (..)
  ) where

import Data.Maybe (fromMaybe)
import Data.Text (Text)

import Automation.ContextQuery (ContextQuery)
import Automation.Json (FromValue (..), withObject, (.:), (.:?))

data RawConfig = RawConfig
  { name                :: Text
  , icon                :: Text
  , priorityUser        :: Maybe Text
  , scheduleHourPacific :: Int
  , models              :: [Text]
  , contextSources      :: Maybe [ContextQuery]
  , enableGrounding     :: Bool
  }

instance FromValue RawConfig where
  fromValue = withObject "series config" $ \obj -> do
    name <- obj .: "name"
    icon <- obj .: "icon"
    priorityUser <- obj .:? "priorityUser"
    scheduleHourPacific <- obj .: "scheduleHourPacific"
    models <- obj .: "models"
    contextSources <- obj .:? "contextSources"
    enableGrounding <- fromMaybe False <$> obj .:? "enableGrounding"
    pure RawConfig{..}
