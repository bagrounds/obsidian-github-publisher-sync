module Automation.ContextQueryTest (tests) where

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
  [ orderByParsingTests
  , orderByRoundTripTests
  , jsonParsingTests
  , whereClauseTests
  , defaultQueryTests
  , evaluationTests
  ]

orderByParsingTests :: TestTree
orderByParsingTests = testGroup "parseOrderBy"
  [ testCase "parses filename DESC" $
      parseOrderBy "filename DESC" @?= Right (OrderBy Filename Descending)

  , testCase "parses date ASC" $
      parseOrderBy "date ASC" @?= Right (OrderBy Date Ascending)

  , testCase "parses title DESC" $
      parseOrderBy "title DESC" @?= Right (OrderBy Title Descending)

  , testCase "defaults to DESC when direction omitted" $
      parseOrderBy "filename" @?= Right (OrderBy Filename Descending)

  , testCase "case insensitive direction" $
      parseOrderBy "date asc" @?= Right (OrderBy Date Ascending)

  , testCase "rejects unknown field" $
      assertBool "should reject unknown field" $
        isLeft (parseOrderBy "unknown DESC")

  , testCase "rejects empty string" $
      assertBool "should reject empty" $
        isLeft (parseOrderBy "")

  , testCase "rejects unknown direction" $
      assertBool "should reject unknown direction" $
        isLeft (parseOrderBy "filename UPWARD")
  ]

orderByRoundTripTests :: TestTree
orderByRoundTripTests = testGroup "orderBy round-trip"
  [ testCase "filename DESC round-trips" $
      parseOrderBy (orderByToText (OrderBy Filename Descending)) @?= Right (OrderBy Filename Descending)

  , testCase "date ASC round-trips" $
      parseOrderBy (orderByToText (OrderBy Date Ascending)) @?= Right (OrderBy Date Ascending)

  , testCase "title DESC round-trips" $
      parseOrderBy (orderByToText (OrderBy Title Descending)) @?= Right (OrderBy Title Descending)

  , testProperty "all OrderBy values round-trip" $
      QC.forAll genOrderBy $ \orderBy ->
        parseOrderBy (orderByToText orderBy) == Right orderBy
  ]

