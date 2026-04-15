module Automation.ContextQuery
  ( ContextScope (..)
  , SelectionStrategy (..)
  , ContextQuery (..)
  , CrossSeriesPost (..)
  , SeriesInfo (..)
  , defaultContextQueries
  , evaluateQueries
  , parseScope
  , scopeToText
  ) where

import Data.List (sortOn)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Ord (Down (..))
import Data.Text (Text)
import qualified Data.Text as T

import Automation.BlogPosts (BlogPost (..), readSeriesPosts)
import Automation.Json (FromValue (..), withObject, (.:), (.:?))
import System.FilePath ((</>))

-- | Which series to draw context posts from.
data ContextScope
  = Self
  | OtherSeries
  | AllSeries
  | SpecificSeries Text
  deriving (Show, Eq)

-- | How to select posts within the scope.
data SelectionStrategy
  = Latest Int
  | LatestPerSeries Int
  deriving (Show, Eq)

-- | A declarative query specifying which posts to include in generation context.
data ContextQuery = ContextQuery
  { cqScope     :: ContextScope
  , cqSelection :: SelectionStrategy
  } deriving (Show, Eq)

-- | A post from another blog series, providing cross-series context.
data CrossSeriesPost = CrossSeriesPost
  { cspSeriesName :: Text
  , cspSeriesIcon :: Text
  , cspPost       :: BlogPost
  } deriving (Show, Eq)

-- | Minimal series metadata needed by the query engine.
data SeriesInfo = SeriesInfo
  { siId   :: Text
  , siName :: Text
  , siIcon :: Text
  } deriving (Show, Eq)

-- | The default context queries when none are specified in the JSON config.
-- Reads up to 7 most recent posts from the current series.
defaultContextQueries :: [ContextQuery]
defaultContextQueries = [ContextQuery Self (Latest 7)]

parseScope :: Text -> Either String ContextScope
parseScope "self" = Right Self
parseScope "others" = Right OtherSeries
parseScope "all" = Right AllSeries
parseScope scopeText = case T.stripPrefix "series:" scopeText of
  Just seriesId | not (T.null seriesId) -> Right (SpecificSeries seriesId)
  _ -> Left $ "Invalid scope: " <> T.unpack scopeText <> ". Expected: self, others, all, or series:<id>"

scopeToText :: ContextScope -> Text
scopeToText Self = "self"
scopeToText OtherSeries = "others"
scopeToText AllSeries = "all"
scopeToText (SpecificSeries seriesId) = "series:" <> seriesId

instance FromValue ContextQuery where
  fromValue = withObject "context query" $ \obj -> do
    scopeText <- obj .: "from"
    scope <- parseScope scopeText
    maybeLatest <- obj .:? "latest"
    maybePerSeries <- obj .:? "latestPerSeries"
    selection <- case (maybeLatest :: Maybe Int, maybePerSeries :: Maybe Int) of
      (Just count, Nothing)  -> Right (Latest count)
      (Nothing, Just count)  -> Right (LatestPerSeries count)
      (Just _, Just _)       -> Left "Specify exactly one of 'latest' or 'latestPerSeries', not both"
      (Nothing, Nothing)     -> Left "Must specify either 'latest' or 'latestPerSeries'"
    pure ContextQuery { cqScope = scope, cqSelection = selection }

-- | Evaluate a list of context queries against the content directory.
-- Returns self posts (for Recent Posts section) and cross-series posts (for cross-series section).
evaluateQueries
  :: Text                    -- ^ Current series ID
  -> FilePath                -- ^ Content root directory
  -> Map Text SeriesInfo     -- ^ All series info (keyed by series ID)
  -> [ContextQuery]          -- ^ Queries to evaluate
  -> IO ([BlogPost], [CrossSeriesPost])
evaluateQueries currentSeriesId contentRoot seriesInfoMap queries = do
  results <- traverse (evaluateSingleQuery currentSeriesId contentRoot seriesInfoMap) queries
  let selfPosts = concatMap fst results
      crossPosts = concatMap snd results
  pure (selfPosts, crossPosts)

evaluateSingleQuery
  :: Text
  -> FilePath
  -> Map Text SeriesInfo
  -> ContextQuery
  -> IO ([BlogPost], [CrossSeriesPost])
