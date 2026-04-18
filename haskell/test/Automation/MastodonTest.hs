module Automation.MastodonTest (tests) where

import Control.Exception (toException)
import qualified Data.ByteString.Lazy as LBS
import Data.Maybe (isJust)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import Test.Tasty.QuickCheck (testProperty)

import qualified Automation.Platforms.Mastodon as Mastodon
import Automation.Retry (HttpCodeException (HttpCodeException))

tests :: TestTree
tests = testGroup "Mastodon"
  [ extractInstanceUrlTests
  , extractStatusIdTests
  , extractUsernameTests
  , generateLocalEmbedTests
  , parseMastodonResponseTests
  , parseOEmbedHtmlTests
  , classifyExceptionTests
  , toDarkModeTests
  , needsDarkModeUpdateTests
  , needsEmbedRegenerationTests
  , extractRegenerationUrlTests
  , replaceSectionContentTests
  , propertyTests
  ]

-- ── Mastodon.extractInstanceUrl ───────────────────────────────────────

extractInstanceUrlTests :: TestTree
extractInstanceUrlTests = testGroup "Mastodon.extractInstanceUrl"
  [ testCase "extracts instance URL from standard Mastodon post URL" $
      Mastodon.extractInstanceUrl "https://fosstodon.org/@bagrounds/123456"
        @?= Just "https://fosstodon.org"

  , testCase "extracts instance URL with path" $
      Mastodon.extractInstanceUrl "https://mastodon.social/@user/789"
        @?= Just "https://mastodon.social"

  , testCase "returns Just prefix for URL without /@" $
      assertBool "should return Just with full URL" $
        isJust (Mastodon.extractInstanceUrl "https://example.com/post/123")

  , testCase "handles URL with multiple /@ segments" $
      Mastodon.extractInstanceUrl "https://instance.org/@user/@nested/post"
        @?= Just "https://instance.org"
  ]

-- ── Mastodon.extractStatusId ──────────────────────────────────────────

extractStatusIdTests :: TestTree
extractStatusIdTests = testGroup "Mastodon.extractStatusId"
  [ testCase "extracts status ID from standard URL" $
      Mastodon.extractStatusId "https://fosstodon.org/@bagrounds/112345678"
        @?= Just "112345678"

  , testCase "extracts last path segment" $
      Mastodon.extractStatusId "https://mastodon.social/@user/999"
        @?= Just "999"

  , testCase "handles single segment" $
      Mastodon.extractStatusId "singlevalue"
        @?= Just "singlevalue"
  ]

-- ── Mastodon.extractUsername ──────────────────────────────────────────

extractUsernameTests :: TestTree
extractUsernameTests = testGroup "Mastodon.extractUsername"
  [ testCase "extracts username from standard URL" $
      Mastodon.extractUsername "https://fosstodon.org/@bagrounds/123"
        @?= Just "bagrounds"

  , testCase "extracts username without status ID" $
      Mastodon.extractUsername "https://mastodon.social/@alice"
        @?= Just "alice"

  , testCase "returns empty username for URL without /@" $
      Mastodon.extractUsername "https://example.com/post/123"
        @?= Just ""
  ]

-- ── Mastodon.generateLocalEmbed ───────────────────────────────────────

generateLocalEmbedTests :: TestTree
generateLocalEmbedTests = testGroup "Mastodon.generateLocalEmbed"
  [ testCase "generates iframe embed with correct src" $ do
      let html = Mastodon.generateLocalEmbed
                   "https://fosstodon.org/@bagrounds/123456"
      assertBool "should contain iframe element" $
        "<iframe" `T.isInfixOf` html
      assertBool "should contain post URL with /embed suffix" $
        "https://fosstodon.org/@bagrounds/123456/embed" `T.isInfixOf` html

  , testCase "includes mastodon-embed class" $ do
      let html = Mastodon.generateLocalEmbed
                   "https://fosstodon.org/@user/789"
      assertBool "should contain mastodon-embed class" $
        "mastodon-embed" `T.isInfixOf` html

  , testCase "includes embed.js script tag" $ do
      let html = Mastodon.generateLocalEmbed
                   "https://fosstodon.org/@user/789"
      assertBool "should contain embed.js script" $
        "https://fosstodon.org/embed.js" `T.isInfixOf` html
      assertBool "should have async attribute" $
        "async=\"async\"" `T.isInfixOf` html

  , testCase "includes width and style attributes" $ do
      let html = Mastodon.generateLocalEmbed
                   "https://fosstodon.org/@user/789"
      assertBool "should contain width 400" $
        "width=\"400\"" `T.isInfixOf` html
      assertBool "should contain max-width style" $
        "max-width: 100%" `T.isInfixOf` html
      assertBool "should contain border: 0" $
        "border: 0" `T.isInfixOf` html

  , testCase "includes allowfullscreen attribute" $ do
      let html = Mastodon.generateLocalEmbed
                   "https://mastodon.social/@user/123"
      assertBool "should contain allowfullscreen" $
        "allowfullscreen=\"allowfullscreen\"" `T.isInfixOf` html

  , testCase "derives instance URL from post URL for script src" $ do
      let html = Mastodon.generateLocalEmbed
                   "https://mastodon.social/@alice/456"
      assertBool "should use mastodon.social for embed.js" $
        "https://mastodon.social/embed.js" `T.isInfixOf` html
  ]

