module Automation.HtmlTest (tests) where

import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))

import Automation.Html

tests :: TestTree
tests = testGroup "Html"
  [ testCase "escapeHtml escapes ampersand" $
      escapeHtml "a & b" @?= "a &amp; b"

  , testCase "escapeHtml escapes angle brackets" $
      escapeHtml "<div>" @?= "&lt;div&gt;"

  , testCase "escapeHtml escapes quotes" $
      escapeHtml "he said \"hi\"" @?= "he said &quot;hi&quot;"

  , testCase "escapeHtml escapes single quotes" $
      escapeHtml "it's" @?= "it&#39;s"

  , testCase "textToHtml converts newlines to br" $
      textToHtml "line1\nline2" @?= "line1<br>line2"

  , testCase "textToHtml escapes and converts" $
      textToHtml "a & b\nc" @?= "a &amp; b<br>c"

  , testCase "formatDisplayDate formats correctly" $
      formatDisplayDate "2026-03-10" @?= "March 10, 2026"

  , testCase "formatDisplayDate handles single digit day" $
      formatDisplayDate "2026-01-05" @?= "January 5, 2026"

  , testCase "monthNames has 12 entries" $
      length monthNames @?= 12
  ]
