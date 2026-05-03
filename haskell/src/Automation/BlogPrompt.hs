module Automation.BlogPrompt
  ( BlogContext (..)
  , CrossSeriesPost (..)
  , Slug (..)
  , DisplayTitle (..)
  , mkSlug
  , generateSlug
  , stripEmbedSections
  , buildBlogPrompt
  , filterCommentsAfterLastPost
  , assembleFrontmatter
  , buildDisplayTitle
  , sanitizeTitle
  , recapInstructions
  , buildCrossSeriesSection
  ) where

import Data.Char (isAsciiLower, isDigit)
import Data.List (findIndex)
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time
  ( Day
  , DayOfWeek (..)
  , LocalTime (..)
  , UTCTime
  , addDays
  , dayOfWeek
  , fromGregorian
  , toGregorian
  )
import Data.Time.Format.ISO8601 (iso8601ParseM)
import Text.Read (readMaybe)

import Automation.BlogComments (BlogComment)
import qualified Automation.BlogComments as Comments
import Automation.BlogPosts (BlogPost (..))
import Automation.BlogSeriesConfig (BlogSeriesConfig (..))

import Automation.Frontmatter (quoteYamlValue)
import Automation.PacificTime (formatDay, formatDayHuman, toPacificLocalTime)
import Automation.Text (isEmoji)
import Automation.Wikilink (buildBackLink)
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

-- | A post from another blog series, carrying metadata for prompt formatting.
data CrossSeriesPost = CrossSeriesPost
  { crossSeriesName :: Text
  , crossSeriesIcon :: Text
  , crossSeriesPost :: BlogPost
  } deriving (Show, Eq)

data BlogContext = BlogContext
  { series           :: BlogSeriesConfig
  , agentsMd         :: Text
  , previousPosts    :: [BlogPost]
  , comments         :: [BlogComment]
  , today            :: Day
  , crossSeriesPosts :: [CrossSeriesPost]
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
        if T.null (T.strip (agentsMd ctx))
          then defaultSystemPrompt
          else agentsMd ctx
      userPrompt = buildUserPrompt ctx
  in (systemPrompt, userPrompt)

filterCommentsAfterLastPost :: BlogSeriesConfig -> [BlogPost] -> [BlogComment] -> [BlogComment]
filterCommentsAfterLastPost _ [] comments = comments
filterCommentsAfterLastPost series (latestPost : _) comments =
  let postDay = fromMaybe (fromGregorian 2026 1 1) (parseDate (bpDate latestPost))
      cutoff = LocalTime postDay (scheduleTime series)
  in filter (commentAfterCutoff cutoff) comments

commentAfterCutoff :: LocalTime -> BlogComment -> Bool
commentAfterCutoff cutoff comment =
  case parseUtcTimestamp (Comments.createdAt comment) of
    Nothing      -> True
    Just utcTime -> toPacificLocalTime utcTime >= cutoff

parseUtcTimestamp :: Text -> Maybe UTCTime
parseUtcTimestamp = iso8601ParseM . T.unpack

buildDisplayTitle :: BlogSeriesConfig -> Day -> Text -> DisplayTitle
buildDisplayTitle series today title =
  DisplayTitle $ formatDay today <> " | " <> icon series <> " " <> title <> " " <> icon series

sanitizeTitle :: BlogSeriesConfig -> Text -> Text
sanitizeTitle series raw =
  T.strip $ stripTrailingIcon $ stripLeadingIcon $ stripDatePipe $ stripLeadingIcon $ T.strip raw
  where
    stripLeadingIcon t =
      maybe (T.stripStart t) T.stripStart
        (T.stripPrefix (icon series) (T.stripStart t))

    stripTrailingIcon t =
      maybe (T.stripEnd t) T.stripEnd
        (T.stripSuffix (icon series) (T.stripEnd t))

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
      url = baseUrl series <> "/" <> formatDay day <> "-" <> unSlug slug
  in T.intercalate "\n"
    [ "---"
    , "share: true"
    , "aliases:"
    , "  - " <> quoteYamlValue displayTitle
    , "title: " <> quoteYamlValue displayTitle
    , "URL: " <> quoteYamlValue url
    , "Author: " <> quoteYamlValue (author series)
    , "---"
    ]

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
buildUserPrompt BlogContext{..} =
  let header = "Today is " <> formatDayHuman today <> "."
        <> "\nWrite the next blog post for the " <> name series <> " series."
        <> "\nToday's date: " <> formatDay today
        <> "\n\nIMPORTANT: Your heading (# or ##) must contain ONLY the creative title."
        <> " Do not include dates, pipe separators, or the series icon emoji in your heading."
        <> " The system adds date and icon formatting automatically."
      postHistory = buildPostHistory series previousPosts
      crossSeriesContext = buildCrossSeriesSection crossSeriesPosts
      commentsSection = buildCommentsSection comments
      recap = recapInstructions today
  in T.intercalate "\n\n"
    $ filter (not . T.null)
      [ header
      , postHistory
      , crossSeriesContext
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

buildCrossSeriesSection :: [CrossSeriesPost] -> Text
buildCrossSeriesSection [] = ""
buildCrossSeriesSection posts =
  let formatted = fmap formatCrossSeriesPost posts
  in "## Today Across the Blog\n\n"
    <> "The following are the most recent posts from other blog series on this site. "
    <> "Each series has its own voice and perspective. Find connections, tensions, "
    <> "and emergent themes across these independent voices.\n\n"
    <> T.intercalate "\n\n---\n\n" formatted

formatCrossSeriesPost :: CrossSeriesPost -> Text
formatCrossSeriesPost CrossSeriesPost{..} =
  let body = stripEmbedSections (bpBody crossSeriesPost)
      excerpt = T.take 2000 body
  in "### " <> crossSeriesIcon <> " " <> crossSeriesName <> " — " <> bpTitle crossSeriesPost
    <> " (" <> bpDate crossSeriesPost <> ")\n\n" <> T.strip excerpt

formatComment :: BlogComment -> Text
formatComment c =
  let priority = if Comments.isPriority c then " ⭐" else ""
  in "**" <> Comments.author c <> "**" <> priority <> " (" <> Comments.createdAt c <> "):\n" <> Comments.body c

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
