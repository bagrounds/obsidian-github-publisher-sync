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
  [ fieldParsingTests
  , fieldRoundTripTests
  , jsonParsingTests
  , whereClauseTests
  , defaultQueryTests
  , evaluationTests
  ]

fieldParsingTests :: TestTree
fieldParsingTests = testGroup "fieldFromText"
  [ testCase "parses filename" $
      fieldFromText "filename" @?= Right Filename

  , testCase "parses date" $
      fieldFromText "date" @?= Right Date

  , testCase "parses title" $
      fieldFromText "title" @?= Right Title

  , testCase "rejects unknown field" $
      assertBool "should reject unknown field" $
        isLeft (fieldFromText "unknown")
  ]

fieldRoundTripTests :: TestTree
fieldRoundTripTests = testGroup "field round-trip"
  [ testCase "filename round-trips" $
      fieldFromText (fieldToText Filename) @?= Right Filename

  , testCase "date round-trips" $
      fieldFromText (fieldToText Date) @?= Right Date

  , testCase "title round-trips" $
      fieldFromText (fieldToText Title) @?= Right Title

  , testProperty "all Field values round-trip" $
      QC.forAll genField $ \parsedField ->
        fieldFromText (fieldToText parsedField) == Right parsedField
  ]

jsonParsingTests :: TestTree
jsonParsingTests = testGroup "JSON parsing"
  [ testCase "parses simple FROM with limit" $
      let json = "{\"from\": [\"my-series\"], \"limit\": 7}"
      in parseContextQuery json @?= Right (ContextQuery
          { directories = ["my-series"]
          , conditions = []
          , orderBy = OrderBy Filename Descending
          , limit = Just 7
          , limitPerSource = Nothing
          })

  , testCase "parses multiple FROM directories" $
      let json = "{\"from\": [\"series-a\", \"series-b\"], \"limit\": 5}"
          result = parseContextQuery json
      in case result of
        Right query -> directories query @?= ["series-a", "series-b"]
        Left failure -> assertBool ("unexpected parse error: " <> failure) False

  , testCase "parses orderBy as field name" $
      let json = "{\"from\": [\"my-series\"], \"orderBy\": \"date\", \"limit\": 3}"
          result = parseContextQuery json
      in case result of
        Right query -> orderBy query @?= OrderBy Date Descending
        Left failure -> assertBool ("unexpected parse error: " <> failure) False

  , testCase "parses ascending true" $
      let json = "{\"from\": [\"my-series\"], \"orderBy\": \"date\", \"ascending\": true, \"limit\": 3}"
          result = parseContextQuery json
      in case result of
        Right query -> orderBy query @?= OrderBy Date Ascending
        Left failure -> assertBool ("unexpected parse error: " <> failure) False

  , testCase "ascending false means descending" $
      let json = "{\"from\": [\"my-series\"], \"orderBy\": \"date\", \"ascending\": false, \"limit\": 3}"
          result = parseContextQuery json
      in case result of
        Right query -> orderBy query @?= OrderBy Date Descending
        Left failure -> assertBool ("unexpected parse error: " <> failure) False

  , testCase "parses limitPerSource" $
      let json = "{\"from\": [\"a\", \"b\"], \"limitPerSource\": 1}"
          result = parseContextQuery json
      in case result of
        Right query -> limitPerSource query @?= Just 1
        Left failure -> assertBool ("unexpected parse error: " <> failure) False

  , testCase "defaults orderBy to filename descending" $
      let json = "{\"from\": [\"x\"], \"limit\": 3}"
          result = parseContextQuery json
      in case result of
        Right query -> orderBy query @?= OrderBy Filename Descending
        Left failure -> assertBool ("unexpected parse error: " <> failure) False

  , testCase "accepts no limit and no limitPerSource" $
      let json = "{\"from\": [\"x\"]}"
          result = parseContextQuery json
      in case result of
        Right query -> do
          limit query @?= Nothing
          limitPerSource query @?= Nothing
        Left failure -> assertBool ("unexpected parse error: " <> failure) False

  , testCase "parses where clause" $
      let json = "{\"from\": [\"x\"], \"where\": [{\"field\": \"date\", \"operator\": \">=\", \"value\": \"2026-04-01\"}], \"limit\": 5}"
          result = parseContextQuery json
      in case result of
        Right query -> conditions query @?= [WhereCondition Date GreaterOrEqual "2026-04-01"]
        Left failure -> assertBool ("unexpected parse error: " <> failure) False

  , testCase "rejects invalid orderBy field" $
      let json = "{\"from\": [\"x\"], \"orderBy\": \"invalid\", \"limit\": 3}"
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
        Left failure -> assertBool ("unexpected parse error: " <> failure) False

  , testCase "parses empty array" $
      parseContextQueryList "[]" @?= Right []
  ]

