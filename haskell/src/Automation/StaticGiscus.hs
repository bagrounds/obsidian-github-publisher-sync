module Automation.StaticGiscus
  ( StaticComment (..)
  , CommentsMap
  , normalizePathname
  , slugToPathname
  , titleToPathname
  , buildCommentsMap
  , renderStaticComment
  , renderStaticCommentsHtml
  , extractSlug
  , findGiscusDiv
  , injectStaticComments
  , fetchAllDiscussions
  , walkHtmlFiles
  , processHtmlFiles
  ) where

import Automation.Json
  ( (.=)
  , encode
  , eitherDecode
  , object
  )
import Control.Monad (filterM)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (catMaybes, mapMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Text.IO as TIO
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
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory)
import System.FilePath ((</>), takeExtension)

import Automation.Html (escapeHtml, formatDisplayDate)
import Automation.StaticGiscus.GraphQL
  ( GqlComment
  , GqlDiscussion
  , GqlDiscussionsPage
  )
import qualified Automation.StaticGiscus.GraphQL as Gql

data StaticComment = StaticComment
  { author      :: Text
  , authorUrl   :: Text
  , bodyHtml    :: Text
  , createdAt   :: Text
  } deriving (Show, Eq)

type CommentsMap = Map Text [StaticComment]

normalizePathname :: Text -> Text
normalizePathname p
  | p == "/" = "/"
  | otherwise = T.dropWhileEnd (== '/') p

slugToPathname :: Text -> Text
slugToPathname slug
  | slug == "index" = "/"
  | otherwise = "/" <> slug

titleToPathname :: Text -> Text
titleToPathname title
  | T.isPrefixOf "/" title = title
  | otherwise = "/" <> title

toStaticComment :: GqlComment -> StaticComment
toStaticComment c = StaticComment
  { author    = maybe "unknown" Gql.login (Gql.author c)
  , authorUrl = maybe "https://github.com" Gql.url (Gql.author c)
  , bodyHtml  = Gql.bodyHtml c
  , createdAt = Gql.createdAt c
  }

buildCommentsMap :: [GqlDiscussion] -> CommentsMap
buildCommentsMap discussions =
  Map.fromList $ mapMaybe toEntry discussions
  where
    toEntry d =
      let pathname = normalizePathname (titleToPathname (Gql.title d))
          staticComments = fmap toStaticComment (Gql.nodes (Gql.comments d))
      in if null staticComments then Nothing else Just (pathname, staticComments)

staticGiscusCss :: Text
staticGiscusCss = "<style>\n\
  \.static-giscus-comments { margin-top: 1rem; }\n\
  \.static-giscus-comment {\n\
  \  margin-bottom: 1rem;\n\
  \  padding: 0.75rem 1rem;\n\
  \  border: 1px solid var(--lightgray);\n\
  \  border-radius: 8px;\n\
  \}\n\
  \.static-giscus-comment-header {\n\
  \  display: flex;\n\
  \  align-items: center;\n\
  \  gap: 0.5rem;\n\
  \  margin-bottom: 0.5rem;\n\
  \  font-size: 0.875rem;\n\
  \}\n\
  \.static-giscus-author {\n\
  \  font-weight: 600;\n\
  \  color: var(--secondary);\n\
  \  text-decoration: none;\n\
  \}\n\
  \.static-giscus-author:hover { text-decoration: underline; }\n\
  \.static-giscus-time { color: var(--gray); font-size: 0.8rem; }\n\
  \.static-giscus-body { line-height: 1.6; color: var(--darkgray); }\n\
  \.static-giscus-body p { margin: 0.5em 0; }\n\
  \.static-giscus-body p:first-child { margin-top: 0; }\n\
  \.static-giscus-body p:last-child { margin-bottom: 0; }\n\
  \</style>"

renderStaticComment :: StaticComment -> Text
renderStaticComment c =
  "<article class=\"static-giscus-comment\">\n\
  \<header class=\"static-giscus-comment-header\">\n\
  \<a href=\"" <> escapeHtml (authorUrl c) <> "\" rel=\"nofollow\" class=\"static-giscus-author\">"
  <> escapeHtml (author c) <> "</a>\n\
  \<time datetime=\"" <> createdAt c <> "\" class=\"static-giscus-time\">"
  <> formatDisplayDate (T.take 10 (createdAt c)) <> "</time>\n\
  \</header>\n\
  \<div class=\"static-giscus-body\">" <> bodyHtml c <> "</div>\n\
  \</article>"

renderStaticCommentsHtml :: [StaticComment] -> Text
renderStaticCommentsHtml [] = ""
renderStaticCommentsHtml comments =
  "<section data-static-giscus class=\"static-giscus-comments\" aria-label=\"Comments\">\n"
  <> staticGiscusCss <> "\n"
  <> T.intercalate "\n" (fmap renderStaticComment comments) <> "\n"
  <> "</section>"

