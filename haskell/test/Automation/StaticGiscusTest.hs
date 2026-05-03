module Automation.StaticGiscusTest (tests) where

import Data.Maybe (isJust)
import qualified Data.Map.Strict as Map
import qualified Data.Text as T
import Data.Text (Text)
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import qualified Data.Text.IO as TIO
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)

import Automation.StaticGiscus
import Automation.StaticGiscus.GraphQL
  ( GqlAuthor (..)
  , GqlComment (..)
  , GqlCommentsNode (..)
  , GqlDiscussion (..)
  )

-- ---------------------------------------------------------------------------
-- Pure function tests
-- ---------------------------------------------------------------------------

tests :: TestTree
tests = testGroup "StaticGiscus"
  [ pureTests
  , ioTests
  ]

pureTests :: TestTree
pureTests = testGroup "Pure functions"
  [ testGroup "normalizePathname"
    [ testCase "root stays root" $
        normalizePathname "/" @?= "/"
    , testCase "strips trailing slash" $
        normalizePathname "/blog/" @?= "/blog"
    , testCase "preserves bare path" $
        normalizePathname "/reflections/2026-03-28" @?= "/reflections/2026-03-28"
    , testCase "strips multiple trailing slashes" $
        normalizePathname "/a/b//" @?= "/a/b"
    ]

  , testGroup "slugToPathname"
    [ testCase "index slug maps to root" $
        slugToPathname "index" @?= "/"
    , testCase "simple slug gets leading slash" $
        slugToPathname "about" @?= "/about"
    , testCase "nested slug gets leading slash" $
        slugToPathname "reflections/2026-03-28" @?= "/reflections/2026-03-28"
    ]

  , testGroup "titleToPathname"
    [ testCase "title with leading slash preserved" $
        titleToPathname "/reflections/2026-03-28" @?= "/reflections/2026-03-28"
    , testCase "title without leading slash gets one" $
        titleToPathname "reflections/2026-03-28" @?= "/reflections/2026-03-28"
    ]

  , testGroup "extractSlug"
    [ testCase "extracts slug from body tag" $
        extractSlug sampleHtml @?= Just "reflections/2026-03-28"
    , testCase "returns Nothing when no data-slug" $
        extractSlug "<html><body><div>hello</div></body></html>" @?= Nothing
    , testCase "extracts index slug" $
        extractSlug "<body data-slug=\"index\">" @?= Just "index"
    ]

  , testGroup "buildCommentsMap"
    [ testCase "empty discussions yield empty map" $
        buildCommentsMap [] @?= Map.empty
    , testCase "discussion without comments is excluded" $
        buildCommentsMap [GqlDiscussion "/about" (GqlCommentsNode [])] @?= Map.empty
    , testCase "discussion with comments is included" $
        let disc = mkDiscussion "/reflections/2026-03-28" [mkGqlComment "user1" "Hello!"]
            result = buildCommentsMap [disc]
        in Map.size result @?= 1
    , testCase "pathname is normalized in map key" $
        let disc = mkDiscussion "reflections/2026-03-28/" [mkGqlComment "user1" "Hello!"]
            result = buildCommentsMap [disc]
        in assertBool "should contain normalized key" $
             Map.member "/reflections/2026-03-28" result
    ]

  , testGroup "renderStaticCommentsHtml"
    [ testCase "empty list returns empty string" $
        renderStaticCommentsHtml [] @?= ""
    , testCase "non-empty list includes data-static-giscus attribute" $
        let sc = mkStaticComment "alice" "<p>Great post!</p>"
            html = renderStaticCommentsHtml [sc]
        in assertBool "should contain data-static-giscus" $
             T.isInfixOf "data-static-giscus" html
    , testCase "non-empty list includes static-giscus-comment class" $
        let sc = mkStaticComment "alice" "<p>Great post!</p>"
            html = renderStaticCommentsHtml [sc]
        in assertBool "should contain static-giscus-comment" $
             T.isInfixOf "static-giscus-comment" html
    , testCase "rendered html includes author name" $
        let sc = mkStaticComment "alice" "<p>Great post!</p>"
            html = renderStaticCommentsHtml [sc]
        in assertBool "should contain author name" $
             T.isInfixOf "alice" html
    ]

  , testGroup "injectStaticComments"
    [ testCase "no slug returns unchanged html" $
        let html = "<html><body><div class=\"giscus\"></div></body></html>"
            cmap = Map.empty
        in injectStaticComments html cmap @?= html
    , testCase "no matching comments returns unchanged html" $
        let cmap = Map.empty
        in injectStaticComments sampleHtml cmap @?= sampleHtml
    , testCase "matching comments injected before giscus div" $
        let sc = mkStaticComment "alice" "<p>Nice!</p>"
            cmap = Map.singleton "/reflections/2026-03-28" [sc]
            result = injectStaticComments sampleHtml cmap
        in do
          assertBool "should contain data-static-giscus" $
            T.isInfixOf "data-static-giscus" result
          assertBool "should contain static-giscus-comment" $
            T.isInfixOf "static-giscus-comment" result
          assertBool "should contain author name" $
            T.isInfixOf "alice" result
    , testCase "static comments appear before giscus div" $
        let sc = mkStaticComment "carol" "<p>Interesting!</p>"
            cmap = Map.singleton "/reflections/2026-03-28" [sc]
            result = injectStaticComments sampleHtml cmap
            (beforeStatic, _) = T.breakOn "data-static-giscus" result
            (beforeGiscus, _) = T.breakOn "class=\"giscus\"" result
        in assertBool "static comments should precede giscus div" $
             T.length beforeStatic < T.length beforeGiscus
    ]

  , testGroup "findGiscusDiv"
    [ testCase "finds giscus div" $
        let html = "<div class=\"giscus\" data-repo=\"test\"></div>"
        in assertBool "should find giscus div" $
             isJust (findGiscusDiv html)
    , testCase "returns Nothing when no giscus div" $
        findGiscusDiv "<div class=\"other\"></div>" @?= Nothing
    ]
  ]