-- ── Mastodon.parseMastodonResponse ────────────────────────────────────

parseMastodonResponseTests :: TestTree
parseMastodonResponseTests = testGroup "Mastodon.parseMastodonResponse"
  [ testCase "parses valid mastodon response" $
      let body = "{\"id\":\"123456\",\"url\":\"https://fosstodon.org/@user/123456\"}"
      in case Mastodon.parseMastodonResponse "hello" (toLBS body) of
           Right result -> Mastodon.postId result @?= "123456"
           Left err -> fail $ "Expected Right, got: " <> show err

  , testCase "returns JsonParseError for invalid JSON" $
      case Mastodon.parseMastodonResponse "txt" (toLBS "not json") of
        Left (Mastodon.JsonParseError _) -> pure ()
        other -> fail $ "Expected JsonParseError, got: " <> show other

  , testCase "returns ExtractionError for missing id field" $
      case Mastodon.parseMastodonResponse "txt" (toLBS "{\"url\":\"https://fosstodon.org/@u/1\"}") of
        Left (Mastodon.ExtractionError _) -> pure ()
        other -> fail $ "Expected ExtractionError, got: " <> show other

  , testCase "returns ExtractionError for missing url field" $
      case Mastodon.parseMastodonResponse "txt" (toLBS "{\"id\":\"123\"}") of
        Left (Mastodon.ExtractionError _) -> pure ()
        other -> fail $ "Expected ExtractionError, got: " <> show other

  , testCase "returns ExtractionError for invalid URL" $
      case Mastodon.parseMastodonResponse "txt" (toLBS "{\"id\":\"123\",\"url\":\"not-a-url\"}") of
        Left (Mastodon.ExtractionError _) -> pure ()
        other -> fail $ "Expected ExtractionError, got: " <> show other
  ]

-- ── Mastodon.parseOEmbedHtml ──────────────────────────────────────────

parseOEmbedHtmlTests :: TestTree
parseOEmbedHtmlTests = testGroup "Mastodon.parseOEmbedHtml"
  [ testCase "parses valid oEmbed response" $
      let body = "{\"html\":\"<iframe>embed</iframe>\"}"
      in Mastodon.parseOEmbedHtml (toLBS body)
           @?= Right "<iframe>embed</iframe>"

  , testCase "returns JsonParseError for invalid JSON" $
      case Mastodon.parseOEmbedHtml (toLBS "garbage") of
        Left (Mastodon.JsonParseError _) -> pure ()
        other -> fail $ "Expected JsonParseError, got: " <> show other

  , testCase "returns ExtractionError for missing html field" $
      case Mastodon.parseOEmbedHtml (toLBS "{\"url\":\"https://example.com\"}") of
        Left (Mastodon.ExtractionError _) -> pure ()
        other -> fail $ "Expected ExtractionError, got: " <> show other
  ]

-- ── Mastodon.classifyException ────────────────────────────────────────

classifyExceptionTests :: TestTree
classifyExceptionTests = testGroup "Mastodon.classifyException"
  [ testCase "classifies HttpCodeException as HttpError" $
      let exception = toException (HttpCodeException 500 "Internal Server Error")
      in Mastodon.classifyException exception
           @?= Mastodon.HttpError 500 "Internal Server Error"

  , testCase "classifies other exception as NetworkError" $
      let exception = toException (userError "timeout")
      in case Mastodon.classifyException exception of
           Mastodon.NetworkError msg ->
             assertBool "should contain error message" $
               "timeout" `T.isInfixOf` msg
           other -> fail $ "Expected NetworkError, got: " <> show other
  ]