jsonParsingTests :: TestTree
jsonParsingTests = testGroup "JSON parsing"
  [ testCase "parses simple FROM with limit" $
      let json = "{\"from\": [\"my-series\"], \"limit\": 7}"
      in parseContextQuery json @?= Right (ContextQuery
          { cqFrom = ["my-series"]
          , cqWhere = []
          , cqOrderBy = OrderBy Filename Descending
          , cqLimit = Just 7
          , cqLimitPerSource = Nothing
          })

  , testCase "parses multiple FROM directories" $
      let json = "{\"from\": [\"series-a\", \"series-b\"], \"limit\": 5}"
          result = parseContextQuery json
      in case result of
        Right query -> cqFrom query @?= ["series-a", "series-b"]
        Left err -> assertBool ("unexpected parse error: " <> err) False

  , testCase "parses orderBy" $
      let json = "{\"from\": [\"my-series\"], \"orderBy\": \"date ASC\", \"limit\": 3}"
          result = parseContextQuery json
      in case result of
        Right query -> cqOrderBy query @?= OrderBy Date Ascending
        Left err -> assertBool ("unexpected parse error: " <> err) False

  , testCase "parses limitPerSource" $
      let json = "{\"from\": [\"a\", \"b\"], \"limitPerSource\": 1}"
          result = parseContextQuery json
      in case result of
        Right query -> cqLimitPerSource query @?= Just 1
        Left err -> assertBool ("unexpected parse error: " <> err) False

  , testCase "defaults orderBy to filename DESC" $
      let json = "{\"from\": [\"x\"], \"limit\": 3}"
          result = parseContextQuery json
      in case result of
        Right query -> cqOrderBy query @?= OrderBy Filename Descending
        Left err -> assertBool ("unexpected parse error: " <> err) False

  , testCase "accepts no limit and no limitPerSource" $
      let json = "{\"from\": [\"x\"]}"
          result = parseContextQuery json
      in case result of
        Right query -> do
          cqLimit query @?= Nothing
          cqLimitPerSource query @?= Nothing
        Left err -> assertBool ("unexpected parse error: " <> err) False

  , testCase "parses where clause" $
      let json = "{\"from\": [\"x\"], \"where\": [{\"field\": \"date\", \"operator\": \">=\", \"value\": \"2026-04-01\"}], \"limit\": 5}"
          result = parseContextQuery json
      in case result of
        Right query -> cqWhere query @?= [WhereCondition Date GreaterOrEqual "2026-04-01"]
        Left err -> assertBool ("unexpected parse error: " <> err) False

  , testCase "rejects invalid orderBy field" $
      let json = "{\"from\": [\"x\"], \"orderBy\": \"invalid DESC\", \"limit\": 3}"
      in assertBool "should reject invalid field" $
           isLeft (parseContextQuery json)

  , testCase "rejects invalid where field" $
      let json = "{\"from\": [\"x\"], \"where\": [{\"field\": \"invalid\", \"operator\": \">=\", \"value\": \"x\"}]}"
      in assertBool "should reject invalid where field" $
           isLeft (parseContextQuery json)

  , testCase "rejects invalid where operator" $
      let json = "{\"from\": [\"x\"], \"where\": [{\"field\": \"date\", \"operator\": \"!=\", \"value\": \"x\"}]}"
      in assertBool "should reject invalid operator" $
           isLeft (parseContextQuery json)

  , testCase "parses array of queries" $
      let json = "[{\"from\": [\"a\"], \"limit\": 7}, {\"from\": [\"b\", \"c\"], \"limitPerSource\": 1}]"
          result = parseContextQueryList json
      in case result of
        Right queries -> length queries @?= 2
        Left err -> assertBool ("unexpected parse error: " <> err) False

  , testCase "parses empty array" $
      parseContextQueryList "[]" @?= Right []
  ]

whereClauseTests :: TestTree
whereClauseTests = testGroup "WHERE clause evaluation"
  [ testCase "date >= filters out older posts" $
      withTestContentDir $ \contentRoot -> do
        writePostWithDate contentRoot "my-series" "2026-04-15-new.md" "2026-04-15"
        writePostWithDate contentRoot "my-series" "2026-03-01-old.md" "2026-03-01"
        let query = ContextQuery
              { cqFrom = ["my-series"]
              , cqWhere = [WhereCondition Date GreaterOrEqual "2026-04-01"]
              , cqOrderBy = OrderBy Filename Descending
              , cqLimit = Nothing
              , cqLimitPerSource = Nothing
              }
        results <- evaluateQuery contentRoot query
        length results @?= 1

  , testCase "date <= filters out newer posts" $
      withTestContentDir $ \contentRoot -> do
        writePostWithDate contentRoot "my-series" "2026-04-15-new.md" "2026-04-15"
        writePostWithDate contentRoot "my-series" "2026-03-01-old.md" "2026-03-01"
        let query = ContextQuery
              { cqFrom = ["my-series"]
              , cqWhere = [WhereCondition Date LessOrEqual "2026-03-15"]
              , cqOrderBy = OrderBy Filename Descending
              , cqLimit = Nothing
              , cqLimitPerSource = Nothing
              }
        results <- evaluateQuery contentRoot query
        length results @?= 1

  , testCase "title contains performs case-insensitive match" $
      withTestContentDir $ \contentRoot -> do
        writePostWithTitle contentRoot "my-series" "2026-04-15-recap.md" "Weekly Recap"
        writePostWithTitle contentRoot "my-series" "2026-04-14-thoughts.md" "Random Thoughts"
        let query = ContextQuery
              { cqFrom = ["my-series"]
              , cqWhere = [WhereCondition Title Contains "recap"]
              , cqOrderBy = OrderBy Filename Descending
              , cqLimit = Nothing
              , cqLimitPerSource = Nothing
              }
        results <- evaluateQuery contentRoot query
        length results @?= 1

  , testCase "multiple where conditions are ANDed" $
      withTestContentDir $ \contentRoot -> do
        writePostWithDate contentRoot "my-series" "2026-04-15-a.md" "2026-04-15"
        writePostWithDate contentRoot "my-series" "2026-04-10-b.md" "2026-04-10"
        writePostWithDate contentRoot "my-series" "2026-03-01-c.md" "2026-03-01"
        let query = ContextQuery
              { cqFrom = ["my-series"]
              , cqWhere =
                  [ WhereCondition Date GreaterOrEqual "2026-04-01"
                  , WhereCondition Date LessOrEqual "2026-04-12"
                  ]
              , cqOrderBy = OrderBy Filename Descending
              , cqLimit = Nothing
              , cqLimitPerSource = Nothing
              }
        results <- evaluateQuery contentRoot query
        length results @?= 1
  ]

