module Automation.ContextQuery
  ( ContextQuery (..)
  , WhereCondition (..)
  , WhereOperator (..)
  , Field (..)
  , OrderBy (..)
  , SortDirection (..)
  , ContextPost (..)
  , defaultContextQueries
  , evaluateQuery
  , evaluateQueries
  , fieldFromText
  , fieldToText
  ) where

import Data.List (sortOn)
import Data.Maybe (fromMaybe)
import Data.Ord (Down (..))
import Data.Text (Text)
import qualified Data.Text as T

import Automation.BlogPosts (BlogPost (..), readSeriesPosts)
import Automation.Json (FromValue (..), withObject, (.:), (.:?))
import System.FilePath ((</>))

-- | Field name used in ORDER BY and WHERE clauses.
data Field = Filename | Date | Title
  deriving (Show, Eq)

-- | Direction for sorting query results.
data SortDirection = Ascending | Descending
  deriving (Show, Eq)

-- | Sorting specification combining a field and direction.
data OrderBy = OrderBy Field SortDirection
  deriving (Show, Eq)

-- | Comparison operator for WHERE conditions.
data WhereOperator = GreaterOrEqual | LessOrEqual | Contains
  deriving (Show, Eq)

-- | A single filter condition: field operator value.
data WhereCondition = WhereCondition
  { field    :: Field
  , operator :: WhereOperator
  , value    :: Text
  } deriving (Show, Eq)

-- | A declarative, SQL-like query specifying which posts to include in generation context.
--
-- Translates to: SELECT posts FROM directories WHERE conditions ORDER BY field LIMIT n
data ContextQuery = ContextQuery
  { directories    :: [Text]             -- ^ Content directories to read from (relative to content root)
  , conditions     :: [WhereCondition]   -- ^ Filter conditions (all must match)
  , orderBy        :: OrderBy            -- ^ Sort order (default: filename DESC)
  , limit          :: Maybe Int          -- ^ Global limit across all sources
  , limitPerSource :: Maybe Int          -- ^ Per-source-directory limit
  } deriving (Show, Eq)

-- | A post returned by the query engine, tagged with its source directory.
data ContextPost = ContextPost
  { sourceDirectory :: Text
  , post            :: BlogPost
  } deriving (Show, Eq)

-- | Default context queries when none are specified.
-- Reads up to 7 most recent posts from the series' own directory.
defaultContextQueries :: Text -> [ContextQuery]
defaultContextQueries seriesId =
  [ ContextQuery
      { directories = [seriesId]
      , conditions = []
      , orderBy = OrderBy Filename Descending
      , limit = Just 7
      , limitPerSource = Nothing
      }
  ]

fieldFromText :: Text -> Either String Field
fieldFromText "filename" = Right Filename
fieldFromText "date"     = Right Date
fieldFromText "title"    = Right Title
fieldFromText other      = Left $ "Unknown field: " <> T.unpack other <> ". Expected: filename, date, or title"

fieldToText :: Field -> Text
fieldToText Filename = "filename"
fieldToText Date = "date"
fieldToText Title = "title"

parseWhereOperator :: Text -> Either String WhereOperator
parseWhereOperator ">=" = Right GreaterOrEqual
parseWhereOperator "<=" = Right LessOrEqual
parseWhereOperator "contains" = Right Contains
parseWhereOperator other = Left $ "Unknown operator: " <> T.unpack other <> ". Expected: >=, <=, or contains"

instance FromValue WhereCondition where
  fromValue = withObject "where condition" $ \obj -> do
    fieldText <- obj .: "field"
    parsedField <- fieldFromText fieldText
    operatorText <- obj .: "operator"
    parsedOperator <- parseWhereOperator operatorText
    parsedValue <- obj .: "value"
    pure WhereCondition { field = parsedField, operator = parsedOperator, value = parsedValue }

instance FromValue ContextQuery where
  fromValue = withObject "context query" $ \obj -> do
    parsedDirectories <- obj .: "from"
    parsedConditions <- fmap (fromMaybe []) (obj .:? "where")
    maybeOrderByField <- obj .:? "orderBy"
    parsedOrderBy <- case (maybeOrderByField :: Maybe Text) of
      Nothing -> Right (OrderBy Filename Descending)
      Just fieldText -> do
        parsedField <- fieldFromText fieldText
        pure (OrderBy parsedField Descending)
    maybeAscending <- obj .:? "ascending"
    let finalOrderBy = case (maybeAscending :: Maybe Bool) of
          Just True -> case parsedOrderBy of
            OrderBy parsedField _ -> OrderBy parsedField Ascending
          _ -> parsedOrderBy
    parsedLimit <- obj .:? "limit"
    parsedLimitPerSource <- obj .:? "limitPerSource"
    pure ContextQuery
      { directories = parsedDirectories
      , conditions = parsedConditions
      , orderBy = finalOrderBy
      , limit = parsedLimit
      , limitPerSource = parsedLimitPerSource
      }

-- | Evaluate a single context query against the content directory.
evaluateQuery :: FilePath -> ContextQuery -> IO [ContextPost]
evaluateQuery contentRoot query = do
  tagged <- concat <$> traverse (readFromDirectory contentRoot (limitPerSource query)) (directories query)
  let filtered = filter (matchesAllConditions (conditions query) . post) tagged
      sorted = sortContextPosts (orderBy query) filtered
  pure $ applyGlobalLimit (limit query) sorted

-- | Evaluate multiple context queries, returning all matching posts tagged with source info.
evaluateQueries :: FilePath -> [ContextQuery] -> IO [ContextPost]
evaluateQueries contentRoot queries =
  concat <$> traverse (evaluateQuery contentRoot) queries

readFromDirectory :: FilePath -> Maybe Int -> Text -> IO [ContextPost]
readFromDirectory contentRoot maybePerSourceLimit directory = do
  let dirPath = contentRoot </> T.unpack directory
  posts <- readSeriesPosts dirPath
  let limited = maybe posts (`take` posts) maybePerSourceLimit
  pure $ fmap (ContextPost directory) limited

matchesAllConditions :: [WhereCondition] -> BlogPost -> Bool
matchesAllConditions whereConditions blogPost = all (`matchesCondition` blogPost) whereConditions

matchesCondition :: WhereCondition -> BlogPost -> Bool
matchesCondition WhereCondition{..} blogPost =
  let fieldValue = extractField field blogPost
  in applyOperator operator value fieldValue

extractField :: Field -> BlogPost -> Text
extractField Filename = bpFilename
extractField Date = bpDate
extractField Title = bpTitle

applyOperator :: WhereOperator -> Text -> Text -> Bool
applyOperator GreaterOrEqual threshold actual = actual >= threshold
applyOperator LessOrEqual threshold actual = actual <= threshold
applyOperator Contains needle actual = T.isInfixOf (T.toLower needle) (T.toLower actual)

sortContextPosts :: OrderBy -> [ContextPost] -> [ContextPost]
sortContextPosts (OrderBy sortField Ascending) = sortOn (extractField sortField . post)
sortContextPosts (OrderBy sortField Descending) = sortOn (Down . extractField sortField . post)

applyGlobalLimit :: Maybe Int -> [ContextPost] -> [ContextPost]
applyGlobalLimit Nothing = id
applyGlobalLimit (Just count) = take count
