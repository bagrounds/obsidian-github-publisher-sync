{-# LANGUAGE OverloadedStrings #-}

module Automation.BlogComments
  ( BlogComment (..)
  , fetchGiscusComments
  , fetchAllSeriesComments
  ) where

import Automation.BlogComments.GraphQL
  ( GqlComment
  , GqlDiscussion
  , GqlResponse
  )
import qualified Automation.BlogComments.GraphQL as Gql
import Automation.Json
  ( (.=)
  , encode
  , eitherDecode
  , object
  )
import Data.List (sortOn)
import Data.Ord (Down (..))
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
  { author     :: Text
  , body       :: Text
  , createdAt  :: Text
  , isPriority :: Bool
  } deriving (Show, Eq)

toComment :: Maybe Text -> GqlComment -> BlogComment
toComment priorityUser graphqlComment = BlogComment
  { author     = maybe "unknown" Gql.login (Gql.author graphqlComment)
  , body       = Gql.body graphqlComment
  , createdAt  = Gql.createdAt graphqlComment
  , isPriority = case priorityUser of
      Just pu -> maybe False (\a -> Gql.login a == pu) (Gql.author graphqlComment)
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
  initialRequest <- parseRequest graphqlEndpoint
  let requestBody' = encode $ object
        [ "query" .= buildQuery maxResults maxComments
        , "variables" .= object [ "searchQuery" .= searchQuery ]
        ]
  let httpReq = initialRequest
        { method = "POST"
        , requestBody = RequestBodyLBS requestBody'
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
          case Gql.errors (gqlResp :: GqlResponse) of
            Just errs -> do
              putStrLn $ "GraphQL errors: " <> show (fmap Gql.message errs)
              pure []
            Nothing ->
              pure $ maybe [] (Gql.searchNodes . Gql.search) (Gql.responseData gqlResp)
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
        (d:_) -> fmap (toComment priorityUser) (Gql.nodes $ Gql.comments d)

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
      let allComments = concatMap (fmap (toComment priorityUser) . Gql.nodes . Gql.comments) discussions
      pure $ sortOn (Down . createdAt) allComments
