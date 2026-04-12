module Automation.BlogImage.TitleExtractionTest (tests) where

import qualified Data.Text as T
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))
import Test.Tasty.QuickCheck (testProperty)

import Automation.BlogImage.TitleExtraction

tests :: TestTree
tests = testGroup "BlogImage.TitleExtraction"
  [ testGroup "extractTitle"
      [ testCase "extracts from frontmatter title field" $
          extractTitle "---\ntitle: My Post\n---\nbody" @?= "My Post"
      , testCase "extracts from H1 heading" $
          extractTitle "# Hello World\nbody" @?= "Hello World"
      , testCase "prefers frontmatter over H1" $
          extractTitle "---\ntitle: FM Title\n---\n# H1 Title\nbody" @?= "FM Title"
      , testCase "returns empty for no title source" $
          extractTitle "just some text without title" @?= ""
      , testCase "strips quotes from frontmatter title" $
          extractTitle "---\ntitle: \"Quoted Title\"\n---\n" @?= "Quoted Title"
      , testCase "strips single quotes from frontmatter title" $
          extractTitle "---\ntitle: 'Single Quoted'\n---\n" @?= "Single Quoted"
      , testCase "empty frontmatter falls back to H1" $
          extractTitle "---\n---\n# Fallback Title" @?= "Fallback Title"
      , testCase "frontmatter with non-title fields falls back to H1" $
          extractTitle "---\ntags: foo\n---\n# H1 Here" @?= "H1 Here"
      ]
  , testGroup "extractTitleFromFrontmatter"
      [ testCase "returns Nothing for empty list" $
          extractTitleFromFrontmatter [] False @?= Nothing
      , testCase "finds title inside frontmatter" $
          extractTitleFromFrontmatter ["---", "title: Test", "---"] False @?= Just "Test"
      , testCase "returns Nothing when not in frontmatter" $
          extractTitleFromFrontmatter ["title: Test"] False @?= Nothing
      , testCase "returns Nothing when title is after closing delimiter" $
          extractTitleFromFrontmatter ["---", "---", "title: Test"] False @?= Nothing
      ]
  , testGroup "findH1Title"
      [ testCase "finds H1 heading" $
          findH1Title ["# My Title", "body text"] @?= Just "My Title"
      , testCase "returns Nothing when no H1" $
          findH1Title ["## H2 heading", "body"] @?= Nothing
      , testCase "returns Nothing for empty list" $
          findH1Title [] @?= Nothing
      , testCase "trims whitespace from H1" $
          findH1Title ["#  Spaced Title  "] @?= Just "Spaced Title"
      ]
  , testGroup "stripQuotes"
      [ testCase "strips double quotes" $
          stripQuotes "\"hello\"" @?= "hello"
      , testCase "strips single quotes" $
          stripQuotes "'hello'" @?= "hello"
      , testCase "leaves unquoted text unchanged" $
          stripQuotes "hello" @?= "hello"
      , testCase "strips mismatched outer quotes" $
          stripQuotes "\"hello'" @?= "hello"
      , testCase "handles empty string" $
          stripQuotes "" @?= ""
      , testCase "handles single character" $
          stripQuotes "x" @?= "x"
      , testCase "handles single quote character" $
          stripQuotes "\"" @?= ""
      ]
  , testGroup "properties"
      [ testProperty "extractTitle finds H1 when title has no newlines" $
          \titleText -> let title = T.filter (/= '\n') (T.pack titleText)
                            content = "# " <> title <> "\nbody"
                        in not (T.null (T.strip title))
                           ==> (extractTitle content == T.strip title)
      ]
  ]
  where
    (==>) :: Bool -> Bool -> Bool
    (==>) False _ = True
    (==>) True  b = b
