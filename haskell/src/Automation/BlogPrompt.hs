module Automation.BlogPrompt
  ( BlogContext (..)
  , Slug (..)
  , DisplayTitle (..)
  , mkSlug
  , generateSlug
  , formatDay
  , stripEmbedSections
  , buildBlogPrompt
  , filterCommentsAfterLastPost
  , buildBackLink
  , buildForwardLink
  , assembleFrontmatter
  , buildDisplayTitle
  , sanitizeTitle
  , todayPacificDay
  , recapInstructions
  ) where

import Data.Char (isAsciiLower, isDigit)
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
import Automation.Frontmatter (quoteYamlValue)
import qualified Automation.Platforms.Bluesky as Bluesky
import qualified Automation.Platforms.Mastodon as Mastodon
import qualified Automation.Platforms.Twitter as Twitter

-- | A validated URL slug: lowercase, alphanumeric + hyphens, no leading/trailing hyphens.
newtype Slug = Slug { unSlug :: Text } deriving (Show, Eq)

-- | A fully constructed display title: "YYYY-MM-DD | icon Title icon".
newtype DisplayTitle = DisplayTitle { unDisplayTitle :: Text } deriving (Show, Eq)

mkSlug :: Text -> Either Text Slug
mkSlug t
  | T.null t = Left "Empty slug"
  | T.any (\c -> c == ' ' || c == '\n') t = Left ("Slug contains whitespace: " <> t)
  | T.head t == '-' || T.last t == '-' = Left ("Slug has leading/trailing hyphens: " <> t)
  | otherwise = Right (Slug t)

data BlogContext = BlogContext
  { bcxSeries        :: BlogSeriesConfig
  , bcxAgentsMd      :: Text
  , bcxPreviousPosts :: [BlogPost]
  , bcxComments      :: [BlogComment]
  , bcxToday         :: Day
  } deriving (Show, Eq)

stripEmbedSections :: Text -> Text
stripEmbedSections content =
  let embedHeaders = [Twitter.sectionHeader, Bluesky.sectionHeader, Mastodon.sectionHeader]
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

buildDisplayTitle :: BlogSeriesConfig -> Day -> Text -> DisplayTitle
buildDisplayTitle series today title =
  DisplayTitle $ formatDay today <> " | " <> bscIcon series <> " " <> title <> " " <> bscIcon series

sanitizeTitle :: BlogSeriesConfig -> Text -> Text
sanitizeTitle series raw =
  T.strip $ stripTrailingIcon $ stripLeadingIcon $ stripDatePipe $ stripLeadingIcon $ T.strip raw
  where
    icon = bscIcon series

    stripLeadingIcon t =
      maybe (T.stripStart t) T.stripStart
        (T.stripPrefix icon (T.stripStart t))

    stripTrailingIcon t =
      maybe (T.stripEnd t) T.stripEnd
        (T.stripSuffix icon (T.stripEnd t))

    stripDatePipe t =
      let s = T.stripStart t
      in case parseDate (T.take 10 s) of
        Just _ ->
          let afterDate = T.drop 10 s
              tryStrip = T.stripPrefix " | " afterDate
                     >>= Just . T.stripStart
          in fromMaybe (T.stripStart afterDate) tryStrip
        Nothing -> s

assembleFrontmatter :: BlogSeriesConfig -> Day -> Text -> Slug -> Text
assembleFrontmatter series day title slug =
  let (DisplayTitle displayTitle) = buildDisplayTitle series day title
      url = bscBaseUrl series <> "/" <> formatDay day <> "-" <> unSlug slug
  in T.intercalate "\n"
    [ "---"
    , "share: true"
    , "aliases:"
    , "  - " <> quoteYamlValue displayTitle
    , "title: " <> quoteYamlValue displayTitle
    , "URL: " <> quoteYamlValue url
    , "Author: " <> quoteYamlValue (bscAuthor series)
    , "---"
    ]

formatDay :: Day -> Text
formatDay = T.pack . formatTime defaultTimeLocale "%Y-%m-%d"

todayPacificDay :: IO Day
todayPacificDay = do
  utcNow <- getCurrentTime
  let tz = pacificTimeZone utcNow
      localTime = utcToLocalTime tz utcNow
  pure $ localDay localTime

recapInstructions :: Day -> Text
recapInstructions day =
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
        <> "\nToday's date: " <> formatDay today
        <> "\n\nIMPORTANT: Your heading (# or ##) must contain ONLY the creative title."
        <> " Do not include dates, pipe separators, or the series icon emoji in your heading."
        <> " The system adds date and icon formatting automatically."
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
      cleanTitle = sanitizeTitle series (bpTitle post)
  in "### " <> link <> " " <> cleanTitle <> " (" <> bpDate post <> ")\n\n" <> T.strip body

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

generateSlug :: Text -> Text
generateSlug title =
  let cleaned = T.filter (not . isEmoji) title
      lowered = T.toLower (T.strip cleaned)
      alphanum = T.map (\c -> if isAlphaNumOrSpace c then c else ' ') lowered
      dashed = T.intercalate "-" (T.words alphanum)
      trimmed = T.dropWhile (== '-') (T.dropWhileEnd (== '-') dashed)
  in trimmed
  where
    isAlphaNumOrSpace c = isAsciiLower c || isDigit c || c == ' ' || c == '-'
    isEmoji c =
      (c >= '\x1f300' && c <= '\x1faff')
        || (c >= '\x2600' && c <= '\x27bf')
        || (c >= '\x200d' && c <= '\x200d')
        || c == '\xfe0f'
        || (c >= '\x2300' && c <= '\x23ff')
        || (c >= '\x2702' && c <= '\x27b0')
