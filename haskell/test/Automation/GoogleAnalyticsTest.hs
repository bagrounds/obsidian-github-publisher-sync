module Automation.GoogleAnalyticsTest (tests) where

import qualified Data.Text as T
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import Test.Tasty.QuickCheck (testProperty)
import qualified Test.Tasty.QuickCheck as QC

import Automation.GoogleAnalytics
import qualified Automation.Json as Json

tests :: TestTree
tests = testGroup "GoogleAnalytics"
  [ constantTests
  , formatDurationTests
  , formatPercentageTests
  , formatDecimalTests
  , reflectionNeedsAnalyticsTests
  , buildAnalyticsSectionTests
  , applyAnalyticsSectionTests
  , parseSummaryResponseTests
  , parseAnalyticsResponseTests
  , requestBodyTests
  , checkForApiErrorTests
  , extractRowCountTests
  , wikilinkTests
  , propertyTests
  ]

sampleSummary :: AnalyticsSummary
sampleSummary = AnalyticsSummary
  { pageViews = 185
  , visitors = 42
  , bounceRate = 0.65
  , pagesPerSession = 2.3
  , averageSessionDuration = 154.5
  }

samplePages :: [PageMetric]
samplePages =
  [ PageMetric "/ai-blog/some-post" 23 (Just "2026-04-15 | 📊 Some Post 🤖")
  , PageMetric "/" 12 (Just "🏡 Home")
  , PageMetric "/chickie-loo/another-post" 8 Nothing
  ]

sampleReport :: AnalyticsReport
sampleReport = AnalyticsReport sampleSummary samplePages

constantTests :: TestTree
constantTests = testGroup "constants"
  [ testCase "analyticsSectionHeader" $
      analyticsSectionHeader @?= "## 📊 Google Analytics"
  , testCase "analyticsReadonlyScope" $
      analyticsReadonlyScope @?= "https://www.googleapis.com/auth/analytics.readonly"
  , testCase "analyticsApiEndpoint includes property ID" $
      analyticsApiEndpoint "123456789" @?= "https://analyticsdata.googleapis.com/v1beta/properties/123456789:runReport"
  ]

formatDurationTests :: TestTree
formatDurationTests = testGroup "formatDuration"
  [ testCase "zero seconds" $
      formatDuration 0 @?= "0m 00s"
  , testCase "90 seconds formats to 1m 30s" $
      formatDuration 90 @?= "1m 30s"
  , testCase "154.5 seconds formats to 2m 34s" $
      formatDuration 154.5 @?= "2m 34s"
  , testCase "3661 seconds formats to 61m 01s" $
      formatDuration 3661 @?= "61m 01s"
  , testCase "5 seconds pads with zero" $
      formatDuration 5 @?= "0m 05s"
  ]

formatPercentageTests :: TestTree
formatPercentageTests = testGroup "formatPercentage"
  [ testCase "zero" $
      formatPercentage 0 @?= "0%"
  , testCase "0.65 formats to 65%" $
      formatPercentage 0.65 @?= "65%"
  , testCase "1.0 formats to 100%" $
      formatPercentage 1.0 @?= "100%"
  , testCase "0.123 rounds to 12%" $
      formatPercentage 0.123 @?= "12%"
  , testCase "0.999 rounds to 100%" $
      formatPercentage 0.999 @?= "100%"
  ]

formatDecimalTests :: TestTree
formatDecimalTests = testGroup "formatDecimal"
  [ testCase "zero" $
      formatDecimal 0 @?= "0.0"
  , testCase "2.3 formats correctly" $
      formatDecimal 2.3 @?= "2.3"
  , testCase "1.0 formats with decimal" $
      formatDecimal 1.0 @?= "1.0"
  , testCase "5.67 rounds to one decimal" $
      formatDecimal 5.67 @?= "5.7"
  ]

reflectionNeedsAnalyticsTests :: TestTree
reflectionNeedsAnalyticsTests = testGroup "reflectionNeedsAnalytics"
  [ testCase "true when section not present" $
      reflectionNeedsAnalytics "# 2026-04-18\n\nSome content" @?= True
  , testCase "false when section present" $
      reflectionNeedsAnalytics "# 2026-04-18\n\n## 📊 Google Analytics\n\nStats" @?= False
  ]

