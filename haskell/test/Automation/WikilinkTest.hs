module Automation.WikilinkTest (tests) where

import qualified Data.Text as T
import Data.Time.LocalTime (TimeOfDay (..))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import Test.Tasty.QuickCheck (testProperty)
import qualified Test.QuickCheck as QC

import Automation.BlogSeriesConfig (BlogSeriesConfig (..))
import Automation.Wikilink (formatWikilink, buildBackLink, buildForwardLink, backMarker, forwardMarker, NavigableDirectory (..), directoryIndexLink, buildNavBackLink, buildNavForwardLink, insertForwardNavLink)

tests :: TestTree
tests = testGroup "Wikilink"
  [ formatWikilinkTests
  , buildBackLinkTests
  , buildForwardLinkTests
  , markerTests
  , navigableDirectoryTests
  , insertForwardNavLinkTests
  , propertyTests
  ]

sampleSeries :: BlogSeriesConfig
sampleSeries = BlogSeriesConfig
  { seriesId       = "chickie-loo"
  , name           = "Chickie Loo"
  , icon           = "🐔"
  , author         = "[[chickie-loo]]"
  , baseUrl        = "https://bagrounds.org/chickie-loo"
  , priorityUser   = Just "ChickieLoo"
  , navLink        = "[[index|Home]] > [[chickie-loo/index|🐔 Chickie Loo]]"
  , scheduleTime   = TimeOfDay 7 0 0
  , contextQueries = []
  }

formatWikilinkTests :: TestTree
formatWikilinkTests = testGroup "formatWikilink"
  [ testCase "formats basic wikilink" $
      formatWikilink "books/test" "Test Book" @?= "[[books/test|Test Book]]"
  , testCase "formats wikilink with emoji alias" $
      formatWikilink "books/thinking-fast-and-slow" "🤔🐇🐢 Thinking, Fast and Slow"
        @?= "[[books/thinking-fast-and-slow|🤔🐇🐢 Thinking, Fast and Slow]]"
  , testCase "formats nav back link" $
      formatWikilink "reflections/2026-04-01" "⏮️" @?= "[[reflections/2026-04-01|⏮️]]"
  , testCase "formats nav forward link" $
      formatWikilink "reflections/2026-04-02" "⏭️" @?= "[[reflections/2026-04-02|⏭️]]"
  , testCase "formats series index link" $
      formatWikilink "auto-blog-zero/index" "🤖 Auto Blog Zero"
        @?= "[[auto-blog-zero/index|🤖 Auto Blog Zero]]"
  , testCase "formats blog post link with full display title" $
      formatWikilink "the-noise/2026-04-14-my-post" "2026-04-14 | 📰 My Post 📰"
        @?= "[[the-noise/2026-04-14-my-post|2026-04-14 | 📰 My Post 📰]]"
  ]

buildBackLinkTests :: TestTree
buildBackLinkTests = testGroup "buildBackLink"
  [ testCase "builds back link with series prefix" $
      buildBackLink sampleSeries "2026-03-25-test"
        @?= "[[chickie-loo/2026-03-25-test|⏮️]]"
  , testCase "strips .md extension" $
      buildBackLink sampleSeries "2026-03-25-test.md"
        @?= "[[chickie-loo/2026-03-25-test|⏮️]]"
  ]

buildForwardLinkTests :: TestTree
buildForwardLinkTests = testGroup "buildForwardLink"
  [ testCase "builds forward link with series prefix" $
      buildForwardLink sampleSeries "2026-03-27-test"
        @?= "[[chickie-loo/2026-03-27-test|⏭️]]"
  , testCase "strips .md extension" $
      buildForwardLink sampleSeries "2026-03-27-test.md"
        @?= "[[chickie-loo/2026-03-27-test|⏭️]]"
  ]

markerTests :: TestTree
markerTests = testGroup "navigation markers"
  [ testCase "backMarker is track previous emoji" $
      backMarker @?= "⏮️"
  , testCase "forwardMarker is track next emoji" $
      forwardMarker @?= "⏭️"
  , testCase "buildBackLink uses backMarker" $
      let result = buildBackLink sampleSeries "test"
      in assertBool "contains backMarker" (T.isInfixOf backMarker result)
  , testCase "buildForwardLink uses forwardMarker" $
      let result = buildForwardLink sampleSeries "test"
      in assertBool "contains forwardMarker" (T.isInfixOf forwardMarker result)
  ]

