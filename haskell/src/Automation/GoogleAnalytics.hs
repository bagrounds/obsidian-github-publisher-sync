module Automation.GoogleAnalytics
  ( AnalyticsSummary (..)
  , PageMetric (..)
  , AnalyticsReport (..)
  , analyticsSectionHeader
  , reflectionNeedsAnalytics
  , formatDuration
  , formatPercentage
  , formatDecimal
  , buildAnalyticsSection
  , applyAnalyticsSection
  , parseAnalyticsResponse
  , parseSummaryResponse
  , buildSummaryRequestBody
  , buildTopPagesRequestBody
  , analyticsReadonlyScope
  , analyticsApiEndpoint
  , extractRowCount
  , checkForApiError
  , pathToWikilinkTarget
  , formatTableWikilink
  , escapeTablePipe
  ) where

import Data.Maybe (fromMaybe)
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
  { pageViews :: Int
  , visitors :: Int
  , bounceRate :: Double
  , pagesPerSession :: Double
  , averageSessionDuration :: Double
  } deriving (Show, Eq)

data PageMetric = PageMetric
  { pagePath :: Text
  , pagePageViews :: Int
  , pageTitle :: Maybe Text
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

formatPercentage :: Double -> Text
formatPercentage ratio =
  let percent = ratio * 100
      rounded = round percent :: Int
  in T.pack (show rounded) <> "%"

formatDecimal :: Double -> Text
formatDecimal value =
  let scaled = round (value * 10) :: Int
      whole = scaled `div` 10
      fraction = scaled `mod` 10
  in T.pack (show whole) <> "." <> T.pack (show fraction)

escapeTablePipe :: Text -> Text
escapeTablePipe = T.replace "|" "\\|"

pathToWikilinkTarget :: Text -> Text
pathToWikilinkTarget path =
  let stripped = fromMaybe path (T.stripPrefix "/" path)
  in if T.null stripped then "index" else stripped

formatTableWikilink :: Text -> Maybe Text -> Text
formatTableWikilink path title =
  let target = pathToWikilinkTarget path
      alias = escapeTablePipe (fromMaybe path title)
  in "[[" <> target <> "\\|" <> alias <> "]]"

buildAnalyticsSection :: AnalyticsReport -> Text
buildAnalyticsSection report =
  let summary = reportSummary report
      summaryLines =
        [ analyticsSectionHeader
        , ""
        , "- 📄 Page Views: " <> T.pack (show (pageViews summary))
        , "- 👥 Visitors: " <> T.pack (show (visitors summary))
        , "- 📊 Bounce Rate: " <> formatPercentage (bounceRate summary)
        , "- 📖 Pages per Session: " <> formatDecimal (pagesPerSession summary)
        , "- ⏱️ Avg Session: " <> formatDuration (averageSessionDuration summary)
        ]
      topPagesLines = case reportTopPages report of
        [] -> []
        pages ->
          [ ""
          , "### 🏆 Top Pages Today"
          , ""
          , "| 👁️ Views | 📄 Page |"
          , "|---:|:---|"
          ] <> fmap formatPageRow pages
  in T.intercalate "\n" (summaryLines <> topPagesLines)

formatPageRow :: PageMetric -> Text
formatPageRow metric =
  "| " <> T.pack (show (pagePageViews metric)) <> " | " <> formatTableWikilink (pagePath metric) (pageTitle metric) <> " |"

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
        [ Json.object ["name" Json..= ("screenPageViews" :: Text)]
        , Json.object ["name" Json..= ("activeUsers" :: Text)]
        , Json.object ["name" Json..= ("bounceRate" :: Text)]
        , Json.object ["name" Json..= ("screenPageViewsPerSession" :: Text)]
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
  checkForApiError value
  rows <- extractRows value
  case rows of
    (row : _) -> do
      metrics <- extractMetricValues row
      case metrics of
        [pageViewsText, visitorsText, bounceRateText, pagesPerSessionText, durationText] -> do
          pageViewsVal <- parseIntMetric "screenPageViews" pageViewsText
          visitorsVal <- parseIntMetric "activeUsers" visitorsText
          bounceRateVal <- parseDoubleMetric "bounceRate" bounceRateText
          pagesPerSessionVal <- parseDoubleMetric "screenPageViewsPerSession" pagesPerSessionText
          durationVal <- parseDoubleMetric "averageSessionDuration" durationText
          Right AnalyticsSummary
            { pageViews = pageViewsVal
            , visitors = visitorsVal
            , bounceRate = bounceRateVal
            , pagesPerSession = pagesPerSessionVal
            , averageSessionDuration = durationVal
            }
        _ -> Left $ "Expected 5 metrics, got " <> T.pack (show (length metrics))
    [] -> Left "No analytics data returned — the GA4 API response contained no rows. This usually means the service account lacks access to the property, the property ID is wrong, or there was genuinely no traffic."

parseAnalyticsResponse :: Json.Value -> Either Text [PageMetric]
parseAnalyticsResponse value = do
  checkForApiError value
  rows <- extractRows value
  traverse parsePageRow rows

parsePageRow :: Json.Value -> Either Text PageMetric
parsePageRow row = do
  dims <- extractDimensionValues row
  metrics <- extractMetricValues row
  case (dims, metrics) of
    (path : _, views : _) -> do
      viewsVal <- parseIntMetric "screenPageViews" views
      Right PageMetric
        { pagePath = path
        , pagePageViews = viewsVal
        , pageTitle = Nothing
        }
    _ -> Left "Missing dimension or metric in page row"

checkForApiError :: Json.Value -> Either Text ()
checkForApiError value =
  case value of
    Json.Object fields ->
      case lookup "error" fields of
        Just (Json.Object errFields) ->
          let message = case lookup "message" errFields of
                Just (Json.String msg) -> msg
                _ -> "unknown error"
              status = case lookup "status" errFields of
                Just (Json.String s) -> " (" <> s <> ")"
                _ -> ""
          in Left $ "GA4 API error: " <> message <> status
        _ -> Right ()
    _ -> Right ()

extractRowCount :: Json.Value -> Int
extractRowCount value =
  case value of
    Json.Object fields ->
      case lookup "rowCount" fields of
        Just (Json.Number n) -> round n
        _ -> case lookup "rows" fields of
          Just (Json.Array rows) -> length rows
          _ -> 0
    _ -> 0

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

parseIntMetric :: Text -> Text -> Either Text Int
parseIntMetric metricName text =
  case reads (T.unpack text) of
    [(n, "")] -> Right n
    _         -> case reads (T.unpack text) of
      [(d, _)] -> Right (round (d :: Double))
      _        -> Left $ "Failed to parse " <> metricName <> " value: " <> text

parseDoubleMetric :: Text -> Text -> Either Text Double
parseDoubleMetric metricName text =
  case reads (T.unpack text) of
    [(d, "")] -> Right d
    _         -> Left $ "Failed to parse " <> metricName <> " value: " <> text
