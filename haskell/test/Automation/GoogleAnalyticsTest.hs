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
  , reflectionNeedsAnalyticsTests
  , buildAnalyticsSectionTests
  , applyAnalyticsSectionTests
  , parseSummaryResponseTests
  , parseAnalyticsResponseTests
  , requestBodyTests
  , propertyTests
  ]

sampleSummary :: AnalyticsSummary
sampleSummary = AnalyticsSummary
  { activeUsers = 42
  , sessions = 67
  , pageViews = 185
  , newUsers = 15
  , averageSessionDuration = 154.5
  }

samplePages :: [PageMetric]
samplePages =
  [ PageMetric "/ai-blog/some-post" 23
  , PageMetric "/" 12
  , PageMetric "/chickie-loo/another-post" 8
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
  , testCase "includes active users" $
      assertBool "contains active users" (T.isInfixOf "👥 Active Users: 42" (buildAnalyticsSection sampleReport))
  , testCase "includes sessions" $
      assertBool "contains sessions" (T.isInfixOf "🔄 Sessions: 67" (buildAnalyticsSection sampleReport))
  , testCase "includes page views" $
      assertBool "contains page views" (T.isInfixOf "📄 Page Views: 185" (buildAnalyticsSection sampleReport))
  , testCase "includes new users" $
      assertBool "contains new users" (T.isInfixOf "🆕 New Users: 15" (buildAnalyticsSection sampleReport))
  , testCase "includes avg session duration" $
      assertBool "contains avg session" (T.isInfixOf "⏱️ Avg Session: 2m 34s" (buildAnalyticsSection sampleReport))
  , testCase "includes top pages section" $
      assertBool "contains top pages" (T.isInfixOf "### 🏆 Top Pages" (buildAnalyticsSection sampleReport))
  , testCase "includes page metrics" $
      assertBool "contains page path" (T.isInfixOf "/ai-blog/some-post — 23 views" (buildAnalyticsSection sampleReport))
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
        assertBool "contains stats" (T.isInfixOf "👥 Active Users: 42" result)
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
      let content = "# 2026-04-18\n\n## 📊 Google Analytics\n\n- 👥 Active Users: 10\n\n## 🔄 Updates\n\nStuff"
          updatedReport = AnalyticsReport (sampleSummary { activeUsers = 99 }) []
          result = applyAnalyticsSection content updatedReport
      in do
        assertBool "contains new value" (T.isInfixOf "👥 Active Users: 99" result)
        assertBool "old value gone" (not (T.isInfixOf "👥 Active Users: 10" result))
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
                        [ Json.Object [("value", Json.String "42")]
                        , Json.Object [("value", Json.String "67")]
                        , Json.Object [("value", Json.String "185")]
                        , Json.Object [("value", Json.String "15")]
                        , Json.Object [("value", Json.String "154.5")]
                        ])
                    ]
                ])
            ]
      in case parseSummaryResponse json of
        Right summary -> do
          activeUsers summary @?= 42
          sessions summary @?= 67
          pageViews summary @?= 185
          newUsers summary @?= 15
          assertBool "duration close" (abs (averageSessionDuration summary - 154.5) < 0.01)
        Left err -> error ("Parse failed: " <> T.unpack err)
  , testCase "returns zeros for empty response" $
      let json = Json.Object []
      in case parseSummaryResponse json of
        Right summary -> do
          activeUsers summary @?= 0
          sessions summary @?= 0
        Left err -> error ("Parse failed: " <> T.unpack err)
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
  ]
