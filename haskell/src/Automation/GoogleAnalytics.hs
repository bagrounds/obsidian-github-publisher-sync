module Automation.GoogleAnalytics
  ( AnalyticsSummary (..)
  , PageMetric (..)
  , AnalyticsReport (..)
  , analyticsSectionHeader
  , reflectionNeedsAnalytics
  , formatDuration
  , buildAnalyticsSection
  , applyAnalyticsSection
  , parseAnalyticsResponse
  , parseSummaryResponse
  , buildSummaryRequestBody
  , buildTopPagesRequestBody
  , analyticsReadonlyScope
  , analyticsApiEndpoint
  ) where

import Data.Text (Text)
import qualified Data.Text as T

import Automation.Platform (updatesSectionHeader)
import qualified Automation.Json as Json
import qualified Automation.Platforms.Bluesky as Bluesky
import qualified Automation.Platforms.Mastodon as Mastodon
import qualified Automation.Platforms.Twitter as Twitter

analyticsSectionHeader :: Text
analyticsSectionHeader = "## 📊 Google Analytics"

analyticsReadonlyScope :: Text
analyticsReadonlyScope = "https://www.googleapis.com/auth/analytics.readonly"

analyticsApiEndpoint :: Text -> Text
analyticsApiEndpoint propertyId =
  "https://analyticsdata.googleapis.com/v1beta/properties/" <> propertyId <> ":runReport"

data AnalyticsSummary = AnalyticsSummary
  { activeUsers :: Int
  , sessions :: Int
  , pageViews :: Int
  , newUsers :: Int
  , averageSessionDuration :: Double
  } deriving (Show, Eq)

data PageMetric = PageMetric
  { pagePath :: Text
  , pagePageViews :: Int
  } deriving (Show, Eq)

data AnalyticsReport = AnalyticsReport
  { reportSummary :: AnalyticsSummary
  , reportTopPages :: [PageMetric]
  } deriving (Show, Eq)

reflectionNeedsAnalytics :: Text -> Bool
reflectionNeedsAnalytics content = not (T.isInfixOf analyticsSectionHeader content)

formatDuration :: Double -> Text
formatDuration totalSeconds =
  let wholeSeconds = round totalSeconds :: Int
      minutes = wholeSeconds `div` 60
      seconds = wholeSeconds `mod` 60
      padded = if seconds < 10 then "0" <> T.pack (show seconds) else T.pack (show seconds)
  in T.pack (show minutes) <> "m " <> padded <> "s"

buildAnalyticsSection :: AnalyticsReport -> Text
buildAnalyticsSection report =
  let summary = reportSummary report
      summaryLines =
        [ analyticsSectionHeader
        , ""
        , "- 👥 Active Users: " <> T.pack (show (activeUsers summary))
        , "- 🔄 Sessions: " <> T.pack (show (sessions summary))
        , "- 📄 Page Views: " <> T.pack (show (pageViews summary))
        , "- 🆕 New Users: " <> T.pack (show (newUsers summary))
        , "- ⏱️ Avg Session: " <> formatDuration (averageSessionDuration summary)
        ]
      topPagesLines = case reportTopPages report of
        [] -> []
        pages ->
          [ ""
          , "### 🏆 Top Pages"
          , ""
          ] <> fmap formatPageMetric pages
  in T.intercalate "\n" (summaryLines <> topPagesLines)

formatPageMetric :: PageMetric -> Text
formatPageMetric metric =
  "- " <> pagePath metric <> " — " <> T.pack (show (pagePageViews metric)) <> " views"

embedHeaders :: [Text]
embedHeaders = [Twitter.sectionHeader, Bluesky.sectionHeader, Mastodon.sectionHeader]

applyAnalyticsSection :: Text -> AnalyticsReport -> Text
applyAnalyticsSection content report =
  let sectionBlock = buildAnalyticsSection report
  in if T.isInfixOf analyticsSectionHeader content
    then replaceExistingSection content sectionBlock
    else insertNewSection content sectionBlock

replaceExistingSection :: Text -> Text -> Text
replaceExistingSection content newSection =
  let (before, sectionStart) = T.breakOn analyticsSectionHeader content
      afterHeader = T.drop (T.length analyticsSectionHeader) sectionStart
      rest = case T.breakOn "\n## " afterHeader of
        (_, "") -> ""
        (_, remaining) -> remaining
  in T.stripEnd before <> "\n\n" <> newSection <> "\n\n" <> T.stripStart rest

insertNewSection :: Text -> Text -> Text
insertNewSection content sectionBlock =
  let trailingSections = updatesSectionHeader : embedHeaders
      indices = filter (>= 0) $ fmap (`indexOfHeader` content) trailingSections
  in case indices of
    [] -> T.stripEnd content <> "\n\n" <> sectionBlock <> "\n"
    _  ->
      let insertIdx = minimum indices
          before = T.stripEnd (T.take insertIdx content)
          after = T.drop insertIdx content
      in before <> "\n\n" <> sectionBlock <> "\n\n" <> after

