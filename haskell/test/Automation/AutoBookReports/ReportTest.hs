{-# LANGUAGE OverloadedStrings #-}

module Automation.AutoBookReports.ReportTest (tests) where

import qualified Data.Text as T
import Test.Tasty
import Test.Tasty.HUnit

import Automation.AutoBookReports.Report

tests :: TestTree
tests = testGroup "AutoBookReports.Report"
  [ testGroup "generateBookSlug"
    [ testCase "lowercases" $
        generateBookSlug "Deep Work" @?= "deep-work"
    , testCase "drops emojis" $
        generateBookSlug "📚 Deep Work" @?= "deep-work"
    , testCase "collapses runs of non-alnum" $
        generateBookSlug "Deep!!!Work" @?= "deep-work"
    , testCase "trims hyphens" $
        generateBookSlug "  --Deep Work--  " @?= "deep-work"
    , testCase "handles colons in subtitles" $
        generateBookSlug "Deep Work: Rules for Focused Success" @?= "deep-work-rules-for-focused-success"
    ]

  , testGroup "buildReportPrompt"
    [ testCase "embeds title and author" $ do
        let (_, user) = buildReportPrompt "Foo Bar" "Baz Qux"
        assertBool "title" (T.isInfixOf "Foo Bar" user)
        assertBool "author" (T.isInfixOf "Baz Qux" user)
    , testCase "system asks for required sections" $ do
        let (sys, _) = buildReportPrompt "Foo" "Bar"
        assertBool "overview" (T.isInfixOf "Overview" sys)
        assertBool "themes" (T.isInfixOf "Key Themes" sys)
        assertBool "recs" (T.isInfixOf "Additional Book Recommendations" sys)
    , testCase "system forbids H1 / frontmatter" $ do
        let (sys, _) = buildReportPrompt "Foo" "Bar"
        assertBool "no H1 instruction" (T.isInfixOf "Do NOT include a top-level H1" sys)
    ]

  , testGroup "assembleBookReport"
    [ testCase "contains frontmatter, nav, h1, image, affiliate, body, signature" $ do
        let input = ReportInput
              { reportTitle = "Foo Bar"
              , reportAuthor = "Baz Qux"
              , reportSlug = "foo-bar"
              , reportAffiliateUrl = "https://www.amazon.com/dp/B08L5W3W7Y?tag=test-20"
              , reportBody = "## 📚 Book Report: Foo Bar by Baz Qux\nbody"
              , reportTodayIso = "2026-05-05T00:00:00Z"
              , reportModelUsed = "gemini-test"
              , reportPromptText = "user prompt"
              }
            md = assembleBookReport input
        assertBool "frontmatter starts" (T.isPrefixOf "---" md)
        assertBool "title in frontmatter" (T.isInfixOf "title: \"Foo Bar\"" md)
        assertBool "URL field"   (T.isInfixOf "URL: \"https://bagrounds.org/books/foo-bar\"" md)
        assertBool "auto_generated flag" (T.isInfixOf "auto_generated: true" md)
        assertBool "nav line"  (T.isInfixOf "[Home](../index.md) > [Books](./index.md)" md)
        assertBool "H1"        (T.isInfixOf "# Foo Bar" md)
        assertBool "image"     (T.isInfixOf "![books-foo-bar](../books-foo-bar.jpg)" md)
        assertBool "affiliate" (T.isInfixOf "https://www.amazon.com/dp/B08L5W3W7Y?tag=test-20" md)
        assertBool "Amazon Associate disclaimer" (T.isInfixOf "As an Amazon Associate" md)
        assertBool "body"      (T.isInfixOf "## 📚 Book Report" md)
        assertBool "signature" (T.isInfixOf "Auto-Generated Report" md)
    ]
  ]