evaluateSingleQuery currentSeriesId contentRoot seriesInfoMap (ContextQuery scope selection) =
  case scope of
    Self ->
      readFromSelf currentSeriesId contentRoot selection

    OtherSeries ->
      readFromOthers currentSeriesId contentRoot seriesInfoMap selection

    AllSeries ->
      readFromAll currentSeriesId contentRoot seriesInfoMap selection

    SpecificSeries targetId ->
      readFromSpecific currentSeriesId contentRoot seriesInfoMap targetId selection

readFromSelf :: Text -> FilePath -> SelectionStrategy -> IO ([BlogPost], [CrossSeriesPost])
readFromSelf seriesId contentRoot selection = do
  let seriesDir = contentRoot </> T.unpack seriesId
  posts <- readSeriesPosts seriesDir
  pure (applyLimit selection posts, [])

readFromOthers
  :: Text -> FilePath -> Map Text SeriesInfo -> SelectionStrategy
  -> IO ([BlogPost], [CrossSeriesPost])
readFromOthers currentSeriesId contentRoot seriesInfoMap selection = do
  let otherInfos = Map.elems (Map.delete currentSeriesId seriesInfoMap)
  readCrossSeriesWithStrategy contentRoot otherInfos selection

readFromAll
  :: Text -> FilePath -> Map Text SeriesInfo -> SelectionStrategy
  -> IO ([BlogPost], [CrossSeriesPost])
readFromAll currentSeriesId contentRoot seriesInfoMap selection = do
  selfResult <- readFromSelf currentSeriesId contentRoot selection
  let otherInfos = Map.elems (Map.delete currentSeriesId seriesInfoMap)
  othersResult <- readCrossSeriesWithStrategy contentRoot otherInfos selection
  pure (fst selfResult, snd othersResult)

readFromSpecific
  :: Text -> FilePath -> Map Text SeriesInfo -> Text -> SelectionStrategy
  -> IO ([BlogPost], [CrossSeriesPost])
readFromSpecific currentSeriesId contentRoot seriesInfoMap targetId selection
  | targetId == currentSeriesId =
      readFromSelf currentSeriesId contentRoot selection
  | otherwise =
      case Map.lookup targetId seriesInfoMap of
        Nothing -> pure ([], [])
        Just info -> readCrossSeriesWithStrategy contentRoot [info] selection

readCrossSeriesWithStrategy
  :: FilePath -> [SeriesInfo] -> SelectionStrategy
  -> IO ([BlogPost], [CrossSeriesPost])
readCrossSeriesWithStrategy contentRoot infos selection =
  case selection of
    LatestPerSeries count -> do
      crossPosts <- concat <$> traverse (readLatestFromSeries contentRoot count) infos
      pure ([], crossPosts)
    Latest count -> do
      allCrossPosts <- concat <$> traverse (readAllFromSeries contentRoot) infos
      let sorted = sortOn (Down . bpFilename . cspPost) allCrossPosts
      pure ([], take count sorted)

readLatestFromSeries :: FilePath -> Int -> SeriesInfo -> IO [CrossSeriesPost]
readLatestFromSeries contentRoot count info = do
  let seriesDir = contentRoot </> T.unpack (siId info)
  posts <- readSeriesPosts seriesDir
  pure $ fmap (toCrossSeriesPost info) (take count posts)

readAllFromSeries :: FilePath -> SeriesInfo -> IO [CrossSeriesPost]
readAllFromSeries contentRoot info = do
  let seriesDir = contentRoot </> T.unpack (siId info)
  posts <- readSeriesPosts seriesDir
  pure $ fmap (toCrossSeriesPost info) posts

toCrossSeriesPost :: SeriesInfo -> BlogPost -> CrossSeriesPost
toCrossSeriesPost info post = CrossSeriesPost
  { cspSeriesName = siName info
  , cspSeriesIcon = siIcon info
  , cspPost = post
  }

applyLimit :: SelectionStrategy -> [BlogPost] -> [BlogPost]
applyLimit (Latest count) = take count
applyLimit (LatestPerSeries count) = take count
