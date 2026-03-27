module Automation.BlueskyTest (tests) where

import Data.Maybe (isJust, isNothing)
import qualified Data.Text as T
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import Test.Tasty.QuickCheck (testProperty)

import Automation.Platforms.Bluesky
  ( extractBlueskyPostId
  , extractBlueskyDid
  , buildBlueskyPostUrl
  , generateLocalBlueskyEmbed
  )

tests :: TestTree
tests = testGroup "Bluesky"
  [ extractPostIdTests
  , extractDidTests
  , buildPostUrlTests
  , generateLocalEmbedTests
  , propertyTests
  ]

-- ── extractBlueskyPostId ───────────────────────────────────────────────

extractPostIdTests :: TestTree
extractPostIdTests = testGroup "extractBlueskyPostId"
  [ testCase "extracts post id from at:// URI" $
      extractBlueskyPostId "at://did:plc:abc123/app.bsky.feed.post/3abc"
        @?= Just "3abc"

  , testCase "extracts post id from bsky.app URL" $
      extractBlueskyPostId "https://bsky.app/profile/did:plc:abc123/post/xyz789"
        @?= Just "xyz789"

  , testCase "handles single segment" $
      assertBool "should return Just for single segment" $
        isJust (extractBlueskyPostId "singlevalue")
  ]

-- ── extractBlueskyDid ──────────────────────────────────────────────────

extractDidTests :: TestTree
extractDidTests = testGroup "extractBlueskyDid"
  [ testCase "extracts DID from at:// URI" $
      extractBlueskyDid "at://did:plc:abc123/app.bsky.feed.post/xyz"
        @?= Just "did:plc:abc123"

  , testCase "extracts DID from bsky.app URL with /profile/" $
      extractBlueskyDid "https://bsky.app/profile/did:plc:abc123/post/xyz"
        @?= Just "did:plc:abc123"

  , testCase "returns Nothing for URL without DID" $
      assertBool "should be Nothing" $
        isNothing (extractBlueskyDid "https://example.com/nothing")
  ]

-- ── buildBlueskyPostUrl ────────────────────────────────────────────────

buildPostUrlTests :: TestTree
buildPostUrlTests = testGroup "buildBlueskyPostUrl"
  [ testCase "builds correct URL" $
      buildBlueskyPostUrl "did:plc:abc123" "xyz789"
        @?= "https://bsky.app/profile/did:plc:abc123/post/xyz789"
  ]

-- ── generateLocalBlueskyEmbed ──────────────────────────────────────────

generateLocalEmbedTests :: TestTree
generateLocalEmbedTests = testGroup "generateLocalBlueskyEmbed"
  [ testCase "contains blockquote with data attributes" $ do
      let html = generateLocalBlueskyEmbed
                   "at://did:plc:abc/app.bsky.feed.post/xyz"
                   "Hello world"
                   "2024-03-15"
                   "testuser"
                   Nothing
      assertBool "should contain bluesky-embed class" $
        "bluesky-embed" `T.isInfixOf` html
      assertBool "should contain data-bluesky-uri" $
        "data-bluesky-uri" `T.isInfixOf` html
      assertBool "should contain embed script" $
        "embed.bsky.app/static/embed.js" `T.isInfixOf` html
      assertBool "should contain color mode" $
        "data-bluesky-embed-color-mode=\"system\"" `T.isInfixOf` html

  , testCase "includes CID attribute when provided" $ do
      let html = generateLocalBlueskyEmbed
                   "at://did:plc:abc/app.bsky.feed.post/xyz"
                   "Hello"
                   "2024-03-15"
                   "testuser"
                   (Just "bafyreiabc")
      assertBool "should contain data-bluesky-cid" $
        "data-bluesky-cid=\"bafyreiabc\"" `T.isInfixOf` html

  , testCase "omits CID attribute when Nothing" $ do
      let html = generateLocalBlueskyEmbed
                   "at://did:plc:abc/app.bsky.feed.post/xyz"
                   "Hello"
                   "2024-03-15"
                   "testuser"
                   Nothing
      assertBool "should not contain data-bluesky-cid" $
        not ("data-bluesky-cid" `T.isInfixOf` html)

  , testCase "formats date correctly" $ do
      let html = generateLocalBlueskyEmbed
                   "at://did:plc:abc/app.bsky.feed.post/xyz"
                   "Hello"
                   "2024-03-15"
                   "user"
                   Nothing
      assertBool "should contain formatted date" $
        "March 15, 2024" `T.isInfixOf` html

  , testCase "escapes HTML in post text" $ do
      let html = generateLocalBlueskyEmbed
                   "at://did:plc:abc/app.bsky.feed.post/xyz"
                   "Hello <world> & \"friends\""
                   "2024-01-01"
                   "user"
                   Nothing
      assertBool "should escape angle brackets" $
        "&lt;world&gt;" `T.isInfixOf` html
      assertBool "should escape ampersand" $
        "&amp;" `T.isInfixOf` html

  , testCase "includes handle link" $ do
      let html = generateLocalBlueskyEmbed
                   "at://did:plc:abc/app.bsky.feed.post/xyz"
                   "Hi"
                   "2024-01-01"
                   "testuser"
                   Nothing
      assertBool "should contain @handle" $
        "@testuser" `T.isInfixOf` html
      assertBool "should contain profile link" $
        "bsky.app/profile/did:plc:abc?ref_src=embed" `T.isInfixOf` html

  , testCase "includes display name" $ do
      let html = generateLocalBlueskyEmbed
                   "at://did:plc:abc/app.bsky.feed.post/xyz"
                   "Hi"
                   "2024-01-01"
                   "testuser"
                   Nothing
      assertBool "should contain Bryan Grounds" $
        "Bryan Grounds" `T.isInfixOf` html
  ]

-- ── Property Tests ─────────────────────────────────────────────────────

propertyTests :: TestTree
propertyTests = testGroup "properties"
  [ testProperty "buildBlueskyPostUrl contains DID and postId" $
      \didSuffix postIdSuffix ->
        let did = "did:plc:" <> T.pack didSuffix
            postId = T.pack postIdSuffix
            url = buildBlueskyPostUrl did postId
        in did `T.isInfixOf` url && postId `T.isInfixOf` url

  , testProperty "extractBlueskyPostId returns last path segment for at:// URIs" $
      \rkey ->
        let rk = T.pack (filter (`notElem` ['/', ' ', '\n', '\r', '\t', '\0']) rkey)
            uri = "at://did:plc:test/app.bsky.feed.post/" <> rk
        in case extractBlueskyPostId uri of
             Just pid -> pid == rk
             Nothing  -> T.null rk

  , testProperty "generateLocalBlueskyEmbed output is non-empty" $
      \postText ->
        let html = generateLocalBlueskyEmbed
                     "at://did:plc:test/app.bsky.feed.post/abc"
                     (T.pack postText)
                     "2024-01-01"
                     "user"
                     Nothing
        in not (T.null html)
  ]
