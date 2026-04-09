module Automation.TypesTest (tests) where

import Data.Char (isAlphaNum, isAscii)
import Data.Text (Text)
import qualified Data.Text as T
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import Test.Tasty.QuickCheck (testProperty)
import qualified Test.QuickCheck as QC

import Automation.TestGenerators (testUrl, testTitle, testRelativePath)
import Automation.Types
  ( Secret (..)
  , PlatformLimits (..)
  , Url
  , unUrl
  , Title
  , unTitle
  , RelativePath
  , unRelativePath
  , mkSecret
  , mkUrl
  , mkTitle
  , mkRelativePath
  , twitterLimits
  , blueskyLimits
  , mastodonLimits
  )

tests :: TestTree
tests = testGroup "Types"
  [ secretTests
  , platformLimitsTests
  , urlTests
  , titleTests
  , relativePathTests
  ]

--------------------------------------------------------------------------------
-- Secret tests
--------------------------------------------------------------------------------

secretTests :: TestTree
secretTests = testGroup "Secret"
  [ testCase "Show redacts the key value" $
      show (Secret "super-secret-key-123") @?= "<redacted>"

  , testCase "mkSecret succeeds for non-empty text" $
      mkSecret "my-key" @?= Right (Secret "my-key")

  , testCase "mkSecret rejects empty text" $
      case mkSecret "" of
        Left _ -> pure ()
        Right _ -> fail "Expected Left for empty key"

  , testCase "mkSecret rejects whitespace-only text" $
      case mkSecret "   " of
        Left _ -> pure ()
        Right _ -> fail "Expected Left for whitespace key"

  , testCase "Eq compares underlying values" $
      Secret "abc" @?= Secret "abc"

  , testCase "Eq detects different values" $
      assertBool "Expected different keys to be unequal" (Secret "abc" /= Secret "xyz")

  , testProperty "Show never reveals the key text" $ \secretText ->
      let text = T.pack secretText
          key = Secret text
          shown = show key
      in T.length text > 10 QC.==> not (T.isInfixOf text (T.pack shown))

  , testProperty "mkSecret round-trips for non-empty input" $ \secretText ->
      let text = T.pack secretText
      in not (T.null (T.strip text)) QC.==>
        case mkSecret text of
          Right key -> unSecret key == text
          Left _ -> False
  ]

--------------------------------------------------------------------------------
-- PlatformLimits tests
--------------------------------------------------------------------------------

platformLimitsTests :: TestTree
platformLimitsTests = testGroup "PlatformLimits"
  [ testCase "twitterLimits has correct max characters" $
      platformMaxCharacters twitterLimits @?= 280

  , testCase "twitterLimits has URL count length" $
      platformUrlCountLength twitterLimits @?= Just 23

  , testCase "blueskyLimits has correct max characters" $
      platformMaxCharacters blueskyLimits @?= 300

  , testCase "blueskyLimits has no URL count length" $
      platformUrlCountLength blueskyLimits @?= Nothing

  , testCase "mastodonLimits has correct max characters" $
      platformMaxCharacters mastodonLimits @?= 500

  , testCase "mastodonLimits has no URL count length" $
      platformUrlCountLength mastodonLimits @?= Nothing

  , testProperty "all platform limits have positive max characters" $
      QC.forAll (QC.elements [twitterLimits, blueskyLimits, mastodonLimits]) $
        \limits -> platformMaxCharacters limits > 0

  , testProperty "twitter URL count length is less than max characters" $
      case platformUrlCountLength twitterLimits of
        Just urlLen -> urlLen < platformMaxCharacters twitterLimits
        Nothing -> True
  ]

--------------------------------------------------------------------------------
-- Url tests
--------------------------------------------------------------------------------

