module Automation.FrontmatterTest (tests) where

import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import Test.Tasty.QuickCheck (testProperty)
import qualified Test.QuickCheck as QC
import qualified Data.Map.Strict as Map
import qualified Data.Text as T

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

  , testGroup "YamlValue rendering"
      [ testCase "YamlBool True renders as native YAML true" $
          renderYamlValue (YamlBool True) @?= "true"
      , testCase "YamlBool False renders as native YAML false" $
          renderYamlValue (YamlBool False) @?= "false"
      , testCase "YamlText renders as double-quoted string" $
          renderYamlValue (YamlText "hello") @?= "\"hello\""
      , testCase "YamlText empty string renders as empty quotes" $
          renderYamlValue (YamlText "") @?= "\"\""
      , testCase "YamlText with special chars is properly escaped" $
          renderYamlValue (YamlText "@cf/model") @?= "\"@cf/model\""
      , testCase "YamlText with colon is properly quoted" $
          renderYamlValue (YamlText "https://example.com") @?= "\"https://example.com\""
      ]

  , testGroup "quoteYamlValue"
      [ testCase "plain text is always quoted" $
          quoteYamlValue "hello" @?= "\"hello\""
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
      , testCase "escapes backslashes" $
          quoteYamlValue "path\\to" @?= "\"path\\\\to\""
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
      , testCase "escapes newlines" $
          quoteYamlValue "line1\nline2" @?= "\"line1\\nline2\""
      , testCase "escapes carriage returns" $
          quoteYamlValue "line1\rline2" @?= "\"line1\\rline2\""
      , testCase "escapes tabs" $
          quoteYamlValue "col1\tcol2" @?= "\"col1\\tcol2\""
      , testCase "strips null bytes" $
          quoteYamlValue "ab\0cd" @?= "\"abcd\""
      , testCase "value starting with ! is safely quoted" $
          quoteYamlValue "!important tag" @?= "\"!important tag\""
      , testCase "value starting with * is safely quoted" $
          quoteYamlValue "*alias ref" @?= "\"*alias ref\""
      , testCase "value starting with & is safely quoted" $
          quoteYamlValue "&anchor" @?= "\"&anchor\""
      , testCase "value starting with | is safely quoted" $
          quoteYamlValue "| block scalar" @?= "\"| block scalar\""
      , testCase "value starting with > is safely quoted" $
          quoteYamlValue "> folded" @?= "\"> folded\""
      , testCase "value starting with ? is safely quoted" $
          quoteYamlValue "? complex key" @?= "\"? complex key\""
      , testCase "value starting with % is safely quoted" $
          quoteYamlValue "%directive" @?= "\"%directive\""
      , testCase "YAML boolean yes is safely quoted" $
          quoteYamlValue "yes" @?= "\"yes\""
      , testCase "YAML boolean no is safely quoted" $
          quoteYamlValue "no" @?= "\"no\""
      , testCase "tilde (YAML null) is safely quoted" $
          quoteYamlValue "~" @?= "\"~\""
      , testCase "image model with slash is safely quoted" $
          quoteYamlValue "black-forest-labs/FLUX.1-schnell" @?= "\"black-forest-labs/FLUX.1-schnell\""
      , testCase "combined escaping: backslash and quote" $
          quoteYamlValue "say \\\"hi\\\"" @?= "\"say \\\\\\\"hi\\\\\\\"\""
      , testCase "combined escaping: newline and quote" $
          quoteYamlValue "line1\n\"line2\"" @?= "\"line1\\n\\\"line2\\\"\""
      ]
  , testGroup "quoteYamlValue properties"
      [ testProperty "output always starts and ends with double quotes" $
          \(QC.ASCIIString s) ->
            let t = T.pack s
                result = quoteYamlValue t
            in T.head result == '"' && T.last result == '"'
      , testProperty "output never contains unescaped newlines" $
          \(QC.ASCIIString s) ->
            let result = quoteYamlValue (T.pack s)
                inner = T.drop 1 (T.dropEnd 1 result)
            in not (T.isInfixOf "\n" inner)
      , testProperty "output never contains unescaped carriage returns" $
          \(QC.ASCIIString s) ->
            let result = quoteYamlValue (T.pack s)
                inner = T.drop 1 (T.dropEnd 1 result)
            in not (T.isInfixOf "\r" inner)
      , testProperty "output never contains unescaped tabs" $
          \(QC.ASCIIString s) ->
            let result = quoteYamlValue (T.pack s)
                inner = T.drop 1 (T.dropEnd 1 result)
            in not (T.isInfixOf "\t" inner)
      , testProperty "output never contains null bytes" $
          \(QC.ASCIIString s) ->
            let result = quoteYamlValue (T.pack s)
            in not (T.isInfixOf "\0" result)
      ]
  ]
