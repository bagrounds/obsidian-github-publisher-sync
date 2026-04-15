module Automation.ContextQueryTest (tests) where

import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import Test.Tasty.QuickCheck (testProperty)
import qualified Test.QuickCheck as QC

import Automation.ContextQuery
import Automation.Json (eitherDecodeStrict)
import qualified Data.Text.Encoding as TE

tests :: TestTree
tests = testGroup "ContextQuery"
  [ scopeParsingTests
  , scopeRoundTripTests
  , jsonParsingTests
  , defaultQueryTests
  , evaluationTests
  ]

scopeParsingTests :: TestTree
scopeParsingTests = testGroup "parseScope"
  [ testCase "parses self" $
      parseScope "self" @?= Right Self

  , testCase "parses others" $
      parseScope "others" @?= Right OtherSeries

  , testCase "parses all" $
      parseScope "all" @?= Right AllSeries

  , testCase "parses series:<id>" $
      parseScope "series:chickie-loo" @?= Right (SpecificSeries "chickie-loo")

  , testCase "rejects empty series: prefix" $
      assertBool "should reject empty series ID" $
        isLeft (parseScope "series:")

  , testCase "rejects unknown scope" $
      assertBool "should reject unknown" $
        isLeft (parseScope "unknown")

  , testCase "rejects empty string" $
      assertBool "should reject empty" $
        isLeft (parseScope "")
  ]

scopeRoundTripTests :: TestTree
scopeRoundTripTests = testGroup "scope round-trip"
  [ testCase "Self round-trips" $
      parseScope (scopeToText Self) @?= Right Self

  , testCase "OtherSeries round-trips" $
      parseScope (scopeToText OtherSeries) @?= Right OtherSeries

  , testCase "AllSeries round-trips" $
      parseScope (scopeToText AllSeries) @?= Right AllSeries

  , testCase "SpecificSeries round-trips" $
      parseScope (scopeToText (SpecificSeries "test-series")) @?= Right (SpecificSeries "test-series")

  , testProperty "SpecificSeries always round-trips" $
      QC.forAll genSeriesId $ \seriesId ->
        parseScope (scopeToText (SpecificSeries seriesId)) == Right (SpecificSeries seriesId)
  ]

jsonParsingTests :: TestTree
jsonParsingTests = testGroup "JSON parsing"
  [ testCase "parses self latest query" $
      let json = "{\"from\": \"self\", \"latest\": 7}"
      in parseContextQuery json @?= Right (ContextQuery Self (Latest 7))

  , testCase "parses others latestPerSeries query" $
      let json = "{\"from\": \"others\", \"latestPerSeries\": 1}"
      in parseContextQuery json @?= Right (ContextQuery OtherSeries (LatestPerSeries 1))

  , testCase "parses all latest query" $
      let json = "{\"from\": \"all\", \"latest\": 5}"
      in parseContextQuery json @?= Right (ContextQuery AllSeries (Latest 5))

  , testCase "parses specific series query" $
      let json = "{\"from\": \"series:chickie-loo\", \"latest\": 3}"
      in parseContextQuery json @?= Right (ContextQuery (SpecificSeries "chickie-loo") (Latest 3))

  , testCase "rejects both latest and latestPerSeries" $
      let json = "{\"from\": \"self\", \"latest\": 7, \"latestPerSeries\": 1}"
      in assertBool "should reject both fields" $
           isLeft (parseContextQuery json)

  , testCase "rejects neither latest nor latestPerSeries" $
      let json = "{\"from\": \"self\"}"
      in assertBool "should reject missing selection" $
           isLeft (parseContextQuery json)

  , testCase "rejects invalid scope" $
      let json = "{\"from\": \"invalid\", \"latest\": 5}"
      in assertBool "should reject invalid scope" $
           isLeft (parseContextQuery json)

  , testCase "parses array of queries" $
      let json = "[{\"from\": \"self\", \"latest\": 7}, {\"from\": \"others\", \"latestPerSeries\": 1}]"
          expected = [ContextQuery Self (Latest 7), ContextQuery OtherSeries (LatestPerSeries 1)]
      in parseContextQueryList json @?= Right expected

  , testCase "parses empty array" $
      parseContextQueryList "[]" @?= Right []
  ]

defaultQueryTests :: TestTree
defaultQueryTests = testGroup "defaultContextQueries"
  [ testCase "default has one query" $
      length defaultContextQueries @?= 1

  , testCase "default queries self latest 7" $
      defaultContextQueries @?= [ContextQuery Self (Latest 7)]
  ]

