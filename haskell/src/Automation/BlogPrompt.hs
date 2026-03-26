module Automation.BlogPrompt
  ( BlogContext (..)
  , stripEmbedSections
  , buildBlogPrompt
  , filterCommentsAfterLastPost
  , buildBackLink
  , buildForwardLink
  , assembleFrontmatter
  , todayPacific
  , quoteForYaml
  , recapInstructions
  ) where

import Data.List (findIndex)
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time
  ( Day
  , DayOfWeek (..)
  , TimeZone (..)
  , UTCTime (..)
  , addDays
  , dayOfWeek
  , defaultTimeLocale
  , formatTime
  , fromGregorian
  , getCurrentTime
  , localDay
  , secondsToDiffTime
  , toGregorian
  , utcToLocalTime
  )
import Text.Read (readMaybe)

import Automation.BlogComments (BlogComment (..))
import Automation.BlogPosts (BlogPost (..))
import Automation.BlogSeriesConfig (BlogSeriesConfig (..))
import Automation.Types
  ( blueskySectionHeader
  , mastodonSectionHeader
  , tweetSectionHeader
  )

data BlogContext = BlogContext
  { bcxSeries        :: BlogSeriesConfig
  , bcxAgentsMd      :: Text
  , bcxPreviousPosts :: [BlogPost]
  , bcxComments      :: [BlogComment]
  , bcxToday         :: Text
  } deriving (Show, Eq)

stripEmbedSections :: Text -> Text
stripEmbedSections content =
  let embedHeaders = [tweetSectionHeader, blueskySectionHeader, mastodonSectionHeader]
      findPosition header =
        let (before, match) = T.breakOn header content
        in if T.null match then Nothing else Just (T.length before)
      positions = mapMaybe findPosition embedHeaders
  in case positions of
    [] -> T.strip content
    ps -> T.strip (T.take (minimum ps) content)

buildBlogPrompt :: BlogContext -> (Text, Text)
buildBlogPrompt ctx =
  let systemPrompt =
        if T.null (T.strip (bcxAgentsMd ctx))
          then defaultSystemPrompt
          else bcxAgentsMd ctx
      userPrompt = buildUserPrompt ctx
  in (systemPrompt, userPrompt)

filterCommentsAfterLastPost :: BlogSeriesConfig -> [BlogPost] -> [BlogComment] -> [BlogComment]
filterCommentsAfterLastPost _ [] comments = comments
filterCommentsAfterLastPost series (latestPost : _) comments =
  let cutoff = bpDate latestPost <> "T" <> bscPostTimeUtc series <> ":00Z"
  in filter (\c -> bcCreatedAt c >= cutoff) comments

buildBackLink :: BlogSeriesConfig -> Text -> Text
buildBackLink series filename =
  let slug = fromMaybe filename (T.stripSuffix ".md" filename)
  in "[[" <> bscId series <> "/" <> slug <> "|⏮️]]"

buildForwardLink :: BlogSeriesConfig -> Text -> Text
buildForwardLink series filename =
  let slug = fromMaybe filename (T.stripSuffix ".md" filename)
  in "[[" <> bscId series <> "/" <> slug <> "|⏭️]]"

assembleFrontmatter :: BlogSeriesConfig -> Text -> Text -> Text -> [Text] -> Text
assembleFrontmatter series title slug today tags =
  let url = bscBaseUrl series <> "/" <> slug
      tagLines = fmap (\tag -> "  - " <> tag) tags
  in T.intercalate "\n" $
    [ "---"
    , "share: true"
    , "aliases:"
    , "  - " <> quoteForYaml title
    , "title: " <> quoteForYaml title
    , "URL: " <> url
    , "Author: " <> bscAuthor series
    , "tags:"
    ] <> tagLines <>
    [ "date: " <> today
    , "---"
    ]

todayPacific :: IO Text
todayPacific = do
  utcNow <- getCurrentTime
  let tz = pacificTimeZone utcNow
      localTime = utcToLocalTime tz utcNow
      day = localDay localTime
  pure $ T.pack $ formatTime defaultTimeLocale "%Y-%m-%d" day

quoteForYaml :: Text -> Text
quoteForYaml t =
  let backslashEscaped = T.replace "\\" "\\\\" t
      quotesEscaped = T.replace "\"" "\\\"" backslashEscaped
  in "\"" <> quotesEscaped <> "\""