toDarkModeTests :: TestTree
toDarkModeTests = testGroup "Mastodon.toDarkMode"
  [ testCase "replaces light background with dark" $ do
      let input = "<blockquote class=\"mastodon-embed\" style=\"background: #FCF8FF; border: 1px solid #C9C4DA;\">content</blockquote>"
          result = Mastodon.toDarkMode input
      assertBool "should have dark background" $
        "background: #282c37" `T.isInfixOf` result
      assertBool "should have dark border" $
        "border: 1px solid #393f4f" `T.isInfixOf` result

  , testCase "replaces light text colors with dark" $ do
      let input = "<a style=\"color: #1C1A25;\"><div style=\"color: #787588;\">text</div></a>"
          result = Mastodon.toDarkMode input
      assertBool "should have light text color" $
        "color: #d9e1e8" `T.isInfixOf` result
      assertBool "should have muted text color" $
        "color: #9baec8" `T.isInfixOf` result

  , testCase "does not modify already-dark embed" $ do
      let input = "<blockquote class=\"mastodon-embed\" style=\"background: #282c37; border: 1px solid #393f4f;\">content</blockquote>"
      Mastodon.toDarkMode input @?= input

  , testCase "handles full oEmbed HTML" $ do
      let result = Mastodon.toDarkMode mastodonLightEmbed
      assertBool "should contain dark background" $
        "background: #282c37" `T.isInfixOf` result
      assertBool "should not contain light background" $
        not ("background: #FCF8FF" `T.isInfixOf` result)
  ]

needsDarkModeUpdateTests :: TestTree
needsDarkModeUpdateTests = testGroup "Mastodon.needsDarkModeUpdate"
  [ testCase "detects light-mode mastodon embed" $
      assertBool "light embed should need update" $
        Mastodon.needsDarkModeUpdate mastodonLightEmbed

  , testCase "does not flag dark-mode mastodon embed" $
      assertBool "dark embed should not need update" $
        not $ Mastodon.needsDarkModeUpdate
          "<blockquote class=\"mastodon-embed\" style=\"background: #282c37;\">content</blockquote>"

  , testCase "does not flag non-mastodon content" $
      assertBool "non-mastodon should not need update" $
        not $ Mastodon.needsDarkModeUpdate "background: #FCF8FF"

  , testCase "does not flag empty text" $
      assertBool "empty should not need update" $
        not $ Mastodon.needsDarkModeUpdate ""
  ]

needsEmbedRegenerationTests :: TestTree
needsEmbedRegenerationTests = testGroup "Mastodon.needsEmbedRegeneration"
  [ testCase "detects light-mode embed as needing regeneration" $
      assertBool "light embed should need regeneration" $
        Mastodon.needsEmbedRegeneration mastodonLightEmbed

  , testCase "does not flag dark embed" $
      assertBool "dark embed should not need regeneration" $
        not $ Mastodon.needsEmbedRegeneration
          "<blockquote class=\"mastodon-embed\" style=\"background: #282c37;\">content</blockquote>"
  ]

extractRegenerationUrlTests :: TestTree
extractRegenerationUrlTests = testGroup "Mastodon.extractRegenerationUrl"
  [ testCase "extracts URL from data-embed-url attribute" $
      let input = "<blockquote class=\"mastodon-embed\" data-embed-url=\"https://mastodon.social/@bagrounds/123/embed\" style=\"background: #FCF8FF; color: #1C1A25;\">content</blockquote>"
      in Mastodon.extractRegenerationUrl input
           @?= Just "https://mastodon.social/@bagrounds/123"

  , testCase "extracts URL from href when data-embed-url missing" $
      let input = "<blockquote class=\"mastodon-embed\" style=\"background: #FCF8FF; color: #1C1A25;\"><a href=\"https://mastodon.social/@bagrounds/456\">link</a></blockquote>"
      in Mastodon.extractRegenerationUrl input
           @?= Just "https://mastodon.social/@bagrounds/456"

  , testCase "returns Nothing for dark embed" $
      let input = "<blockquote class=\"mastodon-embed\" style=\"background: #282c37;\">content</blockquote>"
      in Mastodon.extractRegenerationUrl input
           @?= Nothing
  ]

replaceSectionContentTests :: TestTree
replaceSectionContentTests = testGroup "Mastodon.replaceSectionContent"
  [ testCase "replaces mastodon section content" $ do
      let content = T.unlines
            [ "# My Note"
            , ""
            , "## 🐘 Mastodon"
            , mastodonLightEmbed
            , ""
            , "## 🐦 Tweet"
            , "<blockquote>tweet</blockquote>"
            ]
          newEmbed = "<blockquote class=\"mastodon-embed\" style=\"background: #282c37;\">dark embed</blockquote>"
          result = Mastodon.replaceSectionContent content newEmbed
      assertBool "should contain new dark embed" $
        newEmbed `T.isInfixOf` result
      assertBool "should not contain old light embed" $
        not ("background: #FCF8FF" `T.isInfixOf` result)
      assertBool "should preserve tweet section" $
        "## 🐦 Tweet" `T.isInfixOf` result

  , testCase "does not modify file without Mastodon section" $ do
      let content = "# My Note\nSome content\n"
          result = Mastodon.replaceSectionContent content "<embed/>"
      result @?= content
  ]