buildAnalyticsSectionTests :: TestTree
buildAnalyticsSectionTests = testGroup "buildAnalyticsSection"
  [ testCase "includes section header" $
      assertBool "contains header" (T.isInfixOf "## 📊 Google Analytics" (buildAnalyticsSection sampleReport))
  , testCase "includes page views" $
      assertBool "contains page views" (T.isInfixOf "📄 Page Views: 185" (buildAnalyticsSection sampleReport))
  , testCase "includes visitors" $
      assertBool "contains visitors" (T.isInfixOf "👥 Visitors: 42" (buildAnalyticsSection sampleReport))
  , testCase "includes bounce rate" $
      assertBool "contains bounce rate" (T.isInfixOf "📊 Bounce Rate: 65%" (buildAnalyticsSection sampleReport))
  , testCase "includes pages per session" $
      assertBool "contains pages per session" (T.isInfixOf "📖 Pages per Session: 2.3" (buildAnalyticsSection sampleReport))
  , testCase "includes avg session duration" $
      assertBool "contains avg session" (T.isInfixOf "⏱️ Avg Session: 2m 34s" (buildAnalyticsSection sampleReport))
  , testCase "includes top pages table header" $
      assertBool "contains table header" (T.isInfixOf "| 👁️ | 📄 Page |" (buildAnalyticsSection sampleReport))
  , testCase "includes table separator" $
      assertBool "contains separator" (T.isInfixOf "|---:|:---|" (buildAnalyticsSection sampleReport))
  , testCase "includes page views in table" $
      assertBool "contains view count" (T.isInfixOf "| 23 |" (buildAnalyticsSection sampleReport))
  , testCase "includes wikilink for page with title" $
      assertBool "contains wikilink" (T.isInfixOf "[[ai-blog/some-post\\|2026-04-15 \\| 📊 Some Post 🤖]]" (buildAnalyticsSection sampleReport))
  , testCase "includes wikilink for root page" $
      assertBool "contains index wikilink" (T.isInfixOf "[[index\\|🏡 Home]]" (buildAnalyticsSection sampleReport))
  , testCase "uses path as alias when no title" $
      assertBool "contains path fallback" (T.isInfixOf "[[chickie-loo/another-post\\|/chickie-loo/another-post]]" (buildAnalyticsSection sampleReport))
  , testCase "no top pages section when empty" $
      let report = AnalyticsReport sampleSummary []
      in assertBool "no top pages" (not (T.isInfixOf "### 🏆 Top Pages" (buildAnalyticsSection report)))
  ]

