module Automation.Scheduler
  ( TaskId (..)
  , ScheduleEntry (..)
  , BlogSeriesRunConfig (..)
  , staticSchedule
  , buildSchedule
  , buildBlogSeriesRunConfigs
  , validTaskIds
  , taskIdToText
  , taskIdFromText
  , nowPacificHour
  , getScheduledTasks
  , isValidTaskId
  , isBlogSeries
  , extractSeriesId
  , blogPostExistsForToday
  , blogPostMatchesToday
  , findPostToRegenerate
  ) where

import Data.List.NonEmpty (NonEmpty)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Data.Time (getCurrentTime)
import GHC.Generics (Generic)
import System.Directory (doesDirectoryExist, listDirectory)
import System.FilePath (takeExtension, (</>))

import qualified Automation.Gemini as Gemini
import Automation.PacificTime (pacificHour)

data TaskId
  = BlogSeries Text
  | BackfillBlogImages
  | InternalLinking
  | SocialPosting
  | AiFiction
  | ReflectionTitle
  | DailyAnalytics
  | BookReports
  deriving (Show, Eq, Ord)

data ScheduleEntry = ScheduleEntry
  { taskId :: TaskId
  , hoursPacific :: [Int]
  , atOrAfter :: Bool
  } deriving (Generic, Show, Eq)

data BlogSeriesRunConfig = BlogSeriesRunConfig
  { seriesId          :: Text
  , modelChain        :: NonEmpty Gemini.Model
  , priorityUserEnvVar :: Text
  , searchGrounding   :: Bool
  } deriving (Generic, Show, Eq)

taskIdToText :: TaskId -> Text
taskIdToText = \case
  BlogSeries seriesId -> "blog-series:" <> seriesId
  BackfillBlogImages  -> "backfill-blog-images"
  InternalLinking     -> "internal-linking"
  SocialPosting       -> "social-posting"
  AiFiction           -> "ai-fiction"
  ReflectionTitle     -> "reflection-title"
  DailyAnalytics      -> "daily-analytics"
  BookReports         -> "book-reports"

staticTaskIds :: [TaskId]
staticTaskIds =
  [ BackfillBlogImages
  , InternalLinking
  , SocialPosting
  , AiFiction
  , ReflectionTitle
  , DailyAnalytics
  , BookReports
  ]

taskIdFromText :: [TaskId] -> Text -> Maybe TaskId
taskIdFromText dynamicIds = flip Map.lookup (textToTaskIdMap dynamicIds)

textToTaskIdMap :: [TaskId] -> Map Text TaskId
textToTaskIdMap dynamicIds =
  Map.fromList (fmap (\tid -> (taskIdToText tid, tid)) (staticTaskIds <> dynamicIds))

everyHour :: [Int]
everyHour = [0 .. 23]

staticSchedule :: [ScheduleEntry]
staticSchedule =
  [ ScheduleEntry AiFiction [22] True
  , ScheduleEntry ReflectionTitle [22] True
  , ScheduleEntry DailyAnalytics [1] True
  , ScheduleEntry BackfillBlogImages everyHour False
  , ScheduleEntry InternalLinking everyHour False
  , ScheduleEntry SocialPosting [0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22] False
  , ScheduleEntry BookReports [1] True
  ]

buildSchedule :: [ScheduleEntry] -> [ScheduleEntry]
buildSchedule dynamicEntries = dynamicEntries <> staticSchedule

buildBlogSeriesRunConfigs :: [BlogSeriesRunConfig] -> Map Text BlogSeriesRunConfig
buildBlogSeriesRunConfigs = Map.fromList . fmap (\config -> (seriesId config, config))

validTaskIds :: [ScheduleEntry] -> Set TaskId
validTaskIds = Set.fromList . fmap taskId

isBlogSeries :: TaskId -> Bool
isBlogSeries (BlogSeries _) = True
isBlogSeries _              = False

getScheduledTasks :: [ScheduleEntry] -> Int -> [TaskId]
getScheduledTasks fullSchedule hourPacific =
  fmap taskId (filter (isScheduled hourPacific) fullSchedule)

isScheduled :: Int -> ScheduleEntry -> Bool
isScheduled hourPacific ScheduleEntry{..}
  | atOrAfter || isBlogSeries taskId = any (hourPacific >=) hoursPacific
  | otherwise                        = hourPacific `elem` hoursPacific

isValidTaskId :: [ScheduleEntry] -> Text -> Bool
isValidTaskId fullSchedule t =
  maybe False (`Set.member` validTaskIds fullSchedule) (taskIdFromText (blogSeriesTaskIds fullSchedule) t)

blogSeriesTaskIds :: [ScheduleEntry] -> [TaskId]
blogSeriesTaskIds = filter isBlogSeries . fmap taskId

extractSeriesId :: TaskId -> Maybe Text
extractSeriesId = T.stripPrefix "blog-series:" . taskIdToText

nowPacificHour :: IO Int
nowPacificHour = pacificHour <$> getCurrentTime

blogPostMatchesToday :: Text -> [String] -> Bool
blogPostMatchesToday today =
  any (T.isPrefixOf today . T.pack)

blogPostExistsForToday :: FilePath -> Text -> IO Bool
blogPostExistsForToday seriesDir today = do
  exists <- doesDirectoryExist seriesDir
  if exists
    then blogPostMatchesToday today <$> listDirectory seriesDir
    else pure False

findPostToRegenerate :: FilePath -> Text -> IO (Maybe FilePath)
findPostToRegenerate seriesDir today = do
  exists <- doesDirectoryExist seriesDir
  if exists
    then do
      files <- listDirectory seriesDir
      findM isRegenerable (filter isTodayMarkdown files)
    else pure Nothing
  where
    isTodayMarkdown f =
      T.isPrefixOf today (T.pack f) && takeExtension f == ".md"
    isRegenerable f = do
      content <- TIO.readFile (seriesDir </> f)
      pure (hasRegenerateMarker content)

findM :: Monad m => (a -> m Bool) -> [a] -> m (Maybe a)
findM _ []     = pure Nothing
findM p (x:xs) = p x >>= \found -> if found then pure (Just x) else findM p xs

hasRegenerateMarker :: Text -> Bool
hasRegenerateMarker content =
  case extractFrontmatter content of
    Nothing -> False
    Just fm -> any isRegenerateLine (T.lines fm)

extractFrontmatter :: Text -> Maybe Text
extractFrontmatter content = do
  rest <- T.stripPrefix "---\n" content
  case T.breakOn "\n---" rest of
    (_, "")  -> Nothing
    (fm, _)  -> Just fm

isRegenerateLine :: Text -> Bool
isRegenerateLine line =
  case T.stripPrefix "regenerate_post:" line of
    Nothing   -> False
    Just rest -> T.strip rest == "true"
