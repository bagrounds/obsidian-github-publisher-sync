{-# LANGUAGE OverloadedStrings #-}

module Automation.BlogComments.GraphQL
  ( GqlAuthor (..)
  , GqlComment (..)
  , GqlCommentsNode (..)
  , GqlDiscussion (..)
  , GqlSearchNodes (..)
  , GqlSearchData (..)
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

newtype GqlAuthor = GqlAuthor
  { login :: Text
  } deriving (Show, Eq)

instance FromValue GqlAuthor where
  fromValue = withObject "GqlAuthor" $ \value ->
    GqlAuthor <$> value .: "login"

data GqlComment = GqlComment
  { body      :: Text
  , author    :: Maybe GqlAuthor
  , createdAt :: Text
  } deriving (Show, Eq)

instance FromValue GqlComment where
  fromValue = withObject "GqlComment" $ \value ->
    GqlComment
      <$> value .: "body"
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

newtype GqlSearchNodes = GqlSearchNodes
  { searchNodes :: [GqlDiscussion]
  } deriving (Show, Eq)

instance FromValue GqlSearchNodes where
  fromValue = withObject "GqlSearchNodes" $ \value ->
    GqlSearchNodes <$> value .: "nodes"

newtype GqlSearchData = GqlSearchData
  { search :: GqlSearchNodes
  } deriving (Show, Eq)

instance FromValue GqlSearchData where
  fromValue = withObject "GqlSearchData" $ \value ->
    GqlSearchData <$> value .: "search"

newtype GqlError = GqlError
  { message :: Text
  } deriving (Show, Eq)

instance FromValue GqlError where
  fromValue = withObject "GqlError" $ \value ->
    GqlError <$> value .: "message"

data GqlResponse = GqlResponse
  { responseData :: Maybe GqlSearchData
  , errors       :: Maybe [GqlError]
  } deriving (Show, Eq)

instance FromValue GqlResponse where
  fromValue = withObject "GqlResponse" $ \value ->
    GqlResponse
      <$> value .:? "data"
      <*> value .:? "errors"