extractSlug :: Text -> Maybe Text
extractSlug html =
  case T.breakOn "data-slug=\"" html of
    (_, rest) | not (T.null rest) ->
      let afterAttr = T.drop 11 rest
          slug = T.takeWhile (/= '"') afterAttr
      in Just slug
    _ -> Nothing

giscusDivPattern :: Text
giscusDivPattern = "<div class=\""

injectStaticComments :: Text -> CommentsMap -> Text
injectStaticComments html commentsMap =
  case extractSlug html of
    Nothing -> html
    Just slug ->
      let pathname = normalizePathname (slugToPathname slug)
      in case Map.lookup pathname commentsMap of
        Nothing -> html
        Just [] -> html
        Just comments ->
          let staticHtml = renderStaticCommentsHtml comments
          in case findGiscusDiv html of
            Nothing -> html
            Just insertionPoint ->
              T.take insertionPoint html <> staticHtml <> "\n" <> T.drop insertionPoint html

findGiscusDiv :: Text -> Maybe Int
findGiscusDiv html =
  let segments = T.breakOnAll giscusDivPattern html
      giscusSegments = filter (\(_, after) ->
        let afterDiv = T.drop (T.length giscusDivPattern) after
            classValue = T.takeWhile (/= '"') afterDiv
        in T.isInfixOf "giscus" classValue) segments
  in case giscusSegments of
    ((before, _):_) -> Just (T.length before)
    [] -> Nothing

graphqlEndpoint :: String
graphqlEndpoint = "https://api.github.com/graphql"

fetchDiscussionPage :: Manager -> Text -> Text -> Text -> Text -> Maybe Text -> IO (Maybe GqlDiscussionsPage)
fetchDiscussionPage manager token owner repo categoryId maybeAfterCursor = do
  initialRequest <- parseRequest graphqlEndpoint
  let query = "query($owner: String!, $name: String!, $categoryId: ID!, $after: String) {\
              \ repository(owner: $owner, name: $name) {\
              \   discussions(categoryId: $categoryId, first: 100, after: $after, orderBy: { field: UPDATED_AT, direction: DESC }) {\
              \     pageInfo { hasNextPage, endCursor }\
              \     nodes {\
              \       title\
              \       comments(first: 100) {\
              \         nodes { bodyHTML, author { login, url }, createdAt }\
              \       }\
              \     }\
              \   }\
              \ }\
              \}"
      variables = object
        [ "owner" .= owner
        , "name" .= repo
        , "categoryId" .= categoryId
        , "after" .= maybeAfterCursor
        ]
      body = encode $ object
        [ "query" .= (query :: Text)
        , "variables" .= variables
        ]
      httpReq = initialRequest
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
          pure Nothing
        Right gqlResp ->
          case Gql.errors gqlResp of
            Just errs -> do
              putStrLn $ "GraphQL errors: " <> show (fmap Gql.message errs)
              pure Nothing
            Nothing ->
              pure $ Gql.responseData gqlResp >>= Gql.repository >>= Gql.discussions >>= Just
    _ -> do
      putStrLn $ "GraphQL HTTP error: " <> show status
      pure Nothing

fetchAllDiscussions :: Manager -> Text -> Text -> Text -> Text -> IO [GqlDiscussion]
fetchAllDiscussions manager token owner repo categoryId =
  go Nothing []
  where
    go maybeAfterCursor accumulatedDiscussions = do
      maybePage <- fetchDiscussionPage manager token owner repo categoryId maybeAfterCursor
      case maybePage of
        Nothing -> pure accumulatedDiscussions
        Just page ->
          let updatedDiscussions = accumulatedDiscussions <> Gql.discussionNodes page
          in if Gql.hasNextPage (Gql.pageInfo page)
             then go (Gql.endCursor (Gql.pageInfo page)) updatedDiscussions
             else pure updatedDiscussions

walkHtmlFiles :: FilePath -> IO [FilePath]
walkHtmlFiles dir = do
  exists <- doesDirectoryExist dir
  if exists
    then do
      entries <- listDirectory dir
      let paths = fmap (dir </>) entries
      files <- filterM doesFileExist paths
      dirs  <- filterM doesDirectoryExist paths
      let htmlFiles = filter (\f -> takeExtension f == ".html") files
      nested <- traverse walkHtmlFiles dirs
      pure (htmlFiles <> concat nested)
    else pure []

processHtmlFiles :: FilePath -> CommentsMap -> IO [FilePath]
processHtmlFiles dir commentsMap = do
  htmlFiles <- walkHtmlFiles dir
  catMaybes <$> traverse (processOneFile commentsMap) htmlFiles

processOneFile :: CommentsMap -> FilePath -> IO (Maybe FilePath)
processOneFile commentsMap filePath = do
  content <- TIO.readFile filePath
  let updated = injectStaticComments content commentsMap
  if updated == content
    then pure Nothing
    else do
      TIO.writeFile filePath updated
      pure (Just filePath)
