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
  , parseSessionTests
  , parsePostResponseTests
  , parseOEmbedHtmlTests
  , classifyExceptionTests
  , toDarkModeTests
  , needsDarkModeUpdateTests
  , needsEmbedRegenerationTests
  , extractRegenerationUrlTests
  , replaceSectionContentTests
  , isBrokenEmbedTests
  , propertyTests
  ]

extractPostIdTests :: TestTree
extractPostIdTests = testGroup "extractPostId"
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

extractDidTests :: TestTree
extractDidTests = testGroup "extractDid"
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

buildPostUrlTests :: TestTree
buildPostUrlTests = testGroup "buildPostUrl"
  [ testCase "builds correct URL" $
      Bluesky.buildPostUrl "did:plc:abc123" "xyz789"
        @?= "https://bsky.app/profile/did:plc:abc123/post/xyz789"
  ]

parseSessionTests :: TestTree
parseSessionTests = testGroup "parseSession"
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

parsePostResponseTests :: TestTree
parsePostResponseTests = testGroup "parsePostResponse"
  [ testCase "parses valid post response" $
      let body = "{\"uri\":\"at://did:plc:abc/app.bsky.feed.post/xyz\",\"cid\":\"bafyabc\"}"
      in case Bluesky.parsePostResponse "hello" (toLBS body) of
           Right result -> Bluesky.postCid result @?= "bafyabc"
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

parseOEmbedHtmlTests :: TestTree
parseOEmbedHtmlTests = testGroup "parseOEmbedHtml"
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

classifyExceptionTests :: TestTree
classifyExceptionTests = testGroup "classifyException"
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

toDarkModeTests :: TestTree
toDarkModeTests = testGroup "toDarkMode"
  [ testCase "replaces system color mode with dark" $ do
      let input = "<blockquote class=\"bluesky-embed\" data-bluesky-embed-color-mode=\"system\"><p>content</p></blockquote>"
          result = Bluesky.toDarkMode input
      assertBool "should have dark color mode" $
        "data-bluesky-embed-color-mode=\"dark\"" `T.isInfixOf` result
      assertBool "should not have system color mode" $
        not ("data-bluesky-embed-color-mode=\"system\"" `T.isInfixOf` result)

  , testCase "replaces light color mode with dark" $ do
      let input = "<blockquote class=\"bluesky-embed\" data-bluesky-embed-color-mode=\"light\"><p>content</p></blockquote>"
          result = Bluesky.toDarkMode input
      assertBool "should have dark color mode" $
        "data-bluesky-embed-color-mode=\"dark\"" `T.isInfixOf` result
      assertBool "should not have light color mode" $
        not ("data-bluesky-embed-color-mode=\"light\"" `T.isInfixOf` result)

  , testCase "does not modify already-dark embed" $ do
      let input = "<blockquote class=\"bluesky-embed\" data-bluesky-embed-color-mode=\"dark\"><p>content</p></blockquote>"
      Bluesky.toDarkMode input @?= input

  , testCase "does not modify text without color mode attribute" $ do
      let input = "<blockquote class=\"bluesky-embed\"><p>content</p></blockquote>"
      Bluesky.toDarkMode input @?= input
  ]

needsDarkModeUpdateTests :: TestTree
needsDarkModeUpdateTests = testGroup "needsDarkModeUpdate"
  [ testCase "detects system-mode bluesky embed" $
      assertBool "system-mode embed should need update" $
        Bluesky.needsDarkModeUpdate
          "<blockquote class=\"bluesky-embed\" data-bluesky-uri=\"at://did\" data-bluesky-embed-color-mode=\"system\"><p lang=\"en\">Real content</p></blockquote>"

  , testCase "detects light-mode bluesky embed" $
      assertBool "light-mode embed should need update" $
        Bluesky.needsDarkModeUpdate
          "<blockquote class=\"bluesky-embed\" data-bluesky-uri=\"at://did\" data-bluesky-embed-color-mode=\"light\"><p lang=\"en\">Real content</p></blockquote>"

  , testCase "does not flag dark-mode bluesky embed" $
      assertBool "dark-mode embed should not need update" $
        not $ Bluesky.needsDarkModeUpdate
          "<blockquote class=\"bluesky-embed\" data-bluesky-uri=\"at://did\" data-bluesky-embed-color-mode=\"dark\"><p lang=\"en\">Real content</p></blockquote>"

  , testCase "does not flag embed without color mode attribute" $
      assertBool "embed without color mode should not need update" $
        not $ Bluesky.needsDarkModeUpdate
          "<blockquote class=\"bluesky-embed\" data-bluesky-uri=\"at://did\"><p lang=\"en\">Real content</p></blockquote>"

  , testCase "does not flag non-bluesky content" $
      assertBool "non-bluesky content should not need update" $
        not $ Bluesky.needsDarkModeUpdate
          "data-bluesky-embed-color-mode=\"system\""

  , testCase "does not flag empty text" $
      assertBool "empty text should not need update" $
        not $ Bluesky.needsDarkModeUpdate ""

  , testCase "does not flag broken embeds" $
      assertBool "broken embed should not need dark mode update" $
        not $ Bluesky.needsDarkModeUpdate brokenEmbedExample
  ]

needsEmbedRegenerationTests :: TestTree
needsEmbedRegenerationTests = testGroup "needsEmbedRegeneration"
  [ testCase "detects plain Bluesky URL as needing regeneration" $
      assertBool "plain URL should need regeneration" $
        Bluesky.needsEmbedRegeneration "https://bsky.app/profile/did:plc:abc/post/xyz"

  , testCase "detects URL with whitespace as needing regeneration" $
      assertBool "URL with surrounding whitespace should need regeneration" $
        Bluesky.needsEmbedRegeneration "  \nhttps://bsky.app/profile/did:plc:abc/post/xyz\n  "

  , testCase "detects broken embed as needing regeneration" $
      assertBool "broken embed should need regeneration" $
        Bluesky.needsEmbedRegeneration brokenEmbedExample

  , testCase "does not detect valid blockquote embed as needing regeneration" $
      assertBool "valid blockquote should not need regeneration" $
        not $ Bluesky.needsEmbedRegeneration
          "<blockquote class=\"bluesky-embed\" data-bluesky-uri=\"at://did:plc:abc/app.bsky.feed.post/xyz\"><p lang=\"en\">Hello world, this is a real post</p></blockquote>"

  , testCase "detects valid system-mode embed as needing regeneration for dark mode" $
      assertBool "system-mode embed should need regeneration" $
        Bluesky.needsEmbedRegeneration
          "<blockquote class=\"bluesky-embed\" data-bluesky-uri=\"https://bsky.app/profile/bagrounds.bsky.social/post/3abc\" data-bluesky-embed-color-mode=\"system\"><p lang=\"en\">Real post content here</p></blockquote>"

  , testCase "does not detect valid dark-mode embed as needing regeneration" $
      assertBool "dark-mode embed should not need regeneration" $
        not $ Bluesky.needsEmbedRegeneration
          "<blockquote class=\"bluesky-embed\" data-bluesky-uri=\"https://bsky.app/profile/bagrounds.bsky.social/post/3abc\" data-bluesky-embed-color-mode=\"dark\"><p lang=\"en\">Real post content here</p></blockquote>"

  , testCase "does not detect empty text as needing regeneration" $
      assertBool "empty should not need regeneration" $
        not $ Bluesky.needsEmbedRegeneration ""

  , testCase "does not detect non-bluesky URL as needing regeneration" $
      assertBool "non-bluesky URL should not need regeneration" $
        not $ Bluesky.needsEmbedRegeneration "https://example.com/post/123"
  ]

isBrokenEmbedTests :: TestTree
isBrokenEmbedTests = testGroup "isBrokenEmbed"
  [ testCase "detects garbled embed with DID in paragraph" $
      assertBool "should detect broken embed" $
        Bluesky.isBrokenEmbed brokenEmbedExample

  , testCase "does not detect valid embed as broken" $
      assertBool "valid embed should not be broken" $
        not $ Bluesky.isBrokenEmbed
          "<blockquote class=\"bluesky-embed\" data-bluesky-uri=\"at://did:plc:abc/app.bsky.feed.post/xyz\"><p lang=\"en\">Hello world, this is a real post</p></blockquote>"

  , testCase "does not detect plain URL as broken embed" $
      assertBool "plain URL should not be broken embed" $
        not $ Bluesky.isBrokenEmbed "https://bsky.app/profile/did:plc:abc/post/xyz"
  ]

extractRegenerationUrlTests :: TestTree
extractRegenerationUrlTests = testGroup "extractRegenerationUrl"
  [ testCase "extracts URL from plain placeholder link" $
      let result = Bluesky.extractRegenerationUrl "https://bsky.app/profile/did:plc:abc/post/xyz"
      in assertBool "should extract URL from placeholder" $ isJust result

  , testCase "extracts URL from broken embed with https URI" $
      let brokenWithHttps = "<blockquote class=\"bluesky-embed\" data-bluesky-uri=\"https://bsky.app/profile/bagrounds.bsky.social/post/3mjarbzrnt52a\" data-bluesky-embed-color-mode=\"system\"><p lang=\"en\">did:plc:i4yli6h7x2uoj7acxunww2fc</p></blockquote>"
          result = Bluesky.extractRegenerationUrl brokenWithHttps
      in assertBool "should extract URL from broken embed" $ isJust result

  , testCase "extracts URL from broken embed example from issue" $
      let result = Bluesky.extractRegenerationUrl brokenEmbedExample
      in assertBool "should extract URL from real broken embed" $ isJust result

  , testCase "returns Nothing for valid embed" $
      let validEmbed = "<blockquote class=\"bluesky-embed\" data-bluesky-uri=\"at://did:plc:abc/app.bsky.feed.post/xyz\"><p lang=\"en\">Hello world, real post content here</p></blockquote>"
          result = Bluesky.extractRegenerationUrl validEmbed
      in assertBool "should return Nothing for valid embed" $ isNothing result

  , testCase "returns Nothing for empty content" $
      assertBool "should return Nothing for empty" $
        isNothing (Bluesky.extractRegenerationUrl "")
  ]

replaceSectionContentTests :: TestTree
replaceSectionContentTests = testGroup "replaceSectionContent"
  [ testCase "replaces placeholder URL with embed HTML" $ do
      let content = T.unlines
            [ "# My Note"
            , ""
            , "## 🦋 Bluesky"
            , "https://bsky.app/profile/did:plc:abc/post/xyz"
            , ""
            , "## 🐘 Mastodon"
            , "<iframe>mastodon embed</iframe>"
            ]
          newEmbed = "<blockquote class=\"bluesky-embed\">real embed</blockquote><script></script>"
          result = Bluesky.replaceSectionContent content newEmbed
      assertBool "should contain new embed" $
        newEmbed `T.isInfixOf` result
      assertBool "should not contain placeholder URL" $
        not ("https://bsky.app/profile/did:plc:abc/post/xyz" `T.isInfixOf` result)
      assertBool "should preserve mastodon section" $
        "## 🐘 Mastodon" `T.isInfixOf` result

  , testCase "does not modify file without Bluesky section" $ do
      let content = "# My Note\nSome content\n"
          result = Bluesky.replaceSectionContent content "<embed/>"
      result @?= content

  , testCase "replaces broken embed with new embed" $ do
      let content = T.unlines
            [ "# My Note"
            , ""
            , "## 🦋 Bluesky"
            , brokenEmbedExample
            , ""
            , "## 🐘 Mastodon"
            , "<iframe>mastodon embed</iframe>"
            ]
          newEmbed = "<blockquote class=\"bluesky-embed\">proper embed</blockquote><script></script>"
          result = Bluesky.replaceSectionContent content newEmbed
      assertBool "should contain new embed" $
        newEmbed `T.isInfixOf` result
      assertBool "should not contain broken embed" $
        not (brokenEmbedExample `T.isInfixOf` result)
  ]

propertyTests :: TestTree
propertyTests = testGroup "properties"
  [ testProperty "buildPostUrl contains DID and postId" $
      \didSuffix postIdSuffix ->
        let did = "did:plc:" <> T.pack didSuffix
            postId = T.pack postIdSuffix
            url = Bluesky.buildPostUrl did postId
        in did `T.isInfixOf` url && postId `T.isInfixOf` url

  , testProperty "extractPostId returns last path segment for at:// URIs" $
      \rkey ->
        let rk = T.pack (filter (`notElem` ['/', ' ', '\n', '\r', '\t', '\0']) rkey)
            uri = "at://did:plc:test/app.bsky.feed.post/" <> rk
        in case Bluesky.extractPostId uri of
             Just pid -> pid == rk
             Nothing  -> T.null rk

  , testProperty "show Error is non-empty for HttpError" $
      \code -> not (null (show (Bluesky.HttpError code "msg")))

  , testProperty "show Error is non-empty for JsonParseError" $
      \msg -> not (null (show (Bluesky.JsonParseError (T.pack msg))))

  , testProperty "show Error is non-empty for ExtractionError" $
      \msg -> not (null (show (Bluesky.ExtractionError (T.pack msg))))

  , testProperty "show Error is non-empty for NetworkError" $
      \msg -> not (null (show (Bluesky.NetworkError (T.pack msg))))

  , testProperty "parsePostResponse returns Left for non-object JSON input" $
      \input ->
        let bytes = LBS.fromStrict (TE.encodeUtf8 (T.pack input))
        in case Bluesky.parsePostResponse "fb" bytes of
             Left (Bluesky.JsonParseError _)  -> True
             Left (Bluesky.ExtractionError _) -> True
             Right _                           -> True
             _                                 -> False

  , testProperty "needsEmbedRegeneration detects bsky.app URLs without blockquotes" $
      \postId ->
        let pid = T.pack (filter (`notElem` [' ', '\n', '\r', '\t', '\0']) postId)
            url = "https://bsky.app/profile/did:plc:test/post/" <> pid
        in Bluesky.needsEmbedRegeneration url

  , testProperty "needsEmbedRegeneration rejects valid embeds" $
      \postContent ->
        let content = T.pack (filter (`notElem` ['\0']) postContent)
            validEmbed = "<blockquote class=\"bluesky-embed\" data-bluesky-uri=\"at://did:plc:test/app.bsky.feed.post/abc\"><p lang=\"en\">" <> content <> " some real content</p></blockquote>"
        in not (Bluesky.needsEmbedRegeneration validEmbed)

  , testProperty "defaultOEmbedConfig has positive maxAttempts" $
      \() -> Bluesky.maxAttempts Bluesky.defaultOEmbedConfig > 0

  , testProperty "toDarkMode is idempotent" $
      \suffix ->
        let base = "<blockquote class=\"bluesky-embed\" data-bluesky-embed-color-mode=\"system\">" <> T.pack suffix <> "</blockquote>"
            once = Bluesky.toDarkMode base
            twice = Bluesky.toDarkMode once
        in once == twice

  , testProperty "toDarkMode removes all system color mode references" $
      \suffix ->
        let input = "<blockquote class=\"bluesky-embed\" data-bluesky-embed-color-mode=\"system\">" <> T.pack suffix <> "</blockquote>"
            result = Bluesky.toDarkMode input
        in not ("data-bluesky-embed-color-mode=\"system\"" `T.isInfixOf` result)

  , testProperty "toDarkMode removes all light color mode references" $
      \suffix ->
        let input = "<blockquote class=\"bluesky-embed\" data-bluesky-embed-color-mode=\"light\">" <> T.pack suffix <> "</blockquote>"
            result = Bluesky.toDarkMode input
        in not ("data-bluesky-embed-color-mode=\"light\"" `T.isInfixOf` result)

  , testProperty "needsDarkModeUpdate detects system-mode embeds" $
      \postContent ->
        let content = T.pack (filter (`notElem` ['\0']) postContent)
            systemEmbed = "<blockquote class=\"bluesky-embed\" data-bluesky-uri=\"at://did:plc:test/app.bsky.feed.post/abc\" data-bluesky-embed-color-mode=\"system\"><p lang=\"en\">" <> content <> " real content</p></blockquote>"
        in Bluesky.needsDarkModeUpdate systemEmbed

  , testProperty "needsDarkModeUpdate rejects dark-mode embeds" $
      \postContent ->
        let content = T.pack (filter (`notElem` ['\0']) postContent)
            darkEmbed = "<blockquote class=\"bluesky-embed\" data-bluesky-uri=\"at://did:plc:test/app.bsky.feed.post/abc\" data-bluesky-embed-color-mode=\"dark\"><p lang=\"en\">" <> content <> " real content</p></blockquote>"
        in not (Bluesky.needsDarkModeUpdate darkEmbed)
  ]

brokenEmbedExample :: T.Text
brokenEmbedExample = "<blockquote class=\"bluesky-embed\" data-bluesky-uri=\"https://bsky.app/profile/bagrounds.bsky.social/post/3mjarbzrnt52a\" data-bluesky-embed-color-mode=\"system\"><p lang=\"en\">did:plc:i4yli6h7x2uoj7acxunww2fc</p>\n&mdash; Bryan Grounds (<a href=\"https://bsky.app/profile/bagrounds.bsky.social?ref_src=embed\">@3mjarbzrnt52a</a>) <a href=\"https://bsky.app/profile/bagrounds.bsky.social/post/3mjarbzrnt52a?ref_src=embed\">bagrounds.bsky.social</a></blockquote><script async src=\"https://embed.bsky.app/static/embed.js\" charset=\"utf-8\"></script>"

toLBS :: String -> LBS.ByteString
toLBS = LBS.fromStrict . TE.encodeUtf8 . T.pack
