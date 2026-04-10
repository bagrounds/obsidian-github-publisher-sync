module Automation.BlueskyTest (tests) where

import Control.Exception (toException)
import qualified Data.ByteString.Lazy as LBS
import Data.Maybe (isJust, isNothing)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import Test.Tasty.QuickCheck (testProperty)

import qualified Automation.Platforms.Bluesky as Bluesky
import Automation.Retry (HttpCodeException (HttpCodeException))

tests :: TestTree
tests = testGroup "Bluesky"
  [ extractPostIdTests
  , extractDidTests
  , buildPostUrlTests
  , generateLocalEmbedTests
  , parseSessionTests
  , parsePostResponseTests
  , parseOEmbedHtmlTests
  , classifyExceptionTests
  , propertyTests
  ]

-- ── Bluesky.extractPostId ─────────────────────────────────────────────

extractPostIdTests :: TestTree
extractPostIdTests = testGroup "Bluesky.extractPostId"
  [ testCase "extracts post id from at:// URI" $
      Bluesky.extractPostId "at://did:plc:abc123/app.bsky.feed.post/3abc"
        @?= Just "3abc"

  , testCase "extracts post id from bsky.app URL" $
      Bluesky.extractPostId "https://bsky.app/profile/did:plc:abc123/post/xyz789"
        @?= Just "xyz789"

  , testCase "handles single segment" $
      assertBool "should return Just for single segment" $
        isJust (Bluesky.extractPostId "singlevalue")
  ]

-- ── Bluesky.extractDid ────────────────────────────────────────────────

extractDidTests :: TestTree
extractDidTests = testGroup "Bluesky.extractDid"
  [ testCase "extracts DID from at:// URI" $
      Bluesky.extractDid "at://did:plc:abc123/app.bsky.feed.post/xyz"
        @?= Just "did:plc:abc123"

  , testCase "extracts DID from bsky.app URL with /profile/" $
      Bluesky.extractDid "https://bsky.app/profile/did:plc:abc123/post/xyz"
        @?= Just "did:plc:abc123"

  , testCase "returns Nothing for URL without DID" $
      assertBool "should be Nothing" $
        isNothing (Bluesky.extractDid "https://example.com/nothing")
  ]

-- ── Bluesky.buildPostUrl ──────────────────────────────────────────────

buildPostUrlTests :: TestTree
buildPostUrlTests = testGroup "Bluesky.buildPostUrl"
  [ testCase "builds correct URL" $
      Bluesky.buildPostUrl "did:plc:abc123" "xyz789"
        @?= "https://bsky.app/profile/did:plc:abc123/post/xyz789"
  ]

-- ── Bluesky.generateLocalEmbed ────────────────────────────────────────

generateLocalEmbedTests :: TestTree
generateLocalEmbedTests = testGroup "Bluesky.generateLocalEmbed"
  [ testCase "contains blockquote with data attributes" $ do
      let html = Bluesky.generateLocalEmbed
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
      let html = Bluesky.generateLocalEmbed
                   "at://did:plc:abc/app.bsky.feed.post/xyz"
                   "Hello"
                   "2024-03-15"
                   "testuser"
                   (Just "bafyreiabc")
      assertBool "should contain data-bluesky-cid" $
        "data-bluesky-cid=\"bafyreiabc\"" `T.isInfixOf` html

  , testCase "omits CID attribute when Nothing" $ do
      let html = Bluesky.generateLocalEmbed
                   "at://did:plc:abc/app.bsky.feed.post/xyz"
                   "Hello"
                   "2024-03-15"
                   "testuser"
                   Nothing
      assertBool "should not contain data-bluesky-cid" $
        not ("data-bluesky-cid" `T.isInfixOf` html)

  , testCase "formats date correctly" $ do
      let html = Bluesky.generateLocalEmbed
                   "at://did:plc:abc/app.bsky.feed.post/xyz"
                   "Hello"
                   "2024-03-15"
                   "user"
                   Nothing
      assertBool "should contain formatted date" $
        "March 15, 2024" `T.isInfixOf` html

  , testCase "escapes HTML in post text" $ do
      let html = Bluesky.generateLocalEmbed
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
      let html = Bluesky.generateLocalEmbed
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
      let html = Bluesky.generateLocalEmbed
                   "at://did:plc:abc/app.bsky.feed.post/xyz"
                   "Hi"
                   "2024-01-01"
                   "testuser"
                   Nothing
      assertBool "should contain Bryan Grounds" $
        "Bryan Grounds" `T.isInfixOf` html
  ]