evaluationTests :: TestTree
evaluationTests = testGroup "evaluateQueries"
  [ testCase "self query returns posts from self directory" $
      withTestContentDir $ \contentRoot -> do
        writePosts contentRoot "my-series" ["2026-04-15-first.md", "2026-04-14-second.md"]
        let queries = [ContextQuery Self (Latest 7)]
            seriesInfoMap = Map.empty
        (selfPosts, crossPosts) <- evaluateQueries "my-series" contentRoot seriesInfoMap queries
        length selfPosts @?= 2
        length crossPosts @?= 0

  , testCase "self query respects latest limit" $
      withTestContentDir $ \contentRoot -> do
        writePosts contentRoot "my-series" ["2026-04-15-a.md", "2026-04-14-b.md", "2026-04-13-c.md"]
        let queries = [ContextQuery Self (Latest 2)]
        (selfPosts, _) <- evaluateQueries "my-series" contentRoot Map.empty queries
        length selfPosts @?= 2

  , testCase "others query returns posts from other series" $
      withTestContentDir $ \contentRoot -> do
        writePosts contentRoot "my-series" ["2026-04-15-mine.md"]
        writePosts contentRoot "other-series" ["2026-04-15-theirs.md"]
        let otherInfo = SeriesInfo "other-series" "Other" "🔹"
            seriesInfoMap = Map.fromList [("other-series", otherInfo)]
            queries = [ContextQuery OtherSeries (LatestPerSeries 1)]
        (selfPosts, crossPosts) <- evaluateQueries "my-series" contentRoot seriesInfoMap queries
        length selfPosts @?= 0
        length crossPosts @?= 1
        case crossPosts of
          (cp : _) -> cspSeriesName cp @?= "Other"
          [] -> assertBool "expected at least one cross post" False

  , testCase "others query excludes self" $
      withTestContentDir $ \contentRoot -> do
        writePosts contentRoot "my-series" ["2026-04-15-mine.md"]
        writePosts contentRoot "other-series" ["2026-04-15-theirs.md"]
        let myInfo = SeriesInfo "my-series" "Mine" "🔸"
            otherInfo = SeriesInfo "other-series" "Other" "🔹"
            seriesInfoMap = Map.fromList [("my-series", myInfo), ("other-series", otherInfo)]
            queries = [ContextQuery OtherSeries (LatestPerSeries 1)]
        (_, crossPosts) <- evaluateQueries "my-series" contentRoot seriesInfoMap queries
        length crossPosts @?= 1
        case crossPosts of
          (cp : _) -> cspSeriesName cp @?= "Other"
          [] -> assertBool "expected at least one cross post" False

  , testCase "all query returns self and cross posts" $
      withTestContentDir $ \contentRoot -> do
        writePosts contentRoot "my-series" ["2026-04-15-mine.md"]
        writePosts contentRoot "other-series" ["2026-04-15-theirs.md"]
        let otherInfo = SeriesInfo "other-series" "Other" "🔹"
            seriesInfoMap = Map.fromList [("other-series", otherInfo)]
            queries = [ContextQuery AllSeries (Latest 5)]
        (selfPosts, crossPosts) <- evaluateQueries "my-series" contentRoot seriesInfoMap queries
        length selfPosts @?= 1
        length crossPosts @?= 1

  , testCase "specific series query returns cross posts from named series" $
      withTestContentDir $ \contentRoot -> do
        writePosts contentRoot "target-series" ["2026-04-15-post.md"]
        let targetInfo = SeriesInfo "target-series" "Target" "🎯"
            seriesInfoMap = Map.fromList [("target-series", targetInfo)]
            queries = [ContextQuery (SpecificSeries "target-series") (Latest 3)]
        (selfPosts, crossPosts) <- evaluateQueries "my-series" contentRoot seriesInfoMap queries
        length selfPosts @?= 0
        length crossPosts @?= 1
        case crossPosts of
          (cp : _) -> cspSeriesName cp @?= "Target"
          [] -> assertBool "expected at least one cross post" False

  , testCase "specific series targeting self returns self posts" $
      withTestContentDir $ \contentRoot -> do
        writePosts contentRoot "my-series" ["2026-04-15-mine.md"]
        let queries = [ContextQuery (SpecificSeries "my-series") (Latest 3)]
        (selfPosts, crossPosts) <- evaluateQueries "my-series" contentRoot Map.empty queries
        length selfPosts @?= 1
        length crossPosts @?= 0

  , testCase "multiple queries combine results" $
      withTestContentDir $ \contentRoot -> do
        writePosts contentRoot "my-series" ["2026-04-15-mine.md", "2026-04-14-older.md"]
        writePosts contentRoot "other-a" ["2026-04-15-a.md"]
        writePosts contentRoot "other-b" ["2026-04-15-b.md"]
        let infoA = SeriesInfo "other-a" "Series A" "🅰️"
            infoB = SeriesInfo "other-b" "Series B" "🅱️"
            seriesInfoMap = Map.fromList [("other-a", infoA), ("other-b", infoB)]
            queries =
              [ ContextQuery Self (Latest 7)
              , ContextQuery OtherSeries (LatestPerSeries 1)
              ]
        (selfPosts, crossPosts) <- evaluateQueries "my-series" contentRoot seriesInfoMap queries
        length selfPosts @?= 2
        length crossPosts @?= 2

  , testCase "empty queries return nothing" $
      withTestContentDir $ \contentRoot -> do
        writePosts contentRoot "my-series" ["2026-04-15-mine.md"]
        (selfPosts, crossPosts) <- evaluateQueries "my-series" contentRoot Map.empty []
        length selfPosts @?= 0
        length crossPosts @?= 0

  , testCase "missing directory returns empty" $
      withTestContentDir $ \contentRoot -> do
        let queries = [ContextQuery Self (Latest 7)]
        (selfPosts, crossPosts) <- evaluateQueries "nonexistent" contentRoot Map.empty queries
        length selfPosts @?= 0
        length crossPosts @?= 0

  , testCase "unknown specific series returns empty" $
      withTestContentDir $ \contentRoot -> do
        let queries = [ContextQuery (SpecificSeries "nonexistent") (Latest 3)]
        (_, crossPosts) <- evaluateQueries "my-series" contentRoot Map.empty queries
        length crossPosts @?= 0

  , testCase "latestPerSeries respects per-series limit" $
      withTestContentDir $ \contentRoot -> do
        writePosts contentRoot "series-a" ["2026-04-15-a1.md", "2026-04-14-a2.md", "2026-04-13-a3.md"]
        writePosts contentRoot "series-b" ["2026-04-15-b1.md", "2026-04-14-b2.md"]
        let infoA = SeriesInfo "series-a" "A" "🅰️"
            infoB = SeriesInfo "series-b" "B" "🅱️"
            seriesInfoMap = Map.fromList [("series-a", infoA), ("series-b", infoB)]
            queries = [ContextQuery OtherSeries (LatestPerSeries 1)]
        (_, crossPosts) <- evaluateQueries "my-series" contentRoot seriesInfoMap queries
        length crossPosts @?= 2

  , testCase "latest total across others limits total posts" $
      withTestContentDir $ \contentRoot -> do
        writePosts contentRoot "series-a" ["2026-04-15-a1.md", "2026-04-14-a2.md"]
        writePosts contentRoot "series-b" ["2026-04-15-b1.md", "2026-04-14-b2.md"]
        let infoA = SeriesInfo "series-a" "A" "🅰️"
            infoB = SeriesInfo "series-b" "B" "🅱️"
            seriesInfoMap = Map.fromList [("series-a", infoA), ("series-b", infoB)]
            queries = [ContextQuery OtherSeries (Latest 2)]
        (_, crossPosts) <- evaluateQueries "my-series" contentRoot seriesInfoMap queries
        length crossPosts @?= 2

  , testCase "cross series posts carry correct metadata" $
      withTestContentDir $ \contentRoot -> do
        writePosts contentRoot "other" ["2026-04-15-post.md"]
        let info = SeriesInfo "other" "Other Name" "✨"
            seriesInfoMap = Map.singleton "other" info
            queries = [ContextQuery OtherSeries (LatestPerSeries 1)]
        (_, crossPosts) <- evaluateQueries "my-series" contentRoot seriesInfoMap queries
        case crossPosts of
          (cp : _) -> do
            cspSeriesName cp @?= "Other Name"
            cspSeriesIcon cp @?= "✨"
          [] -> assertBool "expected at least one cross post" False
  ]