applyAnalyticsSectionTests :: TestTree
applyAnalyticsSectionTests = testGroup "applyAnalyticsSection"
  [ testCase "inserts section when not present" $
      let content = "# 2026-04-18\n\nSome content"
          result = applyAnalyticsSection content sampleReport
      in do
        assertBool "contains header" (T.isInfixOf "## 📊 Google Analytics" result)
        assertBool "contains stats" (T.isInfixOf "📄 Page Views: 185" result)
  , testCase "inserts after fiction section" $
      let content = "# 2026-04-18\n\nContent\n\n## 🤖🐲 AI Fiction\n\nFiction text"
          result = applyAnalyticsSection content sampleReport
          analyticsIdx = T.length $ fst $ T.breakOn "## 📊 Google Analytics" result
          fictionIdx = T.length $ fst $ T.breakOn "## 🤖🐲 AI Fiction" result
      in assertBool "analytics after fiction" (analyticsIdx > fictionIdx)
  , testCase "inserts between fiction and updates" $
      let content = "# 2026-04-18\n\nContent\n\n## 🤖🐲 AI Fiction\n\nFiction text\n\n## 🔄 Updates\n\nUpdate text"
          result = applyAnalyticsSection content sampleReport
          fictionIdx = T.length $ fst $ T.breakOn "## 🤖🐲 AI Fiction" result
          analyticsIdx = T.length $ fst $ T.breakOn "## 📊 Google Analytics" result
          updatesIdx = T.length $ fst $ T.breakOn "## 🔄 Updates" result
      in do
        assertBool "analytics after fiction" (analyticsIdx > fictionIdx)
        assertBool "analytics before updates" (analyticsIdx < updatesIdx)
  , testCase "inserts before updates section" $
      let content = "# 2026-04-18\n\nContent\n\n## 🔄 Updates\n\nUpdate text"
          result = applyAnalyticsSection content sampleReport
          analyticsIdx = T.length $ fst $ T.breakOn "## 📊 Google Analytics" result
          updatesIdx = T.length $ fst $ T.breakOn "## 🔄 Updates" result
      in assertBool "analytics before updates" (analyticsIdx < updatesIdx)
  , testCase "inserts before embed sections" $
      let content = "# 2026-04-18\n\nContent\n\n## 🐦 Tweet\n\nTweet embed"
          result = applyAnalyticsSection content sampleReport
          analyticsIdx = T.length $ fst $ T.breakOn "## 📊 Google Analytics" result
          tweetIdx = T.length $ fst $ T.breakOn "## 🐦 Tweet" result
      in assertBool "analytics before tweet" (analyticsIdx < tweetIdx)
  , testCase "replaces existing section" $
      let content = "# 2026-04-18\n\n## 📊 Google Analytics\n\n- 📄 Page Views: 10\n\n## 🔄 Updates\n\nStuff"
          updatedReport = AnalyticsReport (sampleSummary { pageViews = 99 }) []
          result = applyAnalyticsSection content updatedReport
      in do
        assertBool "contains new value" (T.isInfixOf "📄 Page Views: 99" result)
        assertBool "old value gone" (not (T.isInfixOf "📄 Page Views: 10" result))
        assertBool "updates section preserved" (T.isInfixOf "## 🔄 Updates" result)
  , testCase "appends at end when no trailing sections" $
      let content = "# 2026-04-18\n\nBody text"
          result = applyAnalyticsSection content sampleReport
      in assertBool "contains analytics" (T.isInfixOf "## 📊 Google Analytics" result)
  ]

parseSummaryResponseTests :: TestTree
parseSummaryResponseTests = testGroup "parseSummaryResponse"
  [ testCase "parses valid summary response" $
      let json = Json.Object
            [ ("rows", Json.Array
                [ Json.Object
                    [ ("metricValues", Json.Array
                        [ Json.Object [("value", Json.String "185")]
                        , Json.Object [("value", Json.String "42")]
                        , Json.Object [("value", Json.String "0.65")]
                        , Json.Object [("value", Json.String "2.3")]
                        , Json.Object [("value", Json.String "154.5")]
                        ])
                    ]
                ])
            ]
      in case parseSummaryResponse json of
        Right summary -> do
          pageViews summary @?= 185
          visitors summary @?= 42
          assertBool "bounce rate close" (abs (bounceRate summary - 0.65) < 0.01)
          assertBool "pages per session close" (abs (pagesPerSession summary - 2.3) < 0.01)
          assertBool "duration close" (abs (averageSessionDuration summary - 154.5) < 0.01)
        Left err -> error ("Parse failed: " <> T.unpack err)
  , testCase "returns error for empty response (no rows)" $
      let json = Json.Object []
      in case parseSummaryResponse json of
        Left err -> assertBool "mentions no data" (T.isInfixOf "No analytics data" err)
        Right _ -> error "Expected Left for empty response"
  , testCase "returns error for API error response" $
      let json = Json.Object
            [ ("error", Json.Object
                [ ("message", Json.String "User does not have sufficient permissions")
                , ("status", Json.String "PERMISSION_DENIED")
                ])
            ]
      in case parseSummaryResponse json of
        Left err -> do
          assertBool "mentions permission" (T.isInfixOf "permissions" err)
          assertBool "mentions status" (T.isInfixOf "PERMISSION_DENIED" err)
        Right _ -> error "Expected Left for error response"
  ]

