module Automation.ContextQuery
  ( ContextQuery (..)
  , WhereCondition (..)
  , WhereOperator (..)
  , Field (..)
  , OrderBy (..)
  , SortDirection (..)
  , CrossSeriesPost (..)
  , defaultContextQueries
  , evaluateQuery
  , evaluateQueries
  , parseOrderBy
  , orderByToText
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
  { wcField    :: Field
  , wcOperator :: WhereOperator
  , wcValue    :: Text
  } deriving (Show, Eq)

-- | A declarative, SQL-like query specifying which posts to include in generation context.
--
-- Translates to: SELECT posts FROM directories WHERE conditions ORDER BY field LIMIT n
data ContextQuery = ContextQuery
  { cqFrom           :: [Text]             -- ^ Content directories to read from (relative to content root)
  , cqWhere          :: [WhereCondition]   -- ^ Filter conditions (all must match)
  , cqOrderBy        :: OrderBy            -- ^ Sort order (default: filename DESC)
  , cqLimit          :: Maybe Int          -- ^ Global limit across all sources
  , cqLimitPerSource :: Maybe Int          -- ^ Per-source-directory limit
  } deriving (Show, Eq)

-- | A post from another blog series, providing cross-series context.
data CrossSeriesPost = CrossSeriesPost
  { cspSeriesName :: Text
  , cspSeriesIcon :: Text
  , cspPost       :: BlogPost
  } deriving (Show, Eq)

-- | Default context queries when none are specified.
-- Reads up to 7 most recent posts from the series' own directory.
defaultContextQueries :: Text -> [ContextQuery]
defaultContextQueries seriesId =
  [ ContextQuery
      { cqFrom = [seriesId]
      , cqWhere = []
      , cqOrderBy = OrderBy Filename Descending
      , cqLimit = Just 7
      , cqLimitPerSource = Nothing
      }
  ]

-- | Parse an ORDER BY string like "filename DESC" or "date ASC".
parseOrderBy :: Text -> Either String OrderBy
parseOrderBy raw =
  case T.words (T.strip raw) of
    [fieldText, directionText] -> do
      field <- parseField fieldText
      direction <- parseDirection directionText
      pure (OrderBy field direction)
    [fieldText] -> do
      field <- parseField fieldText
      pure (OrderBy field Descending)
    _ -> Left $ "Invalid orderBy: " <> T.unpack raw <> ". Expected: <field> [ASC|DESC]"

orderByToText :: OrderBy -> Text
orderByToText (OrderBy field direction) = fieldToText field <> " " <> directionToText direction

parseField :: Text -> Either String Field
parseField "filename" = Right Filename
parseField "date"     = Right Date
parseField "title"    = Right Title
parseField other      = Left $ "Unknown field: " <> T.unpack other <> ". Expected: filename, date, or title"

fieldToText :: Field -> Text
fieldToText Filename = "filename"
fieldToText Date = "date"
fieldToText Title = "title"

parseDirection :: Text -> Either String SortDirection
parseDirection directionText = case T.toUpper directionText of
  "ASC"  -> Right Ascending
  "DESC" -> Right Descending
  _      -> Left $ "Unknown direction: " <> T.unpack directionText <> ". Expected: ASC or DESC"

directionToText :: SortDirection -> Text
directionToText Ascending = "ASC"
directionToText Descending = "DESC"

parseWhereOperator :: Text -> Either String WhereOperator
parseWhereOperator ">=" = Right GreaterOrEqual
parseWhereOperator "<=" = Right LessOrEqual
parseWhereOperator "contains" = Right Contains
parseWhereOperator other = Left $ "Unknown operator: " <> T.unpack other <> ". Expected: >=, <=, or contains"

instance FromValue WhereCondition where
  fromValue = withObject "where condition" $ \obj -> do
    fieldText <- obj .: "field"
    field <- parseField fieldText
    operatorText <- obj .: "operator"
    operator <- parseWhereOperator operatorText
    value <- obj .: "value"
    pure WhereCondition { wcField = field, wcOperator = operator, wcValue = value }

instance FromValue ContextQuery where
  fromValue = withObject "context query" $ \obj -> do
    from <- obj .: "from"
    whereConditions <- fmap (fromMaybe []) (obj .:? "where")
    maybeOrderByText <- obj .:? "orderBy"
    orderBy <- case (maybeOrderByText :: Maybe Text) of
      Nothing -> Right (OrderBy Filename Descending)
      Just raw -> parseOrderBy raw
    limit <- obj .:? "limit"
    limitPerSource <- obj .:? "limitPerSource"
    pure ContextQuery
      { cqFrom = from
      , cqWhere = whereConditions
      , cqOrderBy = orderBy
      , cqLimit = limit
      , cqLimitPerSource = limitPerSource
      }

-- | Tagged result: which source directory a post came from.
data TaggedPost = TaggedPost
  { tpSourceDirectory :: Text
  , tpPost            :: BlogPost
  }

-- | Evaluate a single context query against the content directory.
evaluateQuery :: FilePath -> ContextQuery -> IO [TaggedPost]
evaluateQuery contentRoot query = do
  tagged <- concat <$> traverse (readFromDirectory contentRoot (cqLimitPerSource query)) (cqFrom query)
  let filtered = filter (matchesAllConditions (cqWhere query) . tpPost) tagged
      sorted = sortTaggedPosts (cqOrderBy query) filtered
  pure $ applyGlobalLimit (cqLimit query) sorted

-- | Evaluate multiple context queries, partitioning results into self posts and cross-series posts.
-- Posts from the current series directory are self posts; all others are cross-series posts.
evaluateQueries
  :: Text                          -- ^ Current series ID (used to partition self vs cross)
  -> FilePath                      -- ^ Content root directory
  -> [(Text, Text, Text)]          -- ^ Series metadata: (id, name, icon) for cross-series annotation
  -> [ContextQuery]                -- ^ Queries to evaluate
  -> IO ([BlogPost], [CrossSeriesPost])
evaluateQueries currentSeriesId contentRoot seriesMetadata queries = do
  allTagged <- concat <$> traverse (evaluateQuery contentRoot) queries
  let (selfTagged, crossTagged) = partitionBySource currentSeriesId allTagged
      selfPosts = fmap tpPost selfTagged
      crossPosts = fmap (tagAsCrossPost seriesMetadata) crossTagged
  pure (selfPosts, crossPosts)

partitionBySource :: Text -> [TaggedPost] -> ([TaggedPost], [TaggedPost])
partitionBySource currentSeriesId = foldr partition ([], [])
  where
    partition tagged (selfs, crosses)
      | tpSourceDirectory tagged == currentSeriesId = (tagged : selfs, crosses)
      | otherwise = (selfs, tagged : crosses)

tagAsCrossPost :: [(Text, Text, Text)] -> TaggedPost -> CrossSeriesPost
tagAsCrossPost metadata tagged =
  let sourceId = tpSourceDirectory tagged
      (name, icon) = lookupSeriesMetadata sourceId metadata
  in CrossSeriesPost
    { cspSeriesName = name
    , cspSeriesIcon = icon
    , cspPost = tpPost tagged
    }

lookupSeriesMetadata :: Text -> [(Text, Text, Text)] -> (Text, Text)
lookupSeriesMetadata sourceId = go
  where
    go [] = (sourceId, "📁")
    go ((seriesId, name, icon) : rest)
      | seriesId == sourceId = (name, icon)
      | otherwise = go rest

readFromDirectory :: FilePath -> Maybe Int -> Text -> IO [TaggedPost]
readFromDirectory contentRoot maybePerSourceLimit directory = do
  let dirPath = contentRoot </> T.unpack directory
  posts <- readSeriesPosts dirPath
  let limited = maybe posts (`take` posts) maybePerSourceLimit
  pure $ fmap (TaggedPost directory) limited

matchesAllConditions :: [WhereCondition] -> BlogPost -> Bool
matchesAllConditions conditions post = all (`matchesCondition` post) conditions

matchesCondition :: WhereCondition -> BlogPost -> Bool
matchesCondition WhereCondition{..} post =
  let fieldValue = extractField wcField post
  in applyOperator wcOperator wcValue fieldValue

extractField :: Field -> BlogPost -> Text
extractField Filename = bpFilename
extractField Date = bpDate
extractField Title = bpTitle

applyOperator :: WhereOperator -> Text -> Text -> Bool
applyOperator GreaterOrEqual threshold actual = actual >= threshold
applyOperator LessOrEqual threshold actual = actual <= threshold
applyOperator Contains needle actual = T.isInfixOf (T.toLower needle) (T.toLower actual)

sortTaggedPosts :: OrderBy -> [TaggedPost] -> [TaggedPost]
sortTaggedPosts (OrderBy field Ascending) = sortOn (extractField field . tpPost)
sortTaggedPosts (OrderBy field Descending) = sortOn (Down . extractField field . tpPost)

applyGlobalLimit :: Maybe Int -> [TaggedPost] -> [TaggedPost]
applyGlobalLimit Nothing = id
applyGlobalLimit (Just count) = take count
