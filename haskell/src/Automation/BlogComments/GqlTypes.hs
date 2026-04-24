{-# LANGUAGE OverloadedStrings #-}

module Automation.BlogComments.GqlTypes
  ( GqlAuthor (..)
  , GqlComment (..)
  , GqlCommentsNode (..)
  , GqlDiscussion (..)
  , GqlSearchNodes (..)
  , GqlSearchData (..)
  , GqlError (..)
  , GqlResponse (..)
  ) where

import Automation.Json (FromValue (..), (.:), (.:?), withObject)
import Data.Text (Text)

newtype GqlAuthor = GqlAuthor
  { login :: Text
  } deriving (Show, Eq)

instance FromValue GqlAuthor where
  fromValue = withObject "GqlAuthor" $ \v ->
    GqlAuthor <$> v .: "login"

data GqlComment = GqlComment
  { body      :: Text
  , author    :: Maybe GqlAuthor
  , createdAt :: Text
  } deriving (Show, Eq)

instance FromValue GqlComment where
  fromValue = withObject "GqlComment" $ \v ->
    GqlComment
      <$> v .: "body"
      <*> v .:? "author"
      <*> v .: "createdAt"

newtype GqlCommentsNode = GqlCommentsNode
  { comments :: [GqlComment]
  } deriving (Show, Eq)

instance FromValue GqlCommentsNode where
  fromValue = withObject "GqlCommentsNode" $ \v ->
    GqlCommentsNode <$> v .: "nodes"

data GqlDiscussion = GqlDiscussion
  { title        :: Text
  , commentsPage :: GqlCommentsNode
  } deriving (Show, Eq)

instance FromValue GqlDiscussion where
  fromValue = withObject "GqlDiscussion" $ \v ->
    GqlDiscussion
      <$> v .: "title"
      <*> v .: "comments"

newtype GqlSearchNodes = GqlSearchNodes
  { discussions :: [GqlDiscussion]
  } deriving (Show, Eq)

instance FromValue GqlSearchNodes where
  fromValue = withObject "GqlSearchNodes" $ \v ->
    GqlSearchNodes <$> v .: "nodes"

newtype GqlSearchData = GqlSearchData
  { searchNodes :: GqlSearchNodes
  } deriving (Show, Eq)

instance FromValue GqlSearchData where
  fromValue = withObject "GqlSearchData" $ \v ->
    GqlSearchData <$> v .: "search"

newtype GqlError = GqlError
  { message :: Text
  } deriving (Show, Eq)

instance FromValue GqlError where
  fromValue = withObject "GqlError" $ \v ->
    GqlError <$> v .: "message"

data GqlResponse = GqlResponse
  { responseData   :: Maybe GqlSearchData
  , responseErrors :: Maybe [GqlError]
  } deriving (Show, Eq)

instance FromValue GqlResponse where
  fromValue = withObject "GqlResponse" $ \v ->
    GqlResponse
      <$> v .:? "data"
      <*> v .:? "errors"
