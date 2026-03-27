module Automation.MastodonTest (tests) where

import Data.Maybe (isJust)
import qualified Data.Text as T
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import Test.Tasty.QuickCheck (testProperty)

import Automation.Platforms.Mastodon
  ( extractMastodonInstanceUrl
  , extractMastodonStatusId
  , extractMastodonUsername
  , generateLocalMastodonEmbed
  )

tests :: TestTree
tests = testGroup "Mastodon"
  [ extractInstanceUrlTests
  , extractStatusIdTests
  , extractUsernameTests
  , generateLocalEmbedTests
  , propertyTests
  ]

-- ── extractMastodonInstanceUrl ─────────────────────────────────────────

extractInstanceUrlTests :: TestTree
extractInstanceUrlTests = testGroup "extractMastodonInstanceUrl"
  [ testCase "extracts instance URL from standard Mastodon post URL" $
      extractMastodonInstanceUrl "https://fosstodon.org/@bagrounds/123456"
        @?= Just "https://fosstodon.org"

  , testCase "extracts instance URL with path" $
      extractMastodonInstanceUrl "https://mastodon.social/@user/789"
        @?= Just "https://mastodon.social"

  , testCase "returns Just prefix for URL without /@" $
      assertBool "should return Just with full URL" $
        isJust (extractMastodonInstanceUrl "https://example.com/post/123")

  , testCase "handles URL with multiple /@ segments" $
      extractMastodonInstanceUrl "https://instance.org/@user/@nested/post"
        @?= Just "https://instance.org"
  ]

-- ── extractMastodonStatusId ────────────────────────────────────────────

extractStatusIdTests :: TestTree
extractStatusIdTests = testGroup "extractMastodonStatusId"
  [ testCase "extracts status ID from standard URL" $
      extractMastodonStatusId "https://fosstodon.org/@bagrounds/112345678"
        @?= Just "112345678"

  , testCase "extracts last path segment" $
      extractMastodonStatusId "https://mastodon.social/@user/999"
        @?= Just "999"

  , testCase "handles single segment" $
      extractMastodonStatusId "singlevalue"
        @?= Just "singlevalue"
  ]

-- ── extractMastodonUsername ────────────────────────────────────────────

extractUsernameTests :: TestTree
extractUsernameTests = testGroup "extractMastodonUsername"
  [ testCase "extracts username from standard URL" $
      extractMastodonUsername "https://fosstodon.org/@bagrounds/123"
        @?= Just "bagrounds"

  , testCase "extracts username without status ID" $
      extractMastodonUsername "https://mastodon.social/@alice"
        @?= Just "alice"

  , testCase "returns empty username for URL without /@" $
      extractMastodonUsername "https://example.com/post/123"
        @?= Just ""
  ]

-- ── generateLocalMastodonEmbed ─────────────────────────────────────────

generateLocalEmbedTests :: TestTree
generateLocalEmbedTests = testGroup "generateLocalMastodonEmbed"
  [ testCase "generates iframe embed with correct src" $ do
      let html = generateLocalMastodonEmbed
                   "https://fosstodon.org/@bagrounds/123456"
      assertBool "should contain iframe element" $
        "<iframe" `T.isInfixOf` html
      assertBool "should contain post URL with /embed suffix" $
        "https://fosstodon.org/@bagrounds/123456/embed" `T.isInfixOf` html

  , testCase "includes mastodon-embed class" $ do
      let html = generateLocalMastodonEmbed
                   "https://fosstodon.org/@user/789"
      assertBool "should contain mastodon-embed class" $
        "mastodon-embed" `T.isInfixOf` html

  , testCase "includes embed.js script tag" $ do
      let html = generateLocalMastodonEmbed
                   "https://fosstodon.org/@user/789"
      assertBool "should contain embed.js script" $
        "https://fosstodon.org/embed.js" `T.isInfixOf` html
      assertBool "should have async attribute" $
        "async=\"async\"" `T.isInfixOf` html

  , testCase "includes width and style attributes" $ do
      let html = generateLocalMastodonEmbed
                   "https://fosstodon.org/@user/789"
      assertBool "should contain width 400" $
        "width=\"400\"" `T.isInfixOf` html
      assertBool "should contain max-width style" $
        "max-width: 100%" `T.isInfixOf` html
      assertBool "should contain border: 0" $
        "border: 0" `T.isInfixOf` html

  , testCase "includes allowfullscreen attribute" $ do
      let html = generateLocalMastodonEmbed
                   "https://mastodon.social/@user/123"
      assertBool "should contain allowfullscreen" $
        "allowfullscreen=\"allowfullscreen\"" `T.isInfixOf` html

  , testCase "derives instance URL from post URL for script src" $ do
      let html = generateLocalMastodonEmbed
                   "https://mastodon.social/@alice/456"
      assertBool "should use mastodon.social for embed.js" $
        "https://mastodon.social/embed.js" `T.isInfixOf` html
  ]

-- ── Property Tests ─────────────────────────────────────────────────────

propertyTests :: TestTree
propertyTests = testGroup "properties"
  [ testProperty "extractMastodonStatusId returns last path segment" $
      \statusId ->
        let sid = T.pack (filter (`notElem` ['/', ' ', '\n', '\r', '\t', '\0']) statusId)
            url = "https://fosstodon.org/@user/" <> sid
        in case extractMastodonStatusId url of
             Just extracted -> extracted == sid
             Nothing        -> T.null sid

  , testProperty "extractMastodonUsername extracts username from well-formed URLs" $
      \username ->
        let uname = T.pack (filter (`notElem` ['/', '@', ' ', '\n', '\r', '\t', '\0']) username)
            url = "https://fosstodon.org/@" <> uname <> "/123"
        in not (T.null uname) ==>
             extractMastodonUsername url == Just uname

  , testProperty "generateLocalMastodonEmbed output is non-empty" $
      \postSuffix ->
        let url = "https://fosstodon.org/@user/" <> T.pack postSuffix
            html = generateLocalMastodonEmbed url
        in not (T.null html)

  , testProperty "generateLocalMastodonEmbed always contains iframe" $
      \postSuffix ->
        let url = "https://fosstodon.org/@user/" <> T.pack postSuffix
            html = generateLocalMastodonEmbed url
        in "<iframe" `T.isInfixOf` html

  , testProperty "extractMastodonInstanceUrl returns prefix before /@" $
      \instanceSuffix ->
        let inst = T.pack (filter (`notElem` ['@', ' ', '\n', '\r', '\t', '\0']) instanceSuffix)
            url = "https://" <> inst <> "/@user/123"
        in extractMastodonInstanceUrl url == Just ("https://" <> inst)
  ]

-- QuickCheck implication helper
(==>) :: Bool -> Bool -> Bool
False ==> _ = True
True  ==> b = b
infixr 0 ==>
