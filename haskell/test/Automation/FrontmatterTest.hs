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

  , testGroup "quoteYamlValue"
      [ testCase "plain text stays unquoted" $
          quoteYamlValue "hello" @?= "hello"
      , testCase "empty string becomes quoted" $
          quoteYamlValue "" @?= "\"\""
      , testCase "value with colon gets quoted" $
          quoteYamlValue "https://example.com" @?= "\"https://example.com\""
      , testCase "value with brackets gets quoted" $
          quoteYamlValue "[[bryan-grounds]]" @?= "\"[[bryan-grounds]]\""
      , testCase "boolean false gets quoted" $
          quoteYamlValue "false" @?= "\"false\""
      , testCase "boolean true gets quoted" $
          quoteYamlValue "true" @?= "\"true\""
      , testCase "null gets quoted" $
          quoteYamlValue "null" @?= "\"null\""
      , testCase "numeric value gets quoted" $
          quoteYamlValue "42" @?= "\"42\""
      , testCase "date-like value gets quoted" $
          quoteYamlValue "2026-03-28" @?= "\"2026-03-28\""
      , testCase "value with hash gets quoted" $
          quoteYamlValue "before # comment" @?= "\"before # comment\""
      , testCase "escapes internal quotes" $
          quoteYamlValue "say \"hello\"" @?= "\"say \\\"hello\\\"\""
      , testCase "preserves backslashes in plain values" $
          quoteYamlValue "path\\to" @?= "path\\to"
      , testCase "value with leading space gets quoted" $
          quoteYamlValue " leading" @?= "\" leading\""
      , testCase "value with comma gets quoted" $
          quoteYamlValue "a, b" @?= "\"a, b\""
      , testCase "value with curly braces gets quoted" $
          quoteYamlValue "{key: val}" @?= "\"{key: val}\""
      , testCase "value with @ gets quoted (YAML reserved indicator)" $
          quoteYamlValue "@cf/black-forest-labs/flux-1-schnell" @?= "\"@cf/black-forest-labs/flux-1-schnell\""
      , testCase "value with backtick gets quoted (YAML reserved indicator)" $
          quoteYamlValue "code `inline`" @?= "\"code `inline`\""
      ]
  ]
