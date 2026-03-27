module Automation.FrontmatterTest (tests) where

import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))
import qualified Data.Map.Strict as Map

import Automation.Frontmatter

tests :: TestTree
tests = testGroup "Frontmatter"
  [ testCase "parseFrontmatter parses valid frontmatter" $
      let content = "---\ntitle: Hello\nURL: https://example.com\n---\nBody text"
          (fm, body) = parseFrontmatter content
      in do
        Map.lookup "title" fm @?= Just "Hello"
        Map.lookup "URL" fm @?= Just "https://example.com"
        body @?= "Body text"

  , testCase "parseFrontmatter handles missing delimiters" $
      let content = "No frontmatter here"
          (fm, body) = parseFrontmatter content
      in do
        fm @?= Map.empty
        body @?= content

  , testCase "parseFrontmatter strips quotes from values" $
      let content = "---\ntitle: \"Quoted Title\"\n---\nBody"
          (fm, _) = parseFrontmatter content
      in Map.lookup "title" fm @?= Just "Quoted Title"

  , testCase "getReflectionPath builds correct path" $
      getReflectionPath "2026-03-26" "/vault/reflections" @?= "/vault/reflections/2026-03-26.md"
  ]