indexOfHeader :: Text -> Text -> Int
indexOfHeader header body =
  case T.breakOn header body of
    (before, rest) | not (T.null rest) -> T.length before
    _ -> -1

buildSummaryRequestBody :: Text -> Json.Value
buildSummaryRequestBody date =
  Json.object
    [ "dateRanges" Json..= Json.Array
        [ Json.object
            [ "startDate" Json..= date
            , "endDate" Json..= date
            ]
        ]
    , "metrics" Json..= Json.Array
        [ Json.object ["name" Json..= ("activeUsers" :: Text)]
        , Json.object ["name" Json..= ("sessions" :: Text)]
        , Json.object ["name" Json..= ("screenPageViews" :: Text)]
        , Json.object ["name" Json..= ("newUsers" :: Text)]
        , Json.object ["name" Json..= ("averageSessionDuration" :: Text)]
        ]
    ]

buildTopPagesRequestBody :: Text -> Json.Value
buildTopPagesRequestBody date =
  Json.object
    [ "dateRanges" Json..= Json.Array
        [ Json.object
            [ "startDate" Json..= date
            , "endDate" Json..= date
            ]
        ]
    , "metrics" Json..= Json.Array
        [ Json.object ["name" Json..= ("screenPageViews" :: Text)]
        ]
    , "dimensions" Json..= Json.Array
        [ Json.object ["name" Json..= ("pagePath" :: Text)]
        ]
    , "orderBys" Json..= Json.Array
        [ Json.object
            [ "metric" Json..= Json.object
                [ "metricName" Json..= ("screenPageViews" :: Text)
                ]
            , "desc" Json..= True
            ]
        ]
    , "limit" Json..= (5 :: Int)
    ]

parseSummaryResponse :: Json.Value -> Either Text AnalyticsSummary
parseSummaryResponse value = do
  rows <- extractRows value
  case rows of
    (row : _) -> do
      metrics <- extractMetricValues row
      case metrics of
        [au, sess, pv, nu, dur] ->
          Right AnalyticsSummary
            { activeUsers = parseIntMetric au
            , sessions = parseIntMetric sess
            , pageViews = parseIntMetric pv
            , newUsers = parseIntMetric nu
            , averageSessionDuration = parseDoubleMetric dur
            }
        _ -> Left $ "Expected 5 metrics, got " <> T.pack (show (length metrics))
    [] -> Right AnalyticsSummary
      { activeUsers = 0
      , sessions = 0
      , pageViews = 0
      , newUsers = 0
      , averageSessionDuration = 0
      }

parseAnalyticsResponse :: Json.Value -> Either Text [PageMetric]
parseAnalyticsResponse value = do
  rows <- extractRows value
  traverse parsePageRow rows

parsePageRow :: Json.Value -> Either Text PageMetric
parsePageRow row = do
  dims <- extractDimensionValues row
  metrics <- extractMetricValues row
  case (dims, metrics) of
    (path : _, views : _) ->
      Right PageMetric
        { pagePath = path
        , pagePageViews = parseIntMetric views
        }
    _ -> Left "Missing dimension or metric in page row"

extractRows :: Json.Value -> Either Text [Json.Value]
extractRows value =
  mapLeft T.pack $ Json.withObject "response" (\obj -> do
    mRows <- obj Json..:? "rows"
    case mRows of
      Just (Json.Array rows) -> Right rows
      Just _                 -> Left "rows is not an array"
      Nothing                -> Right []) value

extractMetricValues :: Json.Value -> Either Text [Text]
extractMetricValues value =
  mapLeft T.pack $ Json.withObject "row" (\obj -> do
    metricsArray <- obj Json..: "metricValues"
    case metricsArray of
      Json.Array values -> traverse extractValue values
      _ -> Left "metricValues is not an array") value

extractDimensionValues :: Json.Value -> Either Text [Text]
extractDimensionValues value =
  mapLeft T.pack $ Json.withObject "row" (\obj -> do
    dimsArray <- obj Json..: "dimensionValues"
    case dimsArray of
      Json.Array values -> traverse extractValue values
      _ -> Left "dimensionValues is not an array") value

extractValue :: Json.Value -> Either String Text
extractValue = Json.withObject "metricValue" $ \obj ->
  obj Json..: "value"

mapLeft :: (a -> b) -> Either a c -> Either b c
mapLeft f (Left a) = Left (f a)
mapLeft _ (Right c) = Right c

parseIntMetric :: Text -> Int
parseIntMetric text =
  case reads (T.unpack text) of
    [(n, "")] -> n
    _         -> case reads (T.unpack text) of
      [(d, _)] -> round (d :: Double)
      _        -> 0

parseDoubleMetric :: Text -> Double
parseDoubleMetric text =
  case reads (T.unpack text) of
    [(d, "")] -> d
    _         -> 0
