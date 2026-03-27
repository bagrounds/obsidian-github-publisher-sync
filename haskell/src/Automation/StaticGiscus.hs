module Automation.StaticGiscus
  ( StaticComment (..)
  , GqlDiscussion (..)
  , GqlComment (..)
  , GqlAuthor (..)
  , CommentsMap
  , normalizePathname
  , slugToPathname
  , titleToPathname
  , buildCommentsMap
  , renderStaticComment
  , renderStaticCommentsHtml
  , extractSlug
  , injectStaticComments
  , fetchAllDiscussions
  , processHtmlFiles
  ) where

import Automation.Json
  ( FromValue (..)
  , (.=)
  , (.:)
  , (.:?)
  , encode
  , eitherDecode
  , object
  , withObject
  )
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe, mapMaybe)
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
import System.Directory (doesDirectoryExist, listDirectory)
import System.FilePath ((</>))

import Automation.Html (escapeHtml, formatDisplayDate)

data GqlAuthor = GqlAuthor
  { sgaLogin :: Text
  , sgaUrl   :: Text
  } deriving (Show, Eq)

instance FromValue GqlAuthor where
  fromValue = withObject "GqlAuthor" $ \v ->
    GqlAuthor <$> v .: "login" <*> v .: "url"

data GqlComment = GqlComment
  { sgcBodyHtml  :: Text
  , sgcAuthor    :: Maybe GqlAuthor
  , sgcCreatedAt :: Text
  } deriving (Show, Eq)

instance FromValue GqlComment where
  fromValue = withObject "GqlComment" $ \v ->
    GqlComment
      <$> v .: "bodyHTML"
      <*> v .:? "author"
      <*> v .: "createdAt"

data GqlCommentsNode = GqlCommentsNode
  { sgcnNodes :: [GqlComment]
  } deriving (Show, Eq)

instance FromValue GqlCommentsNode where
  fromValue = withObject "GqlCommentsNode" $ \v ->
    GqlCommentsNode <$> v .: "nodes"

data GqlDiscussion = GqlDiscussion
  { sgdTitle    :: Text
  , sgdComments :: GqlCommentsNode
  } deriving (Show, Eq)

instance FromValue GqlDiscussion where
  fromValue = withObject "GqlDiscussion" $ \v ->
    GqlDiscussion
      <$> v .: "title"
      <*> v .: "comments"

data GqlPageInfo = GqlPageInfo
  { sgpHasNextPage :: Bool
  , sgpEndCursor   :: Maybe Text
  } deriving (Show, Eq)

instance FromValue GqlPageInfo where
  fromValue = withObject "GqlPageInfo" $ \v ->
    GqlPageInfo <$> v .: "hasNextPage" <*> v .:? "endCursor"

data GqlDiscussionsPage = GqlDiscussionsPage
  { sgdpNodes    :: [GqlDiscussion]
  , sgdpPageInfo :: GqlPageInfo
  } deriving (Show, Eq)

instance FromValue GqlDiscussionsPage where
  fromValue = withObject "GqlDiscussionsPage" $ \v ->
    GqlDiscussionsPage <$> v .: "nodes" <*> v .: "pageInfo"

data GqlRepository = GqlRepository
  { sgrDiscussions :: Maybe GqlDiscussionsPage
  } deriving (Show, Eq)

instance FromValue GqlRepository where
  fromValue = withObject "GqlRepository" $ \v ->
    GqlRepository <$> v .:? "discussions"

data GqlData = GqlData
  { sgdRepository :: Maybe GqlRepository
  } deriving (Show, Eq)

instance FromValue GqlData where
  fromValue = withObject "GqlData" $ \v ->
    GqlData <$> v .:? "repository"

data GqlError = GqlError
  { sgeMessage :: Text
  } deriving (Show, Eq)

instance FromValue GqlError where
  fromValue = withObject "GqlError" $ \v ->
    GqlError <$> v .: "message"

data GqlResponse = GqlResponse
  { sgrData   :: Maybe GqlData
  , sgrErrors :: Maybe [GqlError]
  } deriving (Show, Eq)