recapInstructions :: Text -> Text
recapInstructions dateStr =
  case parseDate dateStr of
    Nothing  -> ""
    Just day ->
      let dow = dayOfWeek day
          (_, month, dayNum) = toGregorian day
          nextDay = addDays 1 day
          (_, nextMonth, _) = toGregorian nextDay
          isSunday = dow == Sunday
          isLastDayOfMonth = nextMonth /= month
          isLastDayOfQuarter = isLastDayOfMonth && month `elem` [3, 6, 9, 12]
          isLastDayOfYear = month == 12 && dayNum == 31
          instructions = filter (not . T.null)
            [ if isSunday then weeklyRecap else ""
            , if isLastDayOfMonth then monthlyRecap else ""
            , if isLastDayOfQuarter then quarterlyRecap else ""
            , if isLastDayOfYear then yearlyRecap else ""
            ]
      in T.intercalate "\n\n" instructions

defaultSystemPrompt :: Text
defaultSystemPrompt = "You are a creative blog writer. Write engaging, thoughtful blog posts."

buildUserPrompt :: BlogContext -> Text
buildUserPrompt ctx =
  let series = bcxSeries ctx
      posts = bcxPreviousPosts ctx
      comments = bcxComments ctx
      today = bcxToday ctx
      header = "Write the next blog post for the " <> bscName series <> " series."
        <> "\nToday's date: " <> today
      postHistory = buildPostHistory series posts
      commentsSection = buildCommentsSection comments
      recap = recapInstructions today
  in T.intercalate "\n\n"
    $ filter (not . T.null)
      [ header
      , postHistory
      , commentsSection
      , recap
      ]

buildPostHistory :: BlogSeriesConfig -> [BlogPost] -> Text
buildPostHistory _ [] = ""
buildPostHistory series posts =
  let recentPosts = postsSinceLastRecap posts
      formatted = fmap (formatPost series) recentPosts
  in "## Recent Posts\n\n" <> T.intercalate "\n\n---\n\n" formatted

postsSinceLastRecap :: [BlogPost] -> [BlogPost]
postsSinceLastRecap posts =
  let capped = take 7 posts
  in case findIndex isRecapPost capped of
    Nothing -> capped
    Just i  -> take (i + 1) capped

isRecapPost :: BlogPost -> Bool
isRecapPost = T.isInfixOf "recap" . T.toLower . bpTitle

formatPost :: BlogSeriesConfig -> BlogPost -> Text
formatPost series post =
  let link = buildBackLink series (bpFilename post)
      body = stripEmbedSections (bpBody post)
  in "### " <> link <> " " <> bpTitle post <> " (" <> bpDate post <> ")\n\n" <> T.strip body

buildCommentsSection :: [BlogComment] -> Text
buildCommentsSection [] = ""
buildCommentsSection comments =
  let formatted = fmap formatComment comments
  in "## Reader Comments\n\n" <> T.intercalate "\n\n" formatted

formatComment :: BlogComment -> Text
formatComment c =
  let priority = if bcIsPriority c then " ⭐" else ""
  in "**" <> bcAuthor c <> "**" <> priority <> " (" <> bcCreatedAt c <> "):\n" <> bcBody c

parseDate :: Text -> Maybe Day
parseDate t =
  case T.splitOn "-" t of
    [yStr, mStr, dStr] ->
      fromGregorian
        <$> readMaybe (T.unpack yStr)
        <*> readMaybe (T.unpack mStr)
        <*> readMaybe (T.unpack dStr)
    _ -> Nothing

weeklyRecap :: Text
weeklyRecap =
  "📅 Today is Sunday. Please include a brief weekly recap section "
    <> "summarizing the key themes and developments from this week's posts."

monthlyRecap :: Text
monthlyRecap =
  "📆 Today is the last day of the month. Please include a monthly recap "
    <> "section summarizing the key themes and developments from this month."

quarterlyRecap :: Text
quarterlyRecap =
  "📊 Today is the last day of the quarter. Please include a quarterly recap "
    <> "section summarizing the key themes from the past three months."

yearlyRecap :: Text
yearlyRecap =
  "🎆 Today is the last day of the year. Please include a yearly recap "
    <> "section reflecting on the major themes and developments from the entire year."

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