parseAnalyticsResponseTests :: TestTree
parseAnalyticsResponseTests = testGroup "parseAnalyticsResponse"
  [ testCase "parses top pages response" $
      let json = Json.Object
            [ ("rows", Json.Array
                [ Json.Object
                    [ ("dimensionValues", Json.Array
                        [ Json.Object [("value", Json.String "/")]
                        ])
                    , ("metricValues", Json.Array
                        [ Json.Object [("value", Json.String "50")]
                        ])
                    ]
                , Json.Object
                    [ ("dimensionValues", Json.Array
                        [ Json.Object [("value", Json.String "/blog")]
                        ])
                    , ("metricValues", Json.Array
                        [ Json.Object [("value", Json.String "30")]
                        ])
                    ]
                ])
            ]
      in case parseAnalyticsResponse json of
        Right pages -> do
          length pages @?= 2
          case pages of
            (first : _) -> do
              pagePath first @?= "/"
              pagePageViews first @?= 50
              pageTitle first @?= Nothing
            [] -> error "Expected at least one page"
        Left err -> error ("Parse failed: " <> T.unpack err)
  , testCase "handles empty rows" $
      let json = Json.Object []
      in case parseAnalyticsResponse json of
        Right pages -> length pages @?= 0
        Left err -> error ("Parse failed: " <> T.unpack err)
  ]

requestBodyTests :: TestTree
requestBodyTests = testGroup "request body builders"
  [ testCase "buildSummaryRequestBody includes date" $
      let body = buildSummaryRequestBody "2026-04-17"
      in case body of
        Json.Object fields ->
          case lookup "dateRanges" fields of
            Just (Json.Array (range : _)) ->
              case range of
                Json.Object rangeFields ->
                  case lookup "startDate" rangeFields of
                    Just (Json.String startDate) -> startDate @?= "2026-04-17"
                    _ -> error "Expected string startDate"
                _ -> error "Expected object range"
            _ -> error "Expected array dateRanges"
        _ -> error "Expected object"
  , testCase "buildSummaryRequestBody includes all 5 metrics" $
      let body = buildSummaryRequestBody "2026-04-17"
      in case body of
        Json.Object fields ->
          case lookup "metrics" fields of
            Just (Json.Array metrics) -> length metrics @?= 5
            _ -> error "Expected array metrics"
        _ -> error "Expected object"
  , testCase "buildSummaryRequestBody requests screenPageViews" $
      let body = buildSummaryRequestBody "2026-04-17"
      in assertBool "contains screenPageViews" (T.isInfixOf "screenPageViews" (T.pack (show body)))
  , testCase "buildSummaryRequestBody requests bounceRate" $
      let body = buildSummaryRequestBody "2026-04-17"
      in assertBool "contains bounceRate" (T.isInfixOf "bounceRate" (T.pack (show body)))
  , testCase "buildSummaryRequestBody requests screenPageViewsPerSession" $
      let body = buildSummaryRequestBody "2026-04-17"
      in assertBool "contains screenPageViewsPerSession" (T.isInfixOf "screenPageViewsPerSession" (T.pack (show body)))
  , testCase "buildTopPagesRequestBody includes pagePath dimension" $
      let body = buildTopPagesRequestBody "2026-04-17"
      in case body of
        Json.Object fields ->
          case lookup "dimensions" fields of
            Just (Json.Array (dim : _)) ->
              case dim of
                Json.Object dimFields ->
                  case lookup "name" dimFields of
                    Just (Json.String dimName) -> dimName @?= "pagePath"
                    _ -> error "Expected string name"
                _ -> error "Expected object dim"
            _ -> error "Expected array dimensions"
        _ -> error "Expected object"
  , testCase "buildTopPagesRequestBody limits to 5 results" $
      let body = buildTopPagesRequestBody "2026-04-17"
      in case body of
        Json.Object fields ->
          case lookup "limit" fields of
            Just (Json.Number limitVal) -> limitVal @?= 5
            _ -> error "Expected number limit"
        _ -> error "Expected object"
  ]