instance FromValue GqlResponse where
  fromValue = withObject "GqlResponse" $ \v ->
    GqlResponse
      <$> v .:? "data"
      <*> v .:? "errors"

data StaticComment = StaticComment
  { scAuthor    :: Text
  , scAuthorUrl :: Text
  , scBodyHtml  :: Text
  , scCreatedAt :: Text
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
  { scAuthor = maybe "unknown" sgaLogin (sgcAuthor c)
  , scAuthorUrl = maybe "https://github.com" sgaUrl (sgcAuthor c)
  , scBodyHtml = sgcBodyHtml c
  , scCreatedAt = sgcCreatedAt c
  }

buildCommentsMap :: [GqlDiscussion] -> CommentsMap
buildCommentsMap discussions =
  Map.fromList $ mapMaybe toEntry discussions
  where
    toEntry d =
      let pathname = normalizePathname (titleToPathname (sgdTitle d))
          comments = fmap toStaticComment (sgcnNodes (sgdComments d))
      in if null comments then Nothing else Just (pathname, comments)

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
  \<a href=\"" <> escapeHtml (scAuthorUrl c) <> "\" rel=\"nofollow\" class=\"static-giscus-author\">"
  <> escapeHtml (scAuthor c) <> "</a>\n\
  \<time datetime=\"" <> scCreatedAt c <> "\" class=\"static-giscus-time\">"
  <> formatDisplayDate (T.take 10 (scCreatedAt c)) <> "</time>\n\
  \</header>\n\
  \<div class=\"static-giscus-body\">" <> scBodyHtml c <> "</div>\n\
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
      giscusSegments = filter (\(before, after) ->
        let afterDiv = T.drop (T.length giscusDivPattern) after
            classValue = T.takeWhile (/= '"') afterDiv
        in T.isInfixOf "giscus" classValue) segments
  in case giscusSegments of
    ((before, _):_) -> Just (T.length before)
    [] -> Nothing

graphqlEndpoint :: String
graphqlEndpoint = "https://api.github.com/graphql"

fetchDiscussionPage :: Manager -> Text -> Text -> Text -> Text -> Maybe Text -> IO (Maybe GqlDiscussionsPage)
fetchDiscussionPage manager token owner repo categoryId mAfter = do
  initReq <- parseRequest graphqlEndpoint
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
      httpReq = initReq
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
          case sgrErrors gqlResp of
            Just errs -> do
              putStrLn $ "GraphQL errors: " <> show (fmap sgeMessage errs)
              pure Nothing
            Nothing ->
              pure $ sgrData gqlResp >>= sgdRepository >>= sgrDiscussions >>= Just
    _ -> do
      putStrLn $ "GraphQL HTTP error: " <> show status
      pure Nothing

fetchAllDiscussions :: Manager -> Text -> Text -> Text -> Text -> IO [GqlDiscussion]
fetchAllDiscussions manager token owner repo categoryId =
  go Nothing []
  where
    go mAfter acc = do
      mPage <- fetchDiscussionPage manager token owner repo categoryId mAfter
      case mPage of
        Nothing -> pure acc
        Just page ->
          let newAcc = acc <> sgdpNodes page
          in if sgpHasNextPage (sgdpPageInfo page)
             then go (sgpEndCursor (sgdpPageInfo page)) newAcc
             else pure newAcc

processHtmlFiles :: FilePath -> CommentsMap -> IO [FilePath]
processHtmlFiles dir commentsMap = do
  exists <- doesDirectoryExist dir
  case exists of
    False -> pure []
    True  -> do
      entries <- listDirectory dir
      let htmlFiles = filter (\f -> T.isSuffixOf ".html" (T.pack f)) entries
      fmap (mapMaybe id) $ traverse (processOneFile dir commentsMap) htmlFiles

processOneFile :: FilePath -> CommentsMap -> FilePath -> IO (Maybe FilePath)
processOneFile dir commentsMap filename = do
  let filePath = dir </> filename
  content <- TIO.readFile filePath
  let updated = injectStaticComments content commentsMap
  if updated == content
    then pure Nothing
    else do
      TIO.writeFile filePath updated
      pure (Just filePath)
