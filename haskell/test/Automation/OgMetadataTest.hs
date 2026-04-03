module Automation.OgMetadataTest (tests) where

import Data.Maybe (isJust, isNothing)
import Data.Text (Text)
import qualified Data.Text as T
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import Test.Tasty.QuickCheck (testProperty)

import Automation.Platforms.OgMetadata (extractOgProperty, detectContentType)

tests :: TestTree
tests = testGroup "OgMetadata"
  [ extractOgPropertyTests
  , detectContentTypeTests
  , propertyTests
  ]

-- ── extractOgProperty ────────────────────────────────────────────────────

sampleHtml :: Text
sampleHtml = T.unlines
  [ "<!DOCTYPE html>"
  , "<html><head>"
  , "<meta property=\"og:title\" content=\"My Page Title\"/>"
  , "<meta property=\"og:description\" content=\"A short description of the page\"/>"
  , "<meta property=\"og:image\" content=\"https://example.com/image.webp\"/>"
  , "<meta property=\"og:image:url\" content=\"https://example.com/image.webp\"/>"
  , "<meta property=\"og:image:type\" content=\"image/webp\"/>"
  , "<meta property=\"og:url\" content=\"https://example.com/page\"/>"
  , "</head><body></body></html>"
  ]

extractOgPropertyTests :: TestTree
extractOgPropertyTests = testGroup "extractOgProperty"
  [ testCase "extracts og:title" $
      extractOgProperty "title" sampleHtml
        @?= Just "My Page Title"

  , testCase "extracts og:description" $
      extractOgProperty "description" sampleHtml
        @?= Just "A short description of the page"

  , testCase "extracts og:image" $
      extractOgProperty "image" sampleHtml
        @?= Just "https://example.com/image.webp"

  , testCase "extracts og:url" $
      extractOgProperty "url" sampleHtml
        @?= Just "https://example.com/page"

  , testCase "returns Nothing for missing property" $
      assertBool "should be Nothing" $
        isNothing (extractOgProperty "video" sampleHtml)

  , testCase "returns Nothing for empty HTML" $
      assertBool "should be Nothing" $
        isNothing (extractOgProperty "title" "")

  , testCase "handles HTML with lots of content before og tags" $ do
      let bigHtml = T.replicate 10000 "x" <> "<meta property=\"og:title\" content=\"Found It\"/>"
      extractOgProperty "title" bigHtml @?= Just "Found It"

  , testCase "handles emoji in content" $ do
      let html = "<meta property=\"og:title\" content=\"🎵 Music 🎶\"/>"
      extractOgProperty "title" html @?= Just "🎵 Music 🎶"

  , testCase "handles special characters in description" $ do
      let html = "<meta property=\"og:description\" content=\"A &amp; B &lt; C\"/>"
      extractOgProperty "description" html @?= Just "A &amp; B &lt; C"

  , testCase "handles multiline HTML" $ do
      let html = "<head>\n<meta property=\"og:title\" content=\"Title\"/>\n</head>"
      extractOgProperty "title" html @?= Just "Title"

  , testCase "extracts first match when multiple exist" $ do
      let html = T.concat
            [ "<meta property=\"og:image\" content=\"first.png\"/>"
            , "<meta property=\"og:image\" content=\"second.png\"/>"
            ]
      extractOgProperty "image" html @?= Just "first.png"

  , testCase "does not match name attribute (only property)" $
      assertBool "should be Nothing for name=og:title" $
        isNothing (extractOgProperty "title" "<meta name=\"og:title\" content=\"Wrong\"/>")

  , testCase "works with real-world Quartz HTML structure" $ do
      let quartzHtml = T.concat
            [ "<head><title>Page</title>"
            , "<meta property=\"og:title\" content=\"2026-04-02 | Reflection\"/>"
            , "<meta property=\"og:type\" content=\"website\"/>"
            , "<meta property=\"og:description\" content=\"Daily reflection\"/>"
            , "<style>body { color: red; }</style>"
            , "<script>const x = 1</script>"
            , "<meta property=\"og:image\" content=\"https://bagrounds.org/reflections/2026-04-02-og-image.webp\"/>"
            , "</head>"
            ]
      extractOgProperty "title" quartzHtml @?= Just "2026-04-02 | Reflection"
      extractOgProperty "description" quartzHtml @?= Just "Daily reflection"
      extractOgProperty "image" quartzHtml @?= Just "https://bagrounds.org/reflections/2026-04-02-og-image.webp"
  ]

-- ── detectContentType ────────────────────────────────────────────────────

detectContentTypeTests :: TestTree
detectContentTypeTests = testGroup "detectContentType"
  [ testCase "detects webp" $
      detectContentType "https://example.com/image.webp" @?= "image/webp"

  , testCase "detects png" $
      detectContentType "https://example.com/image.png" @?= "image/png"

  , testCase "detects gif" $
      detectContentType "https://example.com/image.gif" @?= "image/gif"

  , testCase "detects svg" $
      detectContentType "https://example.com/image.svg" @?= "image/svg+xml"

  , testCase "defaults to jpeg" $
      detectContentType "https://example.com/image.jpg" @?= "image/jpeg"

  , testCase "defaults to jpeg for unknown extension" $
      detectContentType "https://example.com/image.bmp" @?= "image/jpeg"

  , testCase "case insensitive" $
      detectContentType "https://example.com/IMAGE.WEBP" @?= "image/webp"

  , testCase "handles URL with query parameters" $
      detectContentType "https://example.com/image.png?v=1" @?= "image/png"

  , testCase "handles URL with fragment" $
      detectContentType "https://example.com/image.webp#section" @?= "image/webp"
  ]

-- ── Property Tests ───────────────────────────────────────────────────────

propertyTests :: TestTree
propertyTests = testGroup "properties"
  [ testProperty "extractOgProperty returns Nothing for random text" $
      \rawText ->
        let text = T.pack rawText
        in isNothing (extractOgProperty "nonexistent_property_xyz" text)
             || isJust (extractOgProperty "nonexistent_property_xyz" text)

  , testProperty "extractOgProperty roundtrips embedded values" $
      \rawValue ->
        let value = T.pack (filter (\c -> c /= '"' && c /= '\n' && c /= '\r') rawValue)
            html = "<meta property=\"og:test\" content=\"" <> value <> "\"/>"
        in extractOgProperty "test" html == Just value

  , testProperty "detectContentType always returns a valid MIME type" $
      \rawUrl ->
        let url = T.pack rawUrl
            ct = detectContentType url
        in "image/" `T.isPrefixOf` ct
  ]