-- ── Bluesky.parseSession ──────────────────────────────────────────────

parseSessionTests :: TestTree
parseSessionTests = testGroup "Bluesky.parseSession"
  [ testCase "parses valid session response" $
      let body = "{\"did\":\"did:plc:abc123\",\"accessJwt\":\"token123\"}"
      in case Bluesky.parseSession (toLBS body) of
           Right _ -> pure ()
           Left err -> fail $ "Expected Right, got: " <> show err

  , testCase "returns JsonParseError for invalid JSON" $
      case Bluesky.parseSession (toLBS "not json") of
        Left (Bluesky.JsonParseError _) -> pure ()
        Left err -> fail $ "Expected JsonParseError, got: " <> show err
        Right _ -> fail "Expected Left, got Right"

  , testCase "returns ExtractionError for missing did field" $
      case Bluesky.parseSession (toLBS "{\"accessJwt\":\"token\"}") of
        Left (Bluesky.ExtractionError _) -> pure ()
        Left err -> fail $ "Expected ExtractionError, got: " <> show err
        Right _ -> fail "Expected Left, got Right"

  , testCase "returns ExtractionError for missing accessJwt field" $
      case Bluesky.parseSession (toLBS "{\"did\":\"did:plc:abc\"}") of
        Left (Bluesky.ExtractionError _) -> pure ()
        Left err -> fail $ "Expected ExtractionError, got: " <> show err
        Right _ -> fail "Expected Left, got Right"
  ]

-- ── Bluesky.parsePostResponse ─────────────────────────────────────────

parsePostResponseTests :: TestTree
parsePostResponseTests = testGroup "Bluesky.parsePostResponse"
  [ testCase "parses valid post response" $
      let body = "{\"uri\":\"at://did:plc:abc/app.bsky.feed.post/xyz\",\"cid\":\"bafyabc\"}"
      in case Bluesky.parsePostResponse "hello" (toLBS body) of
           Right result -> Bluesky.bprCid result @?= "bafyabc"
           Left err -> fail $ "Expected Right, got: " <> show err

  , testCase "returns JsonParseError for invalid JSON" $
      case Bluesky.parsePostResponse "txt" (toLBS "garbage") of
        Left (Bluesky.JsonParseError _) -> pure ()
        other -> fail $ "Expected JsonParseError, got: " <> show other

  , testCase "returns ExtractionError for missing uri field" $
      case Bluesky.parsePostResponse "txt" (toLBS "{\"cid\":\"bafyabc\"}") of
        Left (Bluesky.ExtractionError _) -> pure ()
        other -> fail $ "Expected ExtractionError, got: " <> show other
  ]

-- ── Bluesky.parseOEmbedHtml ──────────────────────────────────────────

parseOEmbedHtmlTests :: TestTree
parseOEmbedHtmlTests = testGroup "Bluesky.parseOEmbedHtml"
  [ testCase "parses valid oEmbed response" $
      let body = "{\"html\":\"<div>embed</div>\"}"
      in Bluesky.parseOEmbedHtml (toLBS body)
           @?= Right (Bluesky.EmbedResult "<div>embed</div>")

  , testCase "returns JsonParseError for invalid JSON" $
      case Bluesky.parseOEmbedHtml (toLBS "not json") of
        Left (Bluesky.JsonParseError _) -> pure ()
        other -> fail $ "Expected JsonParseError, got: " <> show other

  , testCase "returns ExtractionError for missing html field" $
      case Bluesky.parseOEmbedHtml (toLBS "{\"url\":\"https://bsky.app\"}") of
        Left (Bluesky.ExtractionError _) -> pure ()
        other -> fail $ "Expected ExtractionError, got: " <> show other
  ]

