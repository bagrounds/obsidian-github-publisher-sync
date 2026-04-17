module Automation.WikilinkTest (tests) where

import qualified Data.Text as T
import Data.Time.LocalTime (TimeOfDay (..))
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import Test.Tasty.QuickCheck (testProperty)
import qualified Test.QuickCheck as QC

import Automation.BlogSeriesConfig (BlogSeriesConfig (..))
import Automation.Wikilink (formatWikilink, buildBackLink, buildForwardLink, backMarker, forwardMarker, addForwardNavLink)

tests :: TestTree
tests = testGroup "Wikilink"
  [ formatWikilinkTests
  , buildBackLinkTests
  , buildForwardLinkTests
  , markerTests
  , addForwardNavLinkTests
  , propertyTests
  ]

sampleSeries :: BlogSeriesConfig
sampleSeries = BlogSeriesConfig
  { bscId           = "chickie-loo"
  , bscName         = "Chickie Loo"
  , bscIcon         = "🐔"
  , bscAuthor       = "[[chickie-loo]]"
  , bscBaseUrl      = "https://bagrounds.org/chickie-loo"
  , bscPriorityUser = Just "ChickieLoo"
  , bscNavLink      = "[[index|Home]] > [[chickie-loo/index|🐔 Chickie Loo]]"
  , bscScheduleTime = TimeOfDay 7 0 0
  , bscContextQueries = []
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

addForwardNavLinkTests :: TestTree
addForwardNavLinkTests = testGroup "addForwardNavLink"
  [ testCase "adds forward link after existing back link" $
      let content = "[[index|Home]] > [[test/index|Test]] | [[test/2026-03-31|⏮️]]\n# Post"
          result = addForwardNavLink "test" "[[test/index|Test]]" content "2026-04-02"
      in do
        assertBool "contains forward marker" (T.isInfixOf "⏭️" result)
        assertBool "links to target" (T.isInfixOf "[[test/2026-04-02|⏭️]]" result)
  , testCase "does not add duplicate forward link" $
      let content = "[[test/prev|⏮️]] [[test/next|⏭️]]\n# Post"
          result = addForwardNavLink "test" "marker" content "2026-04-03"
      in result @?= content
  , testCase "adds forward link after fallback marker when no back link" $
      let content = "[[index|Home]] > [[test/index|Test]]\n# Post"
          result = addForwardNavLink "test" "[[test/index|Test]]" content "2026-04-02"
      in do
        assertBool "contains forward marker" (T.isInfixOf "⏭️" result)
        assertBool "links to target" (T.isInfixOf "[[test/2026-04-02|⏭️]]" result)
  , testProperty "addForwardNavLink is idempotent" $
      \(QC.ASCIIString dateStr) ->
        let date = T.pack dateStr
            content = "nav | [[test/prev|⏮️]]\n# Post"
            once = addForwardNavLink "test" "marker" content date
            twice = addForwardNavLink "test" "marker" once date
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
