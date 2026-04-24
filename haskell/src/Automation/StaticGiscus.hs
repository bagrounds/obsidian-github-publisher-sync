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

import qualified Automation.StaticGiscus.GqlTypes as Gql
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

data StaticComment = StaticComment
  { author    :: Text
  , authorUrl :: Text
  , bodyHtml  :: Text
  , createdAt :: Text
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

toStaticComment :: Gql.GqlComment -> StaticComment
toStaticComment gqlComment = StaticComment
  { author    = maybe "unknown" Gql.login (Gql.author gqlComment)
  , authorUrl = maybe "https://github.com" Gql.url (Gql.author gqlComment)
  , bodyHtml  = Gql.bodyHtml gqlComment
  , createdAt = Gql.createdAt gqlComment
  }

buildCommentsMap :: [Gql.GqlDiscussion] -> CommentsMap
buildCommentsMap discussionList =
  Map.fromList $ mapMaybe toEntry discussionList
  where
    toEntry discussion =
      let pathname = normalizePathname (titleToPathname (Gql.title discussion))
          commentList = fmap toStaticComment (Gql.comments (Gql.commentsPage discussion))
      in if null commentList then Nothing else Just (pathname, commentList)

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
renderStaticComment staticComment =
  "<article class=\"static-giscus-comment\">\n\
  \<header class=\"static-giscus-comment-header\">\n\
  \<a href=\"" <> escapeHtml (authorUrl staticComment) <> "\" rel=\"nofollow\" class=\"static-giscus-author\">"
  <> escapeHtml (author staticComment) <> "</a>\n\
  \<time datetime=\"" <> createdAt staticComment <> "\" class=\"static-giscus-time\">"
  <> formatDisplayDate (T.take 10 (createdAt staticComment)) <> "</time>\n\
  \</header>\n\
  \<div class=\"static-giscus-body\">" <> bodyHtml staticComment <> "</div>\n\
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
            Just idx ->
              T.take idx html <> staticHtml <> "\n" <> T.drop idx html

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

fetchDiscussionPage :: Manager -> Text -> Text -> Text -> Text -> Maybe Text -> IO (Maybe Gql.GqlDiscussionsPage)
fetchDiscussionPage manager token owner repo categoryId mAfter = do
  parsedRequest <- parseRequest graphqlEndpoint
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
        , "after" .= mAfter
        ]
      body = encode $ object
        [ "query" .= (query :: Text)
        , "variables" .= variables
        ]
      request = parsedRequest
        { method = "POST"
        , requestBody = RequestBodyLBS body
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
          pure Nothing
        Right gqlResponse ->
          case Gql.responseErrors gqlResponse of
            Just errs -> do
              putStrLn $ "GraphQL errors: " <> show (fmap Gql.message errs)
              pure Nothing
            Nothing ->
              pure $ Gql.responseData gqlResponse >>= Gql.repository >>= Gql.repositoryDiscussions >>= Just
    _ -> do
      putStrLn $ "GraphQL HTTP error: " <> show status
      pure Nothing

fetchAllDiscussions :: Manager -> Text -> Text -> Text -> Text -> IO [Gql.GqlDiscussion]
fetchAllDiscussions manager token owner repo categoryId =
  go Nothing []
  where
    go maybeAfter accumulator = do
      maybePage <- fetchDiscussionPage manager token owner repo categoryId maybeAfter
      case maybePage of
        Nothing -> pure accumulator
        Just page ->
          let newAccumulator = accumulator <> Gql.discussions page
          in if Gql.hasNextPage (Gql.pageInfo page)
             then go (Gql.endCursor (Gql.pageInfo page)) newAccumulator
             else pure newAccumulator

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
