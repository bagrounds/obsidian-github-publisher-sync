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
  fromValue = withObject "GqlAuthor" $ \v ->
    GqlAuthor <$> v .: "login" <*> v .: "url"

data GqlComment = GqlComment
  { bodyHtml  :: Text
  , author    :: Maybe GqlAuthor
  , createdAt :: Text
  } deriving (Show, Eq)

instance FromValue GqlComment where
  fromValue = withObject "GqlComment" $ \v ->
    GqlComment
      <$> v .: "bodyHTML"
      <*> v .:? "author"
      <*> v .: "createdAt"

newtype GqlCommentsNode = GqlCommentsNode
  { nodes :: [GqlComment]
  } deriving (Show, Eq)

instance FromValue GqlCommentsNode where
  fromValue = withObject "GqlCommentsNode" $ \v ->
    GqlCommentsNode <$> v .: "nodes"

data GqlDiscussion = GqlDiscussion
  { title    :: Text
  , comments :: GqlCommentsNode
  } deriving (Show, Eq)

instance FromValue GqlDiscussion where
  fromValue = withObject "GqlDiscussion" $ \v ->
    GqlDiscussion
      <$> v .: "title"
      <*> v .: "comments"

data GqlPageInfo = GqlPageInfo
  { hasNextPage :: Bool
  , endCursor   :: Maybe Text
  } deriving (Show, Eq)

instance FromValue GqlPageInfo where
  fromValue = withObject "GqlPageInfo" $ \v ->
    GqlPageInfo <$> v .: "hasNextPage" <*> v .:? "endCursor"

data GqlDiscussionsPage = GqlDiscussionsPage
  { discussionNodes :: [GqlDiscussion]
  , pageInfo        :: GqlPageInfo
  } deriving (Show, Eq)

instance FromValue GqlDiscussionsPage where
  fromValue = withObject "GqlDiscussionsPage" $ \v ->
    GqlDiscussionsPage <$> v .: "nodes" <*> v .: "pageInfo"

newtype GqlRepository = GqlRepository
  { discussions :: Maybe GqlDiscussionsPage
  } deriving (Show, Eq)

instance FromValue GqlRepository where
  fromValue = withObject "GqlRepository" $ \v ->
    GqlRepository <$> v .:? "discussions"

newtype GqlData = GqlData
  { repository :: Maybe GqlRepository
  } deriving (Show, Eq)

instance FromValue GqlData where
  fromValue = withObject "GqlData" $ \v ->
    GqlData <$> v .:? "repository"

newtype GqlError = GqlError
  { message :: Text
  } deriving (Show, Eq)

instance FromValue GqlError where
  fromValue = withObject "GqlError" $ \v ->
    GqlError <$> v .: "message"

data GqlResponse = GqlResponse
  { responseData :: Maybe GqlData
  , errors       :: Maybe [GqlError]
  } deriving (Show, Eq)

instance FromValue GqlResponse where
  fromValue = withObject "GqlResponse" $ \v ->
    GqlResponse
      <$> v .:? "data"
      <*> v .:? "errors"