defaultQueryTests :: TestTree
defaultQueryTests = testGroup "defaultContextQueries"
  [ testCase "produces one query" $
      length (defaultContextQueries "my-series") @?= 1

  , testCase "queries own directory with limit 7" $
      defaultContextQueries "my-series" @?=
        [ ContextQuery
            { cqFrom = ["my-series"]
            , cqWhere = []
            , cqOrderBy = OrderBy Filename Descending
            , cqLimit = Just 7
            , cqLimitPerSource = Nothing
            }
        ]

  , testCase "uses provided series ID as FROM path" $
      let queries = defaultContextQueries "chickie-loo"
      in case queries of
        [query] -> cqFrom query @?= ["chickie-loo"]
        _ -> assertBool "expected exactly one query" False
  ]

evaluationTests :: TestTree
evaluationTests = testGroup "evaluateQueries"
  [ testCase "reads posts from own directory" $
      withTestContentDir $ \contentRoot -> do
        writePosts contentRoot "my-series" ["2026-04-15-first.md", "2026-04-14-second.md"]
        let queries = defaultContextQueries "my-series"
        (selfPosts, crossPosts) <- evaluateQueries "my-series" contentRoot [] queries
        length selfPosts @?= 2
        length crossPosts @?= 0

  , testCase "limit restricts number of results" $
      withTestContentDir $ \contentRoot -> do
        writePosts contentRoot "my-series" ["2026-04-15-a.md", "2026-04-14-b.md", "2026-04-13-c.md"]
        let query = ContextQuery
              { cqFrom = ["my-series"]
              , cqWhere = []
              , cqOrderBy = OrderBy Filename Descending
              , cqLimit = Just 2
              , cqLimitPerSource = Nothing
              }
        (selfPosts, _) <- evaluateQueries "my-series" contentRoot [] [query]
        length selfPosts @?= 2

  , testCase "reading another directory yields cross-series posts" $
      withTestContentDir $ \contentRoot -> do
        writePosts contentRoot "my-series" ["2026-04-15-mine.md"]
        writePosts contentRoot "other-series" ["2026-04-15-theirs.md"]
        let metadata = [("other-series", "Other", "🔹")]
            query = ContextQuery
              { cqFrom = ["other-series"]
              , cqWhere = []
              , cqOrderBy = OrderBy Filename Descending
              , cqLimit = Just 1
              , cqLimitPerSource = Nothing
              }
        (selfPosts, crossPosts) <- evaluateQueries "my-series" contentRoot metadata [query]
        length selfPosts @?= 0
        length crossPosts @?= 1
        case crossPosts of
          (cp : _) -> cspSeriesName cp @?= "Other"
          [] -> assertBool "expected at least one cross post" False

  , testCase "multi-directory query with limitPerSource" $
      withTestContentDir $ \contentRoot -> do
        writePosts contentRoot "series-a" ["2026-04-15-a1.md", "2026-04-14-a2.md", "2026-04-13-a3.md"]
        writePosts contentRoot "series-b" ["2026-04-15-b1.md", "2026-04-14-b2.md"]
        let metadata = [("series-a", "A", "🅰️"), ("series-b", "B", "🅱️")]
            query = ContextQuery
              { cqFrom = ["series-a", "series-b"]
              , cqWhere = []
              , cqOrderBy = OrderBy Filename Descending
              , cqLimit = Nothing
              , cqLimitPerSource = Just 1
              }
        (_, crossPosts) <- evaluateQueries "my-series" contentRoot metadata [query]
        length crossPosts @?= 2

  , testCase "limitPerSource limits each directory independently" $
      withTestContentDir $ \contentRoot -> do
        writePosts contentRoot "series-a" ["2026-04-15-a1.md", "2026-04-14-a2.md", "2026-04-13-a3.md"]
        writePosts contentRoot "series-b" ["2026-04-15-b1.md", "2026-04-14-b2.md"]
        let metadata = [("series-a", "A", "🅰️"), ("series-b", "B", "🅱️")]
            query = ContextQuery
              { cqFrom = ["series-a", "series-b"]
              , cqWhere = []
              , cqOrderBy = OrderBy Filename Descending
              , cqLimit = Nothing
              , cqLimitPerSource = Just 2
              }
        (_, crossPosts) <- evaluateQueries "my-series" contentRoot metadata [query]
        length crossPosts @?= 4

  , testCase "global limit caps total across directories" $
      withTestContentDir $ \contentRoot -> do
        writePosts contentRoot "series-a" ["2026-04-15-a1.md", "2026-04-14-a2.md"]
        writePosts contentRoot "series-b" ["2026-04-15-b1.md", "2026-04-14-b2.md"]
        let metadata = [("series-a", "A", "🅰️"), ("series-b", "B", "🅱️")]
            query = ContextQuery
              { cqFrom = ["series-a", "series-b"]
              , cqWhere = []
              , cqOrderBy = OrderBy Filename Descending
              , cqLimit = Just 2
              , cqLimitPerSource = Nothing
              }
        (_, crossPosts) <- evaluateQueries "my-series" contentRoot metadata [query]
        length crossPosts @?= 2

  , testCase "orderBy date ASC sorts oldest first" $
      withTestContentDir $ \contentRoot -> do
        writePostWithDate contentRoot "my-series" "2026-04-15-new.md" "2026-04-15"
        writePostWithDate contentRoot "my-series" "2026-04-01-old.md" "2026-04-01"
        let query = ContextQuery
              { cqFrom = ["my-series"]
              , cqWhere = []
              , cqOrderBy = OrderBy Date Ascending
              , cqLimit = Just 1
              , cqLimitPerSource = Nothing
              }
        (selfPosts, _) <- evaluateQueries "my-series" contentRoot [] [query]
        length selfPosts @?= 1

  , testCase "reading own directory partitions as self posts" $
      withTestContentDir $ \contentRoot -> do
        writePosts contentRoot "my-series" ["2026-04-15-mine.md"]
        let query = ContextQuery
              { cqFrom = ["my-series"]
              , cqWhere = []
              , cqOrderBy = OrderBy Filename Descending
              , cqLimit = Just 5
              , cqLimitPerSource = Nothing
              }
        (selfPosts, crossPosts) <- evaluateQueries "my-series" contentRoot [] [query]
        length selfPosts @?= 1
        length crossPosts @?= 0

  , testCase "multiple queries combine results" $
      withTestContentDir $ \contentRoot -> do
        writePosts contentRoot "my-series" ["2026-04-15-mine.md", "2026-04-14-older.md"]
        writePosts contentRoot "other-a" ["2026-04-15-a.md"]
        writePosts contentRoot "other-b" ["2026-04-15-b.md"]
        let metadata = [("other-a", "Series A", "🅰️"), ("other-b", "Series B", "🅱️")]
            queries =
              [ ContextQuery
                  { cqFrom = ["my-series"]
                  , cqWhere = []
                  , cqOrderBy = OrderBy Filename Descending
                  , cqLimit = Just 7
                  , cqLimitPerSource = Nothing
                  }
              , ContextQuery
                  { cqFrom = ["other-a", "other-b"]
                  , cqWhere = []
                  , cqOrderBy = OrderBy Filename Descending
                  , cqLimit = Nothing
                  , cqLimitPerSource = Just 1
                  }
              ]
        (selfPosts, crossPosts) <- evaluateQueries "my-series" contentRoot metadata queries
        length selfPosts @?= 2
        length crossPosts @?= 2

  , testCase "empty queries return nothing" $
      withTestContentDir $ \contentRoot -> do
        writePosts contentRoot "my-series" ["2026-04-15-mine.md"]
        (selfPosts, crossPosts) <- evaluateQueries "my-series" contentRoot [] []
        length selfPosts @?= 0
        length crossPosts @?= 0

  , testCase "missing directory returns empty" $
      withTestContentDir $ \contentRoot -> do
        let query = ContextQuery
              { cqFrom = ["nonexistent"]
              , cqWhere = []
              , cqOrderBy = OrderBy Filename Descending
              , cqLimit = Just 7
              , cqLimitPerSource = Nothing
              }
        (selfPosts, crossPosts) <- evaluateQueries "nonexistent" contentRoot [] [query]
        length selfPosts @?= 0
        length crossPosts @?= 0

  , testCase "cross series posts carry correct metadata" $
      withTestContentDir $ \contentRoot -> do
        writePosts contentRoot "other" ["2026-04-15-post.md"]
        let metadata = [("other", "Other Name", "✨")]
            query = ContextQuery
              { cqFrom = ["other"]
              , cqWhere = []
              , cqOrderBy = OrderBy Filename Descending
              , cqLimit = Nothing
              , cqLimitPerSource = Just 1
              }
        (_, crossPosts) <- evaluateQueries "my-series" contentRoot metadata [query]
        case crossPosts of
          (cp : _) -> do
            cspSeriesName cp @?= "Other Name"
            cspSeriesIcon cp @?= "✨"
          [] -> assertBool "expected at least one cross post" False

  , testCase "unknown series uses directory name as fallback" $
      withTestContentDir $ \contentRoot -> do
        writePosts contentRoot "unlabeled" ["2026-04-15-post.md"]
        let query = ContextQuery
              { cqFrom = ["unlabeled"]
              , cqWhere = []
              , cqOrderBy = OrderBy Filename Descending
              , cqLimit = Just 1
              , cqLimitPerSource = Nothing
              }
        (_, crossPosts) <- evaluateQueries "my-series" contentRoot [] [query]
        case crossPosts of
          (cp : _) -> do
            cspSeriesName cp @?= "unlabeled"
            cspSeriesIcon cp @?= "📁"
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

writePostWithDate :: FilePath -> Text -> Text -> Text -> IO ()
writePostWithDate contentRoot seriesId filename date = do
  let seriesDir = contentRoot </> T.unpack seriesId
  createDirectoryIfMissing True seriesDir
  let content = "---\ntitle: \"Post from " <> date <> "\"\n---\nContent for " <> date
  TIO.writeFile (seriesDir </> T.unpack filename) content

writePostWithTitle :: FilePath -> Text -> Text -> Text -> IO ()
writePostWithTitle contentRoot seriesId filename title = do
  let seriesDir = contentRoot </> T.unpack seriesId
  createDirectoryIfMissing True seriesDir
  let content = "---\ntitle: \"" <> title <> "\"\n---\nContent for " <> title
  TIO.writeFile (seriesDir </> T.unpack filename) content

genOrderBy :: QC.Gen OrderBy
genOrderBy = OrderBy <$> genField <*> genDirection

genField :: QC.Gen Field
genField = QC.elements [Filename, Date, Title]

genDirection :: QC.Gen SortDirection
genDirection = QC.elements [Ascending, Descending]