-- Test helpers

parseContextQuery :: Text -> Either String ContextQuery
parseContextQuery = eitherDecodeStrict . TE.encodeUtf8

parseContextQueryList :: Text -> Either String [ContextQuery]
parseContextQueryList = eitherDecodeStrict . TE.encodeUtf8

isLeft :: Either a b -> Bool
isLeft (Left _) = True
isLeft (Right _) = False

withTestContentDir :: (FilePath -> IO a) -> IO a
withTestContentDir = withSystemTempDirectory "context-query-test"

writePosts :: FilePath -> Text -> [Text] -> IO ()
writePosts contentRoot seriesId filenames = do
  let seriesDir = contentRoot </> T.unpack seriesId
  createDirectoryIfMissing True seriesDir
  mapM_ (writeTestPost seriesDir) filenames

writeTestPost :: FilePath -> Text -> IO ()
writeTestPost seriesDir filename = do
  let content = "---\ntitle: \"Test Post\"\n---\nTest body content for " <> filename
  TIO.writeFile (seriesDir </> T.unpack filename) content

genSeriesId :: QC.Gen Text
genSeriesId = do
  parts <- QC.listOf1 genWord
  pure (T.intercalate "-" parts)
  where
    genWord = T.pack <$> QC.listOf1 (QC.elements ['a'..'z'])