navigableDirectoryTests :: TestTree
navigableDirectoryTests = testGroup "NavigableDirectory"
  [ testCase "directoryIndexLink Reflections" $
      directoryIndexLink Reflections @?= "[[reflections/index|Reflections]]"
  , testCase "directoryIndexLink Changes" $
      directoryIndexLink Changes @?= "[[changes/index|Changes]]"
  , testCase "buildNavBackLink Reflections" $
      buildNavBackLink Reflections "2026-04-01" @?= "[[reflections/2026-04-01|⏮️]]"
  , testCase "buildNavBackLink Changes" $
      buildNavBackLink Changes "2026-04-01" @?= "[[changes/2026-04-01|⏮️]]"
  , testCase "buildNavForwardLink Reflections" $
      buildNavForwardLink Reflections "2026-04-02" @?= "[[reflections/2026-04-02|⏭️]]"
  , testCase "buildNavForwardLink Changes" $
      buildNavForwardLink Changes "2026-04-02" @?= "[[changes/2026-04-02|⏭️]]"
  ]

insertForwardNavLinkTests :: TestTree
insertForwardNavLinkTests = testGroup "insertForwardNavLink"
  [ testCase "inserts after existing back link" $
      let content = "[[index|Home]] > [[reflections/index|Reflections]] | [[reflections/2026-03-31|⏮️]]\n# Post"
          result = insertForwardNavLink Reflections content "2026-04-02"
      in do
        assertBool "contains forward marker" (T.isInfixOf "⏭️" result)
        assertBool "links to target" (T.isInfixOf "[[reflections/2026-04-02|⏭️]]" result)
  , testCase "does not add duplicate forward link" $
      let content = "[[reflections/prev|⏮️]] [[reflections/next|⏭️]]\n# Post"
          result = insertForwardNavLink Reflections content "2026-04-03"
      in result @?= content
  , testCase "inserts after directory index link when no back link" $
      let content = "[[index|Home]] > [[reflections/index|Reflections]]\n# Post"
          result = insertForwardNavLink Reflections content "2026-04-02"
      in do
        assertBool "contains forward marker" (T.isInfixOf "⏭️" result)
        assertBool "links to target" (T.isInfixOf "[[reflections/2026-04-02|⏭️]]" result)
  , testCase "works for Changes directory" $
      let content = "[[index|Home]] > [[changes/index|Changes]] | [[changes/2026-03-31|⏮️]]\n# Post"
          result = insertForwardNavLink Changes content "2026-04-02"
      in do
        assertBool "contains forward marker" (T.isInfixOf "⏭️" result)
        assertBool "links to target" (T.isInfixOf "[[changes/2026-04-02|⏭️]]" result)
  , testProperty "insertForwardNavLink is idempotent for Reflections" $
      \(QC.ASCIIString dateStr) ->
        let date = T.pack dateStr
            content = "nav | [[reflections/prev|⏮️]]\n# Post"
            once = insertForwardNavLink Reflections content date
            twice = insertForwardNavLink Reflections once date
        in once == twice
  , testProperty "insertForwardNavLink is idempotent for Changes" $
      \(QC.ASCIIString dateStr) ->
        let date = T.pack dateStr
            content = "nav | [[changes/prev|⏮️]]\n# Post"
            once = insertForwardNavLink Changes content date
            twice = insertForwardNavLink Changes once date
        in once == twice
  ]

propertyTests :: TestTree
propertyTests = testGroup "properties"
  [ testProperty "formatWikilink starts with [[ and ends with ]]" $
      \(QC.ASCIIString target) (QC.ASCIIString alias) ->
        let result = formatWikilink (T.pack target) (T.pack alias)
        in T.isPrefixOf "[[" result && T.isSuffixOf "]]" result
  , testProperty "formatWikilink contains pipe separator" $
      \(QC.ASCIIString target) (QC.ASCIIString alias) ->
        T.isInfixOf "|" (formatWikilink (T.pack target) (T.pack alias))
  , testProperty "formatWikilink contains target and alias" $
      \(QC.ASCIIString target) (QC.ASCIIString alias) ->
        let result = formatWikilink (T.pack target) (T.pack alias)
        in T.isInfixOf (T.pack target) result && T.isInfixOf (T.pack alias) result
  ]
