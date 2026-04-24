{-# LANGUAGE OverloadedStrings #-}

module Automation.BlogComments
  ( BlogComment (..)
  , fetchGiscusComments
  , fetchAllSeriesComments
  ) where

import Automation.Json ((.=), encode, eitherDecode, object)
import qualified Automation.BlogComments.GqlTypes as Gql
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

toComment :: Maybe Text -> Gql.GqlComment -> BlogComment
toComment priorityUser gqlComment = BlogComment
  { author     = maybe "unknown" Gql.login (Gql.author gqlComment)
  , body       = Gql.body gqlComment
  , createdAt  = Gql.createdAt gqlComment
  , isPriority = case priorityUser of
      Just priorityLogin -> maybe False (\a -> Gql.login a == priorityLogin) (Gql.author gqlComment)
      Nothing            -> False
  }

buildQuery :: Int -> Int -> Text
buildQuery maxResults maxComments =
  "query($searchQuery: String!) { search(type: DISCUSSION, query: $searchQuery, first: "
    <> T.pack (show maxResults)
    <> ") { nodes { ... on Discussion { title, comments(first: "
    <> T.pack (show maxComments)
    <> ") { nodes { body, author { login }, createdAt } } } } } }"

searchDiscussions :: Manager -> Text -> Text -> Int -> Int -> IO [Gql.GqlDiscussion]
searchDiscussions manager token searchQuery maxResults maxComments = do
  parsedRequest <- parseRequest graphqlEndpoint
  let requestBody = encode $ object
        [ "query" .= buildQuery maxResults maxComments
        , "variables" .= object [ "searchQuery" .= searchQuery ]
        ]
  let request = parsedRequest
        { method = "POST"
        , requestBody = RequestBodyLBS requestBody
        , requestHeaders =
            [ ("Authorization", "Bearer " <> TE.encodeUtf8 token)
            , ("Content-Type", "application/json")
            , ("User-Agent", "obsidian-github-publisher-sync")
            ]
        }
  response <- httpLbs request manager
  let status = statusCode $ responseStatus response
  case status of
    200 ->
      case eitherDecode (responseBody response) of
        Left err -> do
          putStrLn $ "GraphQL parse error: " <> err
          pure []
        Right gqlResponse ->
          case Gql.responseErrors gqlResponse of
            Just errs -> do
              putStrLn $ "GraphQL errors: " <> show (fmap Gql.message errs)
              pure []
            Nothing ->
              pure $ maybe [] (Gql.discussions . Gql.searchNodes) (Gql.responseData gqlResponse)
    _ -> do
      putStrLn $ "GraphQL HTTP error: " <> show status
      pure []

fetchGiscusComments :: Manager -> Text -> Maybe Text -> IO [BlogComment]
fetchGiscusComments manager pathname priorityUser = do
  maybeGithubToken <- lookupEnv "GITHUB_TOKEN"
  case maybeGithubToken of
    Nothing -> do
      putStrLn "skip_giscus: no GITHUB_TOKEN"
      pure []
    Just token -> do
      let searchQuery = "repo:" <> giscusRepo <> " in:title \"" <> pathname <> "\""
      foundDiscussions <- searchDiscussions manager (T.pack token) searchQuery 1 100
      pure $ case foundDiscussions of
        []    -> []
        (d:_) -> fmap (toComment priorityUser) (Gql.comments $ Gql.commentsPage d)

fetchAllSeriesComments :: Manager -> Text -> Maybe Text -> IO [BlogComment]
fetchAllSeriesComments manager seriesId priorityUser = do
  maybeGithubToken <- lookupEnv "GITHUB_TOKEN"
  case maybeGithubToken of
    Nothing -> do
      putStrLn "skip_giscus: no GITHUB_TOKEN"
      pure []
    Just token -> do
      let searchQuery = "repo:" <> giscusRepo <> " in:title \"" <> seriesId <> "/\""
      foundDiscussions <- searchDiscussions manager (T.pack token) searchQuery 50 50
      let allComments = concatMap (fmap (toComment priorityUser) . Gql.comments . Gql.commentsPage) foundDiscussions
      pure $ sortOn (Down . createdAt) allComments
