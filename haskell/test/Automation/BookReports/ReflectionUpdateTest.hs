module Automation.BookReports.ReflectionUpdateTest (tests) where

import qualified Data.Text as T
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)

import Automation.BookReports.ReflectionUpdate
  ( booksSectionHeading
  , buildBookWikilinkLine
  , insertOrUpdateBooksSection
  , reflectionContainsBookWikilink
  )
import Automation.BookReports.Types (mkBookSlug, mkBookTitle)

trailingHeadings :: [T.Text]
trailingHeadings =
  [ "## [📊 Changes]"
  , "<!-- bluesky-embed -->"
  , "<!-- mastodon-embed -->"
  ]

tests :: TestTree
tests = testGroup "BookReports.ReflectionUpdate"
  [ testCase "buildBookWikilinkLine produces obsidian wikilink with auto marker" $ do
      slug <- expectRight (mkBookSlug "sapiens")
      title <- expectRight (mkBookTitle "Sapiens")
      buildBookWikilinkLine slug title
        @?= "- 🆕📚 [[books/sapiens|Sapiens]] 🤖"

  , testCase "inserts new Books section before trailing sections" $ do
      slug <- expectRight (mkBookSlug "sapiens")
      title <- expectRight (mkBookTitle "Sapiens")
      let content = T.unlines
            [ "# 2026-05-05"
            , ""
            , "Some body."
            , ""
            , "## [📊 Changes]"
            , ""
            ]
          updated = insertOrUpdateBooksSection trailingHeadings slug title content
      assertBool "section heading present" (T.isInfixOf booksSectionHeading updated)
      assertBool "wikilink present"        (T.isInfixOf "[[books/sapiens|Sapiens]]" updated)
      assertBool "books section appears before changes"
        (T.isInfixOf (booksSectionHeading <> "\n- 🆕📚 [[books/sapiens|Sapiens]] 🤖") updated)

  , testCase "appends under existing Books section instead of duplicating" $ do
      slug <- expectRight (mkBookSlug "sapiens")
      title <- expectRight (mkBookTitle "Sapiens")
      let content = T.unlines
            [ "# 2026-05-05"
            , booksSectionHeading
            , "- [[books/cradle-to-cradle|♻️ Cradle to Cradle]]"
            , ""
            , "## [📊 Changes]"
            ]
          updated = insertOrUpdateBooksSection trailingHeadings slug title content
      assertBool "still has cradle"         (T.isInfixOf "cradle-to-cradle" updated)
      assertBool "now has sapiens wikilink" (T.isInfixOf "[[books/sapiens|Sapiens]]" updated)
      length (T.splitOn booksSectionHeading updated) @?= 2

  , testCase "is idempotent — running twice does not duplicate the link" $ do
      slug <- expectRight (mkBookSlug "sapiens")
      title <- expectRight (mkBookTitle "Sapiens")
      let content = T.unlines
            [ "# 2026-05-05"
            , booksSectionHeading
            , "- [[books/sapiens|Sapiens]]"
            ]
          updated = insertOrUpdateBooksSection trailingHeadings slug title content
      updated @?= content

  , testCase "appends fresh section at end when no trailing sections present" $ do
      slug <- expectRight (mkBookSlug "sapiens")
      title <- expectRight (mkBookTitle "Sapiens")
      let content = "# 2026-05-05\n\nSome body.\n"
          updated = insertOrUpdateBooksSection trailingHeadings slug title content
      assertBool "section appended" (T.isInfixOf booksSectionHeading updated)

  , testCase "reflectionContainsBookWikilink detects existing link" $ do
      slug <- expectRight (mkBookSlug "sapiens")
      assertBool "detects link"
        (reflectionContainsBookWikilink slug "- [[books/sapiens|Sapiens]]")
      assertBool "doesn't false-positive on different slug"
        (not (reflectionContainsBookWikilink slug "- [[books/cradle|Cradle]]"))
  ]
  where
    expectRight (Right v) = pure v
    expectRight (Left e)  = error (T.unpack e)
