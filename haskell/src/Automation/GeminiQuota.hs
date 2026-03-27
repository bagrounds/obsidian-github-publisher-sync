module Automation.GeminiQuota
  ( ModelInfo (..)
  , QuotaInfo (..)
  , fetchModelCatalog
  , checkQuota
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import qualified Network.HTTP.Client as HTTP
import qualified Network.HTTP.Client.TLS as TLS

data QuotaInfo = QuotaInfo
  { qiRequestsPerMinute :: Maybe Int
  , qiTokensPerMinute   :: Maybe Int
  , qiRequestsPerDay    :: Maybe Int
  } deriving (Show, Eq)

data ModelInfo = ModelInfo
  { miName        :: Text
  , miDisplayName :: Text
  , miQuota       :: QuotaInfo
  } deriving (Show, Eq)

fetchModelCatalog :: Text -> IO [ModelInfo]
fetchModelCatalog apiKey = do
  manager <- TLS.newTlsManager
  request <- HTTP.parseRequest (T.unpack ("https://generativelanguage.googleapis.com/v1beta/models?key=" <> apiKey))
  _response <- HTTP.httpLbs request manager
  pure []

checkQuota :: Text -> Text -> IO (Maybe QuotaInfo)
checkQuota _apiKey _modelName = pure Nothing
