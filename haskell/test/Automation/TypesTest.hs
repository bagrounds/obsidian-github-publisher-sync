module Automation.TypesTest (tests) where

import Data.Text (Text)
import qualified Data.Text as T
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import Test.Tasty.QuickCheck (testProperty)
import qualified Test.QuickCheck as QC

import Automation.Types
  ( Secret (..)
  , DateStr (..)
  , PlatformLimits (..)
  , mkSecret
  , mkDateStr
  , twitterLimits
  , blueskyLimits
  , mastodonLimits
  )

tests :: TestTree
tests = testGroup "Types"
  [ secretTests
  , dateStrTests
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

  , testProperty "Show never reveals the key text" $ \keyText ->
      let key = Secret (T.pack keyText)
          shown = show key
      in length keyText > 10 QC.==> not (T.isInfixOf (T.pack keyText) (T.pack shown))

  , testProperty "mkSecret round-trips for non-empty input" $ \keyText ->
      let text = T.pack keyText
      in not (T.null (T.strip text)) QC.==>
        case mkSecret text of
          Right key -> unSecret key == text
          Left _ -> False
  ]

--------------------------------------------------------------------------------
-- DateStr tests
--------------------------------------------------------------------------------

dateStrTests :: TestTree
dateStrTests = testGroup "DateStr"
  [ testCase "mkDateStr succeeds for valid date" $
      mkDateStr "2026-04-08" @?= Right (DateStr "2026-04-08")

  , testCase "mkDateStr rejects short string" $
      case mkDateStr "2026-04" of
        Left _ -> pure ()
        Right _ -> fail "Expected Left for short date"

  , testCase "mkDateStr rejects wrong separators" $
      case mkDateStr "2026/04/08" of
        Left _ -> pure ()
        Right _ -> fail "Expected Left for wrong separators"

  , testCase "mkDateStr rejects long string" $
      case mkDateStr "2026-04-08X" of
        Left _ -> pure ()
        Right _ -> fail "Expected Left for long date"

  , testCase "Show displays the date value" $
      show (DateStr "2026-04-08") @?= "DateStr \"2026-04-08\""

  , testCase "unDateStr extracts the value" $
      unDateStr (DateStr "2026-04-08") @?= "2026-04-08"

  , testProperty "mkDateStr round-trips valid YYYY-MM-DD dates" $ do
      year <- QC.choose (2000 :: Int, 2099)
      month <- QC.choose (1 :: Int, 12)
      day <- QC.choose (1 :: Int, 28)
      let dateText = T.pack $ show year <> "-" <> padTwo month <> "-" <> padTwo day
      pure $ case mkDateStr dateText of
        Right ds -> unDateStr ds == dateText
        Left _ -> False
  ]

padTwo :: Int -> String
padTwo n
  | n < 10   = "0" <> show n
  | otherwise = show n

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