urlTests :: TestTree
urlTests = testGroup "Url"
  [ testCase "mkUrl accepts https URL" $
      fmap unUrl (mkUrl "https://example.com") @?= Right "https://example.com"

  , testCase "mkUrl accepts http URL" $
      fmap unUrl (mkUrl "http://example.com") @?= Right "http://example.com"

  , testCase "mkUrl rejects non-URL text" $
      case mkUrl "not a url" of
        Left _ -> pure ()
        Right _ -> fail "Expected Left for invalid URL"

  , testCase "mkUrl rejects empty text" $
      case mkUrl "" of
        Left _ -> pure ()
        Right _ -> fail "Expected Left for empty URL"

  , testCase "Eq compares underlying URLs" $
      testUrl "https://a.com" @?= testUrl "https://a.com"

  , testCase "Eq detects different URLs" $
      assertBool "Expected different URLs to be unequal"
        (testUrl "https://a.com" /= testUrl "https://b.com")

  , testProperty "valid URLs always start with http" $ \suffix ->
      let text = "https://example.com/" <> T.pack (filter isAsciiAlphaNum suffix)
      in case mkUrl text of
           Right url -> T.isPrefixOf "http" (unUrl url)
           Left _ -> True

  , testProperty "mkUrl round-trips for valid input" $ \suffix ->
      let text = "https://example.com/" <> T.pack (filter isAsciiAlphaNum suffix)
      in case mkUrl text of
           Right url -> unUrl url == text
           Left _ -> True

  , testProperty "mkUrl rejects non-http input" $
      QC.forAll (QC.arbitrary `QC.suchThat` (\s -> not (null s) && take 4 s /= "http")) $ \raw ->
        let text = T.pack raw
        in case mkUrl text of
             Left _ -> True
             Right _ -> False
  ]

--------------------------------------------------------------------------------
-- Title tests
--------------------------------------------------------------------------------

titleTests :: TestTree
titleTests = testGroup "Title"
  [ testCase "mkTitle accepts non-empty text" $
      fmap unTitle (mkTitle "Hello World") @?= Right "Hello World"

  , testCase "mkTitle rejects empty text" $
      case mkTitle "" of
        Left _ -> pure ()
        Right _ -> fail "Expected Left for empty title"

  , testCase "mkTitle rejects whitespace-only text" $
      case mkTitle "   " of
        Left _ -> pure ()
        Right _ -> fail "Expected Left for whitespace title"

  , testCase "Eq compares underlying titles" $
      testTitle "abc" @?= testTitle "abc"

  , testCase "Eq detects different titles" $
      assertBool "Expected different titles to be unequal"
        (testTitle "abc" /= testTitle "xyz")

  , testProperty "mkTitle round-trips for non-empty input" $ \raw ->
      let text = T.pack raw
      in not (T.null (T.strip text)) QC.==>
        case mkTitle text of
          Right title -> unTitle title == text
          Left _ -> False

  , testProperty "mkTitle rejects all-whitespace input" $
      QC.forAll (QC.listOf1 (QC.elements [' ', '\t', '\n'])) $ \ws ->
        let text = T.pack ws
        in case mkTitle text of
             Left _ -> True
             Right _ -> False
  ]

--------------------------------------------------------------------------------
-- RelativePath tests
--------------------------------------------------------------------------------

relativePathTests :: TestTree
relativePathTests = testGroup "RelativePath"
  [ testCase "mkRelativePath accepts relative path" $
      fmap unRelativePath (mkRelativePath "content/notes/file.md") @?= Right "content/notes/file.md"

  , testCase "mkRelativePath rejects empty text" $
      case mkRelativePath "" of
        Left _ -> pure ()
        Right _ -> fail "Expected Left for empty path"

  , testCase "mkRelativePath rejects absolute path" $
      case mkRelativePath "/absolute/path" of
        Left _ -> pure ()
        Right _ -> fail "Expected Left for absolute path"

  , testCase "Eq compares underlying paths" $
      testRelativePath "a/b" @?= testRelativePath "a/b"

  , testCase "Eq detects different paths" $
      assertBool "Expected different paths to be unequal"
        (testRelativePath "a/b" /= testRelativePath "c/d")

  , testProperty "mkRelativePath round-trips for valid input" $ \raw ->
      let text = T.pack raw
      in not (T.null text) && not (T.isPrefixOf "/" text) QC.==>
        case mkRelativePath text of
          Right rp -> unRelativePath rp == text
          Left _ -> False

  , testProperty "mkRelativePath rejects absolute paths" $
      QC.forAll (QC.arbitrary `QC.suchThat` (not . null)) $ \suffix ->
        let text = "/" <> T.pack suffix
        in case mkRelativePath text of
             Left _ -> True
             Right _ -> False

  , testProperty "constructed RelativePath never starts with /" $ \raw ->
      let text = T.pack raw
      in not (T.null text) && not (T.isPrefixOf "/" text) QC.==>
        case mkRelativePath text of
          Right rp -> not (T.isPrefixOf "/" (unRelativePath rp))
          Left _ -> True
  ]

isAsciiAlphaNum :: Char -> Bool
isAsciiAlphaNum c = isAscii c && isAlphaNum c