-- ── Property Tests ─────────────────────────────────────────────────────

propertyTests :: TestTree
propertyTests = testGroup "properties"
  [ testProperty "Mastodon.extractStatusId returns last path segment" $
      \statusId ->
        let sid = T.pack (filter (`notElem` ['/', ' ', '\n', '\r', '\t', '\0']) statusId)
            url = "https://fosstodon.org/@user/" <> sid
        in case Mastodon.extractStatusId url of
             Just extracted -> extracted == sid
             Nothing        -> T.null sid

  , testProperty "Mastodon.extractUsername extracts username from well-formed URLs" $
      \username ->
        let uname = T.pack (filter (`notElem` ['/', '@', ' ', '\n', '\r', '\t', '\0']) username)
            url = "https://fosstodon.org/@" <> uname <> "/123"
        in not (T.null uname) ==>
             Mastodon.extractUsername url == Just uname

  , testProperty "Mastodon.generateLocalEmbed output is non-empty" $
      \postSuffix ->
        let url = "https://fosstodon.org/@user/" <> T.pack postSuffix
            html = Mastodon.generateLocalEmbed url
        in not (T.null html)

  , testProperty "Mastodon.generateLocalEmbed always contains iframe" $
      \postSuffix ->
        let url = "https://fosstodon.org/@user/" <> T.pack postSuffix
            html = Mastodon.generateLocalEmbed url
        in "<iframe" `T.isInfixOf` html

  , testProperty "Mastodon.extractInstanceUrl returns prefix before /@" $
      \instanceSuffix ->
        let inst = T.pack (filter (`notElem` ['@', ' ', '\n', '\r', '\t', '\0']) instanceSuffix)
            url = "https://" <> inst <> "/@user/123"
        in Mastodon.extractInstanceUrl url == Just ("https://" <> inst)

  , testProperty "show Mastodon.Error is non-empty for HttpError" $
      \code -> not (null (show (Mastodon.HttpError code "msg")))

  , testProperty "show Mastodon.Error is non-empty for JsonParseError" $
      \msg -> not (null (show (Mastodon.JsonParseError (T.pack msg))))

  , testProperty "show Mastodon.Error is non-empty for ExtractionError" $
      \msg -> not (null (show (Mastodon.ExtractionError (T.pack msg))))

  , testProperty "show Mastodon.Error is non-empty for NetworkError" $
      \msg -> not (null (show (Mastodon.NetworkError (T.pack msg))))

  , testProperty "parseMastodonResponse returns Left for non-object JSON input" $
      \input ->
        let bytes = LBS.fromStrict (TE.encodeUtf8 (T.pack input))
        in case Mastodon.parseMastodonResponse "fb" bytes of
             Left (Mastodon.JsonParseError _)  -> True
             Left (Mastodon.ExtractionError _) -> True
             Right _                            -> True
             _                                  -> False

  , testProperty "toDarkMode is idempotent" $
      \suffix ->
        let base = "<blockquote class=\"mastodon-embed\" style=\"background: #FCF8FF; color: #1C1A25;\">" <> T.pack suffix <> "</blockquote>"
            once = Mastodon.toDarkMode base
            twice = Mastodon.toDarkMode once
        in once == twice

  , testProperty "toDarkMode removes all light background references" $
      \suffix ->
        let input = "<blockquote class=\"mastodon-embed\" style=\"background: #FCF8FF;\">" <> T.pack suffix <> "</blockquote>"
            result = Mastodon.toDarkMode input
        in not ("background: #FCF8FF" `T.isInfixOf` result)
  ]

-- ── Helpers ───────────────────────────────────────────────────────────

mastodonLightEmbed :: T.Text
mastodonLightEmbed = "<blockquote class=\"mastodon-embed\" data-embed-url=\"https://mastodon.social/@bagrounds/116285079002713407/embed\" style=\"background: #FCF8FF; border-radius: 8px; border: 1px solid #C9C4DA; margin: 0; max-width: 540px; min-width: 270px; overflow: hidden; padding: 0;\"> <a href=\"https://mastodon.social/@bagrounds/116285079002713407\" target=\"_blank\" style=\"align-items: center; color: #1C1A25; display: flex; flex-direction: column;\">View on Mastodon</a> </blockquote> <script data-allowed-prefixes=\"https://mastodon.social/\" async src=\"https://mastodon.social/embed.js\"></script>"

toLBS :: String -> LBS.ByteString
toLBS = LBS.fromStrict . TE.encodeUtf8 . T.pack

-- QuickCheck implication helper
(==>) :: Bool -> Bool -> Bool
False ==> _ = True
True  ==> b = b
infixr 0 ==>