-- ---------------------------------------------------------------------------
-- IO tests (file system)
-- ---------------------------------------------------------------------------

ioTests :: TestTree
ioTests = testGroup "IO (file system)"
  [ testCase "walkHtmlFiles finds files in subdirectories" $
      withSystemTempDirectory "giscus-test" $ \tmpDir -> do
        let subDir = tmpDir </> "reflections"
        createDirectoryIfMissing True subDir
        TIO.writeFile (tmpDir </> "index.html") "<html></html>"
        TIO.writeFile (subDir </> "page.html") "<html></html>"
        TIO.writeFile (subDir </> "image.png") "binary"
        files <- walkHtmlFiles tmpDir
        assertBool "should find top-level html" $
          any (isSuffixOf' "index.html") files
        assertBool "should find nested html" $
          any (isSuffixOf' "page.html") files
        assertBool "should not include non-html" $
          not (any (isSuffixOf' "image.png") files)
        length files @?= 2

  , testCase "walkHtmlFiles finds deeply nested files" $
      withSystemTempDirectory "giscus-test" $ \tmpDir -> do
        let deepDir = tmpDir </> "a" </> "b" </> "c"
        createDirectoryIfMissing True deepDir
        TIO.writeFile (deepDir </> "deep.html") "<html></html>"
        files <- walkHtmlFiles tmpDir
        assertBool "should find deeply nested html" $
          any (isSuffixOf' "deep.html") files
        length files @?= 1

  , testCase "walkHtmlFiles returns empty for non-existent directory" $
      do
        files <- walkHtmlFiles "/tmp/non-existent-dir-giscus-test-1234"
        files @?= []

  , testCase "processHtmlFiles injects into nested files" $
      withSystemTempDirectory "giscus-test" $ \tmpDir -> do
        let subDir = tmpDir </> "reflections"
        createDirectoryIfMissing True subDir
        TIO.writeFile (subDir </> "2026-03-28.html") sampleHtml
        let sc = mkStaticComment "bob" "<p>Awesome!</p>"
            cmap = Map.singleton "/reflections/2026-03-28" [sc]
        injected <- processHtmlFiles tmpDir cmap
        length injected @?= 1
        modified <- TIO.readFile (subDir </> "2026-03-28.html")
        assertBool "modified file should contain data-static-giscus" $
          T.isInfixOf "data-static-giscus" modified
        assertBool "modified file should contain author" $
          T.isInfixOf "bob" modified

  , testCase "processHtmlFiles leaves non-matching files unchanged" $
      withSystemTempDirectory "giscus-test" $ \tmpDir -> do
        TIO.writeFile (tmpDir </> "about.html") sampleHtml
        let cmap = Map.singleton "/other-page" [mkStaticComment "eve" "<p>Hi!</p>"]
        injected <- processHtmlFiles tmpDir cmap
        length injected @?= 0
        content <- TIO.readFile (tmpDir </> "about.html")
        content @?= sampleHtml
  ]

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

sampleHtml :: Text
sampleHtml = "<html><body data-slug=\"reflections/2026-03-28\"><article>Content</article><div class=\"giscus\" data-repo=\"test\"></div></body></html>"

mkGqlComment :: Text -> Text -> GqlComment
mkGqlComment username body = GqlComment
  { bodyHtml = "<p>" <> body <> "</p>"
  , author = Just (GqlAuthor username ("https://github.com/" <> username))
  , createdAt = "2026-01-15T10:00:00Z"
  }

mkDiscussion :: Text -> [GqlComment] -> GqlDiscussion
mkDiscussion discussionTitle discussionComments = GqlDiscussion
  { title = discussionTitle
  , comments = GqlCommentsNode discussionComments
  }

mkStaticComment :: Text -> Text -> StaticComment
mkStaticComment commentAuthor body = StaticComment
  { author      = commentAuthor
  , authorUrl   = "https://github.com/" <> commentAuthor
  , scBodyHtml  = body
  , scCreatedAt = "2026-01-15T10:00:00Z"
  }

isSuffixOf' :: String -> FilePath -> Bool
isSuffixOf' suffix path = drop (length path - length suffix) path == suffix