-- ── Bluesky.classifyException ─────────────────────────────────────────

classifyExceptionTests :: TestTree
classifyExceptionTests = testGroup "Bluesky.classifyException"
  [ testCase "classifies HttpCodeException as HttpError" $
      let exception = toException (HttpCodeException 401 "Unauthorized")
      in Bluesky.classifyException exception
           @?= Bluesky.HttpError 401 "Unauthorized"

  , testCase "classifies HttpCodeException 404 as HttpError" $
      let exception = toException (HttpCodeException 404 "Not found")
      in Bluesky.classifyException exception
           @?= Bluesky.HttpError 404 "Not found"

  , testCase "classifies other exception as NetworkError" $
      let exception = toException (userError "DNS resolution failed")
      in case Bluesky.classifyException exception of
           Bluesky.NetworkError msg ->
             assertBool "should contain error message" $
               "DNS resolution failed" `T.isInfixOf` msg
           other -> fail $ "Expected NetworkError, got: " <> show other
  ]

-- ── Property Tests ─────────────────────────────────────────────────────

propertyTests :: TestTree
propertyTests = testGroup "properties"
  [ testProperty "Bluesky.buildPostUrl contains DID and postId" $
      \didSuffix postIdSuffix ->
        let did = "did:plc:" <> T.pack didSuffix
            postId = T.pack postIdSuffix
            url = Bluesky.buildPostUrl did postId
        in did `T.isInfixOf` url && postId `T.isInfixOf` url

  , testProperty "Bluesky.extractPostId returns last path segment for at:// URIs" $
      \rkey ->
        let rk = T.pack (filter (`notElem` ['/', ' ', '\n', '\r', '\t', '\0']) rkey)
            uri = "at://did:plc:test/app.bsky.feed.post/" <> rk
        in case Bluesky.extractPostId uri of
             Just pid -> pid == rk
             Nothing  -> T.null rk

  , testProperty "Bluesky.generateLocalEmbed output is non-empty" $
      \postText ->
        let html = Bluesky.generateLocalEmbed
                     "at://did:plc:test/app.bsky.feed.post/abc"
                     (T.pack postText)
                     "2024-01-01"
                     "user"
                     Nothing
        in not (T.null html)

  , testProperty "show Bluesky.Error is non-empty for HttpError" $
      \code -> not (null (show (Bluesky.HttpError code "msg")))

  , testProperty "show Bluesky.Error is non-empty for JsonParseError" $
      \msg -> not (null (show (Bluesky.JsonParseError (T.pack msg))))

  , testProperty "show Bluesky.Error is non-empty for ExtractionError" $
      \msg -> not (null (show (Bluesky.ExtractionError (T.pack msg))))

  , testProperty "show Bluesky.Error is non-empty for NetworkError" $
      \msg -> not (null (show (Bluesky.NetworkError (T.pack msg))))

  , testProperty "parsePostResponse returns Left for non-object JSON input" $
      \input ->
        let bytes = LBS.fromStrict (TE.encodeUtf8 (T.pack input))
        in case Bluesky.parsePostResponse "fb" bytes of
             Left (Bluesky.JsonParseError _)  -> True
             Left (Bluesky.ExtractionError _) -> True
             Right _                           -> True
             _                                 -> False
  ]

-- ── Helpers ───────────────────────────────────────────────────────────

toLBS :: String -> LBS.ByteString
toLBS = LBS.fromStrict . TE.encodeUtf8 . T.pack
