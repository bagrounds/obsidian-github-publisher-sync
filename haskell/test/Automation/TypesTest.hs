module Automation.TypesTest (tests) where

import Data.Text (Text)
import qualified Data.Text as T
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import Test.Tasty.QuickCheck (testProperty)
import qualified Test.QuickCheck as QC

import Automation.Types
  ( Secret (..)
  , PlatformLimits (..)
  , mkSecret
  , twitterLimits
  , blueskyLimits
  , mastodonLimits
  )

tests :: TestTree
tests = testGroup "Types"
  [ secretTests
  , platformLimitsTests
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
      let key = Secret (T.pack secretText)
          shown = show key
      in length secretText > 10 QC.==> not (T.isInfixOf (T.pack secretText) (T.pack shown))

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