checkForApiErrorTests :: TestTree
checkForApiErrorTests = testGroup "checkForApiError"
  [ testCase "returns Right for valid response" $
      let json = Json.Object [("rows", Json.Array [])]
      in checkForApiError json @?= Right ()
  , testCase "returns Left for error response" $
      let json = Json.Object
            [ ("error", Json.Object
                [ ("message", Json.String "Permission denied")
                , ("status", Json.String "PERMISSION_DENIED")
                ])
            ]
      in case checkForApiError json of
        Left err -> do
          assertBool "mentions permission" (T.isInfixOf "Permission denied" err)
          assertBool "mentions status" (T.isInfixOf "PERMISSION_DENIED" err)
        Right _ -> error "Expected Left for error response"
  , testCase "returns Right when no error field" $
      checkForApiError (Json.Object []) @?= Right ()
  ]

extractRowCountTests :: TestTree
extractRowCountTests = testGroup "extractRowCount"
  [ testCase "counts rows from array" $
      let json = Json.Object
            [ ("rows", Json.Array
                [ Json.Object [("value", Json.String "1")]
                , Json.Object [("value", Json.String "2")]
                ])
            ]
      in extractRowCount json @?= 2
  , testCase "uses rowCount field when present" $
      let json = Json.Object [("rowCount", Json.Number 42)]
      in extractRowCount json @?= 42
  , testCase "returns 0 for empty response" $
      extractRowCount (Json.Object []) @?= 0
  ]

wikilinkTests :: TestTree
wikilinkTests = testGroup "wikilinks"
  [ testCase "pathToWikilinkTarget strips leading slash" $
      pathToWikilinkTarget "/reflections/2026-04-17" @?= "reflections/2026-04-17"
  , testCase "pathToWikilinkTarget converts root to index" $
      pathToWikilinkTarget "/" @?= "index"
  , testCase "pathToWikilinkTarget preserves path without slash" $
      pathToWikilinkTarget "ai-blog/some-post" @?= "ai-blog/some-post"
  , testCase "formatTableWikilink with title" $
      formatTableWikilink "/ai-blog/post" (Just "My Post") @?= "[[ai-blog/post\\|My Post]]"
  , testCase "formatTableWikilink without title uses path" $
      formatTableWikilink "/ai-blog/post" Nothing @?= "[[ai-blog/post\\|/ai-blog/post]]"
  , testCase "formatTableWikilink escapes pipe in title" $
      formatTableWikilink "/reflections/2026-04-17" (Just "2026-04-17 | Daily Reflection")
        @?= "[[reflections/2026-04-17\\|2026-04-17 \\| Daily Reflection]]"
  , testCase "formatTableWikilink root path with title" $
      formatTableWikilink "/" (Just "🏡 Home") @?= "[[index\\|🏡 Home]]"
  , testCase "escapeTablePipe replaces pipe" $
      escapeTablePipe "a | b" @?= "a \\| b"
  ]

propertyTests :: TestTree
propertyTests = testGroup "properties"
  [ testProperty "reflectionNeedsAnalytics returns false after applyAnalyticsSection" $
      \(QC.ASCIIString content) ->
        let report = AnalyticsReport
              (AnalyticsSummary 0 0 0 0 0)
              []
            result = applyAnalyticsSection (T.pack content) report
        in not (reflectionNeedsAnalytics result)
  , testProperty "formatDuration always contains m and s" $
      QC.forAll (QC.choose (0.0, 100000.0)) $ \duration ->
        let result = formatDuration duration
        in T.isInfixOf "m" result && T.isInfixOf "s" result
  , testProperty "formatPercentage always ends with percent" $
      QC.forAll (QC.choose (0.0, 1.0)) $ \ratio ->
        T.isSuffixOf "%" (formatPercentage ratio)
  , testProperty "formatDecimal always contains a dot" $
      QC.forAll (QC.choose (0.0, 100.0)) $ \value ->
        T.isInfixOf "." (formatDecimal value)
  , testProperty "pathToWikilinkTarget never starts with slash" $
      \(QC.ASCIIString path) ->
        let result = pathToWikilinkTarget (T.pack path)
        in not (T.isPrefixOf "/" result) || T.null result
  ]