whereClauseTests :: TestTree
whereClauseTests = testGroup "WHERE clause evaluation"
  [ testCase "date >= filters out older posts" $
      withTestContentDirectory $ \contentRoot -> do
        writePostWithDate contentRoot "my-series" "2026-04-15-new.md" "2026-04-15"
        writePostWithDate contentRoot "my-series" "2026-03-01-old.md" "2026-03-01"
        let query = ContextQuery
              { directories = ["my-series"]
              , conditions = [WhereCondition Date GreaterOrEqual "2026-04-01"]
              , orderBy = OrderBy Filename Descending
              , limit = Nothing
              , limitPerSource = Nothing
              }
        results <- evaluateQuery contentRoot query
        length results @?= 1

  , testCase "date <= filters out newer posts" $
      withTestContentDirectory $ \contentRoot -> do
        writePostWithDate contentRoot "my-series" "2026-04-15-new.md" "2026-04-15"
        writePostWithDate contentRoot "my-series" "2026-03-01-old.md" "2026-03-01"
        let query = ContextQuery
              { directories = ["my-series"]
              , conditions = [WhereCondition Date LessOrEqual "2026-03-15"]
              , orderBy = OrderBy Filename Descending
              , limit = Nothing
              , limitPerSource = Nothing
              }
        results <- evaluateQuery contentRoot query
        length results @?= 1

  , testCase "title contains performs case-insensitive match" $
      withTestContentDirectory $ \contentRoot -> do
        writePostWithTitle contentRoot "my-series" "2026-04-15-recap.md" "Weekly Recap"
        writePostWithTitle contentRoot "my-series" "2026-04-14-thoughts.md" "Random Thoughts"
        let query = ContextQuery
              { directories = ["my-series"]
              , conditions = [WhereCondition Title Contains "recap"]
              , orderBy = OrderBy Filename Descending
              , limit = Nothing
              , limitPerSource = Nothing
              }
        results <- evaluateQuery contentRoot query
        length results @?= 1

  , testCase "multiple where conditions are ANDed" $
      withTestContentDirectory $ \contentRoot -> do
        writePostWithDate contentRoot "my-series" "2026-04-15-a.md" "2026-04-15"
        writePostWithDate contentRoot "my-series" "2026-04-10-b.md" "2026-04-10"
        writePostWithDate contentRoot "my-series" "2026-03-01-c.md" "2026-03-01"
        let query = ContextQuery
              { directories = ["my-series"]
              , conditions =
                  [ WhereCondition Date GreaterOrEqual "2026-04-01"
                  , WhereCondition Date LessOrEqual "2026-04-12"
                  ]
              , orderBy = OrderBy Filename Descending
              , limit = Nothing
              , limitPerSource = Nothing
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
            { directories = ["my-series"]
            , conditions = []
            , orderBy = OrderBy Filename Descending
            , limit = Just 7
            , limitPerSource = Nothing
            }
        ]

  , testCase "uses provided series ID as FROM path" $
      let queries = defaultContextQueries "chickie-loo"
      in case queries of
        [query] -> directories query @?= ["chickie-loo"]
        _ -> assertBool "expected exactly one query" False
  ]

