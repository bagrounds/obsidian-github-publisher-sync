{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}

module Automation.BlogComments
  ( BlogComment (..)
  , fetchGiscusComments
  , fetchAllSeriesComments
  ) where

import Automation.Json
  ( FromValue (..)
  , Value (..)
  , (.=)
  , (.:)
  , (.:?)
  , encode
  , eitherDecode
  , object
  , withObject
  )
import Data.List (sortBy)
import Data.Maybe (fromMaybe)
import Data.Ord (Down (..), comparing)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Network.HTTP.Client
  ( Manager
  , Request (..)
  , RequestBody (..)
  , httpLbs
  , parseRequest
  , responseBody
  , responseStatus
  )
import Network.HTTP.Types.Status (statusCode)
import System.Environment (lookupEnv)

giscusRepo :: Text
giscusRepo = "bagrounds/obsidian-github-publisher-sync"

graphqlEndpoint :: String
graphqlEndpoint = "https://api.github.com/graphql"

data BlogComment = BlogComment
  { bcAuthor     :: Text
  , bcBody       :: Text
  , bcCreatedAt  :: Text
  , bcIsPriority :: Bool
  } deriving (Show, Eq)

data GqlAuthor = GqlAuthor
  { gaLogin :: Text
  } deriving (Show, Eq)

instance FromValue GqlAuthor where
  fromValue = withObject "GqlAuthor" $ \v ->
    GqlAuthor <$> v .: "login"

data GqlComment = GqlComment
  { gcBody      :: Text
  , gcAuthor    :: Maybe GqlAuthor
  , gcCreatedAt :: Text
  } deriving (Show, Eq)

instance FromValue GqlComment where
  fromValue = withObject "GqlComment" $ \v ->
    GqlComment
      <$> v .: "body"
      <*> v .:? "author"
      <*> v .: "createdAt"

data GqlCommentsNode = GqlCommentsNode
  { gcnNodes :: [GqlComment]
  } deriving (Show, Eq)

instance FromValue GqlCommentsNode where
  fromValue = withObject "GqlCommentsNode" $ \v ->
    GqlCommentsNode <$> v .: "nodes"

data GqlDiscussion = GqlDiscussion
  { gdTitle    :: Text
  , gdComments :: GqlCommentsNode
  } deriving (Show, Eq)

instance FromValue GqlDiscussion where
  fromValue = withObject "GqlDiscussion" $ \v ->
    GqlDiscussion
      <$> v .: "title"
      <*> v .: "comments"

data GqlSearchNodes = GqlSearchNodes
  { gsnNodes :: [GqlDiscussion]
  } deriving (Show, Eq)

instance FromValue GqlSearchNodes where
  fromValue = withObject "GqlSearchNodes" $ \v ->
    GqlSearchNodes <$> v .: "nodes"

data GqlSearchData = GqlSearchData
  { gsdSearch :: GqlSearchNodes
  } deriving (Show, Eq)

instance FromValue GqlSearchData where
  fromValue = withObject "GqlSearchData" $ \v ->
    GqlSearchData <$> v .: "search"

data GqlError = GqlError
  { geMessage :: Text
  } deriving (Show, Eq)

instance FromValue GqlError where
  fromValue = withObject "GqlError" $ \v ->
    GqlError <$> v .: "message"

data GqlResponse = GqlResponse
  { grData   :: Maybe GqlSearchData
  , grErrors :: Maybe [GqlError]
  } deriving (Show, Eq)

instance FromValue GqlResponse where
  fromValue = withObject "GqlResponse" $ \v ->
    GqlResponse
      <$> v .:? "data"
      <*> v .:? "errors"

toComment :: Maybe Text -> GqlComment -> BlogComment
toComment priorityUser gc = BlogComment
  { bcAuthor     = maybe "unknown" gaLogin (gcAuthor gc)
  , bcBody       = gcBody gc
  , bcCreatedAt  = gcCreatedAt gc
  , bcIsPriority = case priorityUser of
      Just pu -> maybe False (\a -> gaLogin a == pu) (gcAuthor gc)
      Nothing -> False
  }

buildQuery :: Int -> Int -> Text
buildQuery maxResults maxComments =
  "query($searchQuery: String!) { search(type: DISCUSSION, query: $searchQuery, first: "
    <> T.pack (show maxResults)
    <> ") { nodes { ... on Discussion { title, comments(first: "
    <> T.pack (show maxComments)
    <> ") { nodes { body, author { login }, createdAt } } } } } }"

searchDiscussions :: Manager -> Text -> Text -> Int -> Int -> IO [GqlDiscussion]
searchDiscussions manager token searchQuery maxResults maxComments = do
  initReq <- parseRequest graphqlEndpoint
  let body = encode $ object
        [ "query" .= buildQuery maxResults maxComments
        , "variables" .= object [ "searchQuery" .= searchQuery ]
        ]
  let httpReq = initReq
        { method = "POST"
        , requestBody = RequestBodyLBS body
        , requestHeaders =
            [ ("Authorization", "Bearer " <> TE.encodeUtf8 token)
            , ("Content-Type", "application/json")
            , ("User-Agent", "obsidian-github-publisher-sync")
            ]
        }
  response <- httpLbs httpReq manager
  let status = statusCode $ responseStatus response
  case status of
    200 ->
      case eitherDecode (responseBody response) of
        Left err -> do
          putStrLn $ "GraphQL parse error: " <> err
          pure []
        Right gqlResp ->
          case grErrors gqlResp of
            Just errs -> do
              putStrLn $ "GraphQL errors: " <> show (fmap geMessage errs)
              pure []
            Nothing ->
              pure $ maybe [] (gsnNodes . gsdSearch) (grData gqlResp)
    _ -> do
      putStrLn $ "GraphQL HTTP error: " <> show status
      pure []

fetchGiscusComments :: Manager -> Text -> Maybe Text -> IO [BlogComment]
fetchGiscusComments manager pathname priorityUser = do
  mToken <- lookupEnv "GITHUB_TOKEN"
  case mToken of
    Nothing -> do
      putStrLn "skip_giscus: no GITHUB_TOKEN"
      pure []
    Just token -> do
      let searchQuery = "repo:" <> giscusRepo <> " in:title \"" <> pathname <> "\""
      discussions <- searchDiscussions manager (T.pack token) searchQuery 1 100
      pure $ case discussions of
        []    -> []
        (d:_) -> fmap (toComment priorityUser) (gcnNodes $ gdComments d)

fetchAllSeriesComments :: Manager -> Text -> Maybe Text -> IO [BlogComment]
fetchAllSeriesComments manager seriesId priorityUser = do
  mToken <- lookupEnv "GITHUB_TOKEN"
  case mToken of
    Nothing -> do
      putStrLn "skip_giscus: no GITHUB_TOKEN"
      pure []
    Just token -> do
      let searchQuery = "repo:" <> giscusRepo <> " in:title \"" <> seriesId <> "/\""
      discussions <- searchDiscussions manager (T.pack token) searchQuery 50 50
      let allComments = concatMap (fmap (toComment priorityUser) . gcnNodes . gdComments) discussions
      pure $ sortBy (comparing (Down . bcCreatedAt)) allComments
