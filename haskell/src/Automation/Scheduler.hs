module Automation.Scheduler
  ( TaskId (..)
  , ScheduleEntry (..)
  , BlogSeriesRunConfig (..)
  , schedule
  , blogSeriesRunConfigs
  , validTaskIds
  , taskIdToText
  , taskIdFromText
  , nowPacificHour
  , pacificHour
  , getScheduledTasks
  , isValidTaskId
  , extractSeriesId
  , blogPostExistsForToday
  , findPostToRegenerate
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Data.Time
  ( Day
  , DayOfWeek (..)
  , TimeZone (..)
  , UTCTime (..)
  , addDays
  , dayOfWeek
  , fromGregorian
  , getCurrentTime
  , localTimeOfDay
  , secondsToDiffTime
  , todHour
  , toGregorian
  , utcToLocalTime
  )
import GHC.Generics (Generic)
import System.Directory (doesDirectoryExist, listDirectory)
import System.FilePath (takeExtension, (</>))

data TaskId
  = BlogSeriesChickieLoo
  | BlogSeriesAutoBlogZero
  | BlogSeriesSystemsForPublicGood
  | BackfillBlogImages
  | InternalLinking
  | SocialPosting
  | AiFiction
  | ReflectionTitle
  deriving (Show, Eq, Ord, Bounded, Enum)

data ScheduleEntry = ScheduleEntry
  { seTaskId :: TaskId
  , seHoursPacific :: [Int]
  , seAtOrAfter :: Bool
  } deriving (Generic, Show, Eq)

data BlogSeriesRunConfig = BlogSeriesRunConfig
  { bsrcSeriesId :: Text
  , bsrcModelChain :: [Text]
  , bsrcPriorityUserEnvVar :: Text
  } deriving (Generic, Show, Eq)

taskIdToText :: TaskId -> Text
taskIdToText = \case
  BlogSeriesChickieLoo           -> "blog-series:chickie-loo"
  BlogSeriesAutoBlogZero         -> "blog-series:auto-blog-zero"
  BlogSeriesSystemsForPublicGood -> "blog-series:systems-for-public-good"
  BackfillBlogImages             -> "backfill-blog-images"
  InternalLinking                -> "internal-linking"
  SocialPosting                  -> "social-posting"
  AiFiction                      -> "ai-fiction"
  ReflectionTitle                -> "reflection-title"

taskIdFromText :: Text -> Maybe TaskId
taskIdFromText = flip Map.lookup textToTaskIdMap

textToTaskIdMap :: Map Text TaskId
textToTaskIdMap =
  Map.fromList [(taskIdToText tid, tid) | tid <- [minBound .. maxBound]]

everyHour :: [Int]
everyHour = [0 .. 23]

schedule :: [ScheduleEntry]
schedule =
  [ ScheduleEntry BlogSeriesChickieLoo [7] False
  , ScheduleEntry BlogSeriesAutoBlogZero [8] False
  , ScheduleEntry BlogSeriesSystemsForPublicGood [9] False
  , ScheduleEntry AiFiction [22] True
  , ScheduleEntry ReflectionTitle [22] True
  , ScheduleEntry BackfillBlogImages everyHour False
  , ScheduleEntry InternalLinking everyHour False
  , ScheduleEntry SocialPosting [0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22] False
  ]

blogSeriesRunConfigs :: Map Text BlogSeriesRunConfig
blogSeriesRunConfigs = Map.fromList
  [ ("chickie-loo", BlogSeriesRunConfig
      "chickie-loo"
      ["gemini-3.1-flash-lite-preview", "gemini-3-flash-preview"]
      "CHICKIE_LOO_PRIORITY_USER")
  , ("auto-blog-zero", BlogSeriesRunConfig
      "auto-blog-zero"
      ["gemini-3.1-flash-lite-preview", "gemini-3-flash-preview"]
      "AUTO_BLOG_ZERO_PRIORITY_USER")
  , ("systems-for-public-good", BlogSeriesRunConfig
      "systems-for-public-good"
      ["gemini-2.5-flash", "gemini-2.5-flash-lite", "gemini-3.1-flash-lite-preview"]
      "SYSTEMS_FOR_PUBLIC_GOOD_PRIORITY_USER")
  ]

validTaskIds :: Set TaskId
validTaskIds = Set.fromList (fmap seTaskId schedule)

isBlogSeries :: TaskId -> Bool
isBlogSeries = \case
  BlogSeriesChickieLoo           -> True
  BlogSeriesAutoBlogZero         -> True
  BlogSeriesSystemsForPublicGood -> True
  _                              -> False

getScheduledTasks :: Int -> [TaskId]
getScheduledTasks hourPacific =
  fmap seTaskId (filter (isScheduled hourPacific) schedule)

isScheduled :: Int -> ScheduleEntry -> Bool
isScheduled hourPacific ScheduleEntry{..}
  | seAtOrAfter || isBlogSeries seTaskId = any (hourPacific >=) seHoursPacific
  | otherwise                            = hourPacific `elem` seHoursPacific

isValidTaskId :: Text -> Bool
isValidTaskId t = maybe False (`Set.member` validTaskIds) (taskIdFromText t)

extractSeriesId :: TaskId -> Maybe Text
extractSeriesId = T.stripPrefix "blog-series:" . taskIdToText

nowPacificHour :: IO Int
nowPacificHour = pacificHour <$> getCurrentTime

pacificHour :: UTCTime -> Int
pacificHour utcNow =
  todHour (localTimeOfDay (utcToLocalTime (pacificTimeZone utcNow) utcNow))

pacificTimeZone :: UTCTime -> TimeZone
pacificTimeZone utcNow
  | isPacificDST utcNow = TimeZone (-420) True "PDT"
  | otherwise            = TimeZone (-480) False "PST"

isPacificDST :: UTCTime -> Bool
isPacificDST utcNow =
  let (year, _, _) = toGregorian (utctDay utcNow)
      dstStart = UTCTime (nthSundayOf 2 year 3) (secondsToDiffTime (10 * 3600))
      dstEnd   = UTCTime (nthSundayOf 1 year 11) (secondsToDiffTime (9 * 3600))
  in utcNow >= dstStart && utcNow < dstEnd

nthSundayOf :: Int -> Integer -> Int -> Day
nthSundayOf n year month =
  let first = fromGregorian year month 1
      offset = daysUntilSunday (dayOfWeek first)
  in addDays (fromIntegral (offset + 7 * (n - 1))) first

daysUntilSunday :: DayOfWeek -> Int
daysUntilSunday = \case
  Sunday    -> 0
  Monday    -> 6
  Tuesday   -> 5
  Wednesday -> 4
  Thursday  -> 3
  Friday    -> 2
  Saturday  -> 1

blogPostExistsForToday :: FilePath -> Text -> IO Bool
blogPostExistsForToday seriesDir today = do
  exists <- doesDirectoryExist seriesDir
  if exists
    then any (T.isPrefixOf today . T.pack) <$> listDirectory seriesDir
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