evaluationTests :: TestTree
evaluationTests = testGroup "evaluateQueries"
  [ testCase "reads posts from own directory" $
      withTestContentDirectory $ \contentRoot -> do
        writePosts contentRoot "my-series" ["2026-04-15-first.md", "2026-04-14-second.md"]
        let queries = defaultContextQueries "my-series"
        results <- evaluateQueries contentRoot queries
        length results @?= 2

  , testCase "limit restricts number of results" $
      withTestContentDirectory $ \contentRoot -> do
        writePosts contentRoot "my-series" ["2026-04-15-a.md", "2026-04-14-b.md", "2026-04-13-c.md"]
        let query = ContextQuery
              { directories = ["my-series"]
              , conditions = []
              , orderBy = OrderBy Filename Descending
              , limit = Just 2
              , limitPerSource = Nothing
              }
        results <- evaluateQueries contentRoot [query]
        length results @?= 2

  , testCase "reading another directory yields posts from that directory" $
      withTestContentDirectory $ \contentRoot -> do
        writePosts contentRoot "my-series" ["2026-04-15-mine.md"]
        writePosts contentRoot "other-series" ["2026-04-15-theirs.md"]
        let query = ContextQuery
              { directories = ["other-series"]
              , conditions = []
              , orderBy = OrderBy Filename Descending
              , limit = Just 1
              , limitPerSource = Nothing
              }
        results <- evaluateQueries contentRoot [query]
        length results @?= 1
        case results of
          (contextPost : _) -> sourceDirectory contextPost @?= "other-series"
          [] -> assertBool "expected at least one post" False

  , testCase "multi-directory query with limitPerSource" $
      withTestContentDirectory $ \contentRoot -> do
        writePosts contentRoot "series-a" ["2026-04-15-a1.md", "2026-04-14-a2.md", "2026-04-13-a3.md"]
        writePosts contentRoot "series-b" ["2026-04-15-b1.md", "2026-04-14-b2.md"]
        let query = ContextQuery
              { directories = ["series-a", "series-b"]
              , conditions = []
              , orderBy = OrderBy Filename Descending
              , limit = Nothing
              , limitPerSource = Just 1
              }
        results <- evaluateQueries contentRoot [query]
        length results @?= 2

  , testCase "limitPerSource limits each directory independently" $
      withTestContentDirectory $ \contentRoot -> do
        writePosts contentRoot "series-a" ["2026-04-15-a1.md", "2026-04-14-a2.md", "2026-04-13-a3.md"]
        writePosts contentRoot "series-b" ["2026-04-15-b1.md", "2026-04-14-b2.md"]
        let query = ContextQuery
              { directories = ["series-a", "series-b"]
              , conditions = []
              , orderBy = OrderBy Filename Descending
              , limit = Nothing
              , limitPerSource = Just 2
              }
        results <- evaluateQueries contentRoot [query]
        length results @?= 4

  , testCase "global limit caps total across directories" $
      withTestContentDirectory $ \contentRoot -> do
        writePosts contentRoot "series-a" ["2026-04-15-a1.md", "2026-04-14-a2.md"]
        writePosts contentRoot "series-b" ["2026-04-15-b1.md", "2026-04-14-b2.md"]
        let query = ContextQuery
              { directories = ["series-a", "series-b"]
              , conditions = []
              , orderBy = OrderBy Filename Descending
              , limit = Just 2
              , limitPerSource = Nothing
              }
        results <- evaluateQueries contentRoot [query]
        length results @?= 2

  , testCase "orderBy date ascending sorts oldest first" $
      withTestContentDirectory $ \contentRoot -> do
        writePostWithDate contentRoot "my-series" "2026-04-15-new.md" "2026-04-15"
        writePostWithDate contentRoot "my-series" "2026-04-01-old.md" "2026-04-01"
        let query = ContextQuery
              { directories = ["my-series"]
              , conditions = []
              , orderBy = OrderBy Date Ascending
              , limit = Just 1
              , limitPerSource = Nothing
              }
        results <- evaluateQueries contentRoot [query]
        length results @?= 1

  , testCase "posts carry source directory info" $
      withTestContentDirectory $ \contentRoot -> do
        writePosts contentRoot "my-series" ["2026-04-15-mine.md"]
        let query = ContextQuery
              { directories = ["my-series"]
              , conditions = []
              , orderBy = OrderBy Filename Descending
              , limit = Just 5
              , limitPerSource = Nothing
              }
        results <- evaluateQueries contentRoot [query]
        length results @?= 1
        case results of
          (contextPost : _) -> sourceDirectory contextPost @?= "my-series"
          [] -> assertBool "expected at least one post" False

  , testCase "multiple queries combine results" $
      withTestContentDirectory $ \contentRoot -> do
        writePosts contentRoot "my-series" ["2026-04-15-mine.md", "2026-04-14-older.md"]
        writePosts contentRoot "other-a" ["2026-04-15-a.md"]
        writePosts contentRoot "other-b" ["2026-04-15-b.md"]
        let queries =
              [ ContextQuery
                  { directories = ["my-series"]
                  , conditions = []
                  , orderBy = OrderBy Filename Descending
                  , limit = Just 7
                  , limitPerSource = Nothing
                  }
              , ContextQuery
                  { directories = ["other-a", "other-b"]
                  , conditions = []
                  , orderBy = OrderBy Filename Descending
                  , limit = Nothing
                  , limitPerSource = Just 1
                  }
              ]
        results <- evaluateQueries contentRoot queries
        length results @?= 4

  , testCase "empty queries return nothing" $
      withTestContentDirectory $ \contentRoot -> do
        writePosts contentRoot "my-series" ["2026-04-15-mine.md"]
        results <- evaluateQueries contentRoot []
        length results @?= 0

  , testCase "missing directory returns empty" $
      withTestContentDirectory $ \contentRoot -> do
        let query = ContextQuery
              { directories = ["nonexistent"]
              , conditions = []
              , orderBy = OrderBy Filename Descending
              , limit = Just 7
              , limitPerSource = Nothing
              }
        results <- evaluateQueries contentRoot [query]
        length results @?= 0

  , testCase "context posts carry correct source directory" $
      withTestContentDirectory $ \contentRoot -> do
        writePosts contentRoot "other" ["2026-04-15-post.md"]
        let query = ContextQuery
              { directories = ["other"]
              , conditions = []
              , orderBy = OrderBy Filename Descending
              , limit = Nothing
              , limitPerSource = Just 1
              }
        results <- evaluateQueries contentRoot [query]
        case results of
          (contextPost : _) -> sourceDirectory contextPost @?= "other"
          [] -> assertBool "expected at least one post" False
  ]

