module Automation.EmbedSectionTest (tests) where

import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, assertBool)
import qualified Data.Text as T

import Automation.EmbedSection
import qualified Automation.Platforms.Bluesky as Bluesky
import qualified Automation.Platforms.Mastodon as Mastodon
import qualified Automation.Platforms.Twitter as Twitter

tests :: TestTree
tests = testGroup "EmbedSection"
  [ testCase "buildTweetSection contains header" $
      let section = buildTweetSection "content" "<blockquote>tweet</blockquote>"
      in assertBool "should contain tweet header" $
           Twitter.sectionHeader `T.isInfixOf` section

  , testCase "buildBlueskySection contains header" $
      let section = buildBlueskySection "content" "<blockquote>post</blockquote>"
      in assertBool "should contain bluesky header" $
           Bluesky.sectionHeader `T.isInfixOf` section

  , testCase "buildMastodonSection contains header" $
      let section = buildMastodonSection "content" "<iframe>toot</iframe>"
      in assertBool "should contain mastodon header" $
           Mastodon.sectionHeader `T.isInfixOf` section

  , testCase "createSectionBuilder with trailing newline uses single newline separator" $
      let result = createSectionBuilder "## Header" "content\n" "<embed/>"
      in assertBool "should start with single newline" $
           T.isPrefixOf "\n## Header" result

  , testCase "createSectionBuilder without trailing newline uses double newline separator" $
      let result = createSectionBuilder "## Header" "content" "<embed/>"
      in assertBool "should start with double newline" $
           T.isPrefixOf "\n\n## Header" result

  , testCase "section headers use correct emojis" $ do
      assertBool "tweet has bird" $ T.isInfixOf "🐦" Twitter.sectionHeader
      assertBool "bluesky has butterfly" $ T.isInfixOf "🦋" Bluesky.sectionHeader
      assertBool "mastodon has elephant" $ T.isInfixOf "🐘" Mastodon.sectionHeader

  , testCase "multi-line embed content is preserved" $
      let embedHtml = "<blockquote>\n  <p>Line 1</p>\n  <p>Line 2</p>\n</blockquote>"
          section = buildTweetSection "content" embedHtml
      in do
          assertBool "should contain line 1" $ T.isInfixOf "Line 1" section
          assertBool "should contain line 2" $ T.isInfixOf "Line 2" section

  , testCase "createSectionBuilder includes embed html after header" $
      let result = createSectionBuilder "## Test" "body" "<div>embed</div>"
      in assertBool "should contain embed" $ T.isInfixOf "<div>embed</div>" result
  ]
