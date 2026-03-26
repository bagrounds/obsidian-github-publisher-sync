module Automation.EmbedSectionTest (tests) where

import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, assertBool)
import qualified Data.Text as T

import Automation.EmbedSection
import Automation.Types (tweetSectionHeader, blueskySectionHeader, mastodonSectionHeader)

tests :: TestTree
tests = testGroup "EmbedSection"
  [ testCase "buildTweetSection contains header" $
      let section = buildTweetSection "content" "<blockquote>tweet</blockquote>"
      in assertBool "should contain tweet header" $
           tweetSectionHeader `T.isInfixOf` section

  , testCase "buildBlueskySection contains header" $
      let section = buildBlueskySection "content" "<blockquote>post</blockquote>"
      in assertBool "should contain bluesky header" $
           blueskySectionHeader `T.isInfixOf` section

  , testCase "buildMastodonSection contains header" $
      let section = buildMastodonSection "content" "<iframe>toot</iframe>"
      in assertBool "should contain mastodon header" $
           mastodonSectionHeader `T.isInfixOf` section
  ]