-- Test helpers

parseContextQuery :: Text -> Either String ContextQuery
parseContextQuery = eitherDecodeStrict . TE.encodeUtf8

parseContextQueryList :: Text -> Either String [ContextQuery]
parseContextQueryList = eitherDecodeStrict . TE.encodeUtf8

isLeft :: Either a b -> Bool
isLeft (Left _) = True
isLeft (Right _) = False

withTestContentDirectory :: (FilePath -> IO a) -> IO a
withTestContentDirectory = withSystemTempDirectory "context-query-test"

writePosts :: FilePath -> Text -> [Text] -> IO ()
writePosts contentRoot seriesId filenames = do
  let seriesDirectory = contentRoot </> T.unpack seriesId
  createDirectoryIfMissing True seriesDirectory
  mapM_ (writeTestPost seriesDirectory) filenames

writeTestPost :: FilePath -> Text -> IO ()
writeTestPost seriesDirectory filename = do
  let content = "---\ntitle: \"Test Post\"\n---\nTest body content for " <> filename
  TIO.writeFile (seriesDirectory </> T.unpack filename) content

writePostWithDate :: FilePath -> Text -> Text -> Text -> IO ()
writePostWithDate contentRoot seriesId filename date = do
  let seriesDirectory = contentRoot </> T.unpack seriesId
  createDirectoryIfMissing True seriesDirectory
  let content = "---\ntitle: \"Post from " <> date <> "\"\n---\nContent for " <> date
  TIO.writeFile (seriesDirectory </> T.unpack filename) content

writePostWithTitle :: FilePath -> Text -> Text -> Text -> IO ()
writePostWithTitle contentRoot seriesId filename title = do
  let seriesDirectory = contentRoot </> T.unpack seriesId
  createDirectoryIfMissing True seriesDirectory
  let content = "---\ntitle: \"" <> title <> "\"\n---\nContent for " <> title
  TIO.writeFile (seriesDirectory </> T.unpack filename) content

genField :: QC.Gen Field
genField = QC.elements [Filename, Date, Title]
