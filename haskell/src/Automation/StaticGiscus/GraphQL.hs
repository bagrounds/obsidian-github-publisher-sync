module Automation.StaticGiscus.GraphQL
  ( GqlAuthor (..)
  , GqlComment (..)
  , GqlCommentsNode (..)
  , GqlDiscussion (..)
  , GqlPageInfo (..)
  , GqlDiscussionsPage (..)
  , GqlRepository (..)
  , GqlData (..)
  , GqlError (..)
  , GqlResponse (..)
  ) where

import Automation.Json
  ( FromValue (..)
  , (.:)
  , (.:?)
  , withObject
  )
import Data.Text (Text)

data GqlAuthor = GqlAuthor
  { login :: Text
  , url   :: Text
  } deriving (Show, Eq)

instance FromValue GqlAuthor where
  fromValue = withObject "GqlAuthor" $ \value ->
    GqlAuthor <$> value .: "login" <*> value .: "url"

data GqlComment = GqlComment
  { bodyHtml  :: Text
  , author    :: Maybe GqlAuthor
  , createdAt :: Text
  } deriving (Show, Eq)

instance FromValue GqlComment where
  fromValue = withObject "GqlComment" $ \value ->
    GqlComment
      <$> value .: "bodyHTML"
      <*> value .:? "author"
      <*> value .: "createdAt"

newtype GqlCommentsNode = GqlCommentsNode
  { nodes :: [GqlComment]
  } deriving (Show, Eq)

instance FromValue GqlCommentsNode where
  fromValue = withObject "GqlCommentsNode" $ \value ->
    GqlCommentsNode <$> value .: "nodes"

data GqlDiscussion = GqlDiscussion
  { title    :: Text
  , comments :: GqlCommentsNode
  } deriving (Show, Eq)

instance FromValue GqlDiscussion where
  fromValue = withObject "GqlDiscussion" $ \value ->
    GqlDiscussion
      <$> value .: "title"
      <*> value .: "comments"

data GqlPageInfo = GqlPageInfo
  { hasNextPage :: Bool
  , endCursor   :: Maybe Text
  } deriving (Show, Eq)

instance FromValue GqlPageInfo where
  fromValue = withObject "GqlPageInfo" $ \value ->
    GqlPageInfo <$> value .: "hasNextPage" <*> value .:? "endCursor"

data GqlDiscussionsPage = GqlDiscussionsPage
  { discussionNodes :: [GqlDiscussion]
  , pageInfo        :: GqlPageInfo
  } deriving (Show, Eq)

instance FromValue GqlDiscussionsPage where
  fromValue = withObject "GqlDiscussionsPage" $ \value ->
    GqlDiscussionsPage <$> value .: "nodes" <*> value .: "pageInfo"

newtype GqlRepository = GqlRepository
  { discussions :: Maybe GqlDiscussionsPage
  } deriving (Show, Eq)

instance FromValue GqlRepository where
  fromValue = withObject "GqlRepository" $ \value ->
    GqlRepository <$> value .:? "discussions"

newtype GqlData = GqlData
  { repository :: Maybe GqlRepository
  } deriving (Show, Eq)

instance FromValue GqlData where
  fromValue = withObject "GqlData" $ \value ->
    GqlData <$> value .:? "repository"

newtype GqlError = GqlError
  { message :: Text
  } deriving (Show, Eq)

instance FromValue GqlError where
  fromValue = withObject "GqlError" $ \value ->
    GqlError <$> value .: "message"

data GqlResponse = GqlResponse
  { responseData :: Maybe GqlData
  , errors       :: Maybe [GqlError]
  } deriving (Show, Eq)

instance FromValue GqlResponse where
  fromValue = withObject "GqlResponse" $ \value ->
    GqlResponse
      <$> value .:? "data"
      <*> value .:? "errors"
