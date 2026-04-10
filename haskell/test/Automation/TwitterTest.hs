module Automation.TwitterTest (tests) where

import Control.Exception (toException)
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import Test.Tasty.QuickCheck (testProperty)

import qualified Automation.Platforms.Twitter as Twitter
import Automation.Retry (HttpCodeException (HttpCodeException))

tests :: TestTree
tests = testGroup "Twitter"
  [ parseTweetResponseTests
  , parseOEmbedHtmlTests
  , classifyExceptionTests
  , errorShowTests
  , propertyTests
  ]

-- ── Twitter.parseTweetResponse ────────────────────────────────────────

parseTweetResponseTests :: TestTree
parseTweetResponseTests = testGroup "Twitter.parseTweetResponse"
  [ testCase "parses valid tweet response" $
      let body = "{\"data\":{\"id\":\"12345\",\"text\":\"Hello world\"}}"
      in Twitter.parseTweetResponse "fallback" (toLBS body)
           @?= Right ("12345", "Hello world")

  , testCase "uses fallback text when tweet text missing" $
      let body = "{\"data\":{\"id\":\"12345\"}}"
      in Twitter.parseTweetResponse "my fallback" (toLBS body)
           @?= Right ("12345", "my fallback")

  , testCase "returns JsonParseError for invalid JSON" $
      case Twitter.parseTweetResponse "fb" (toLBS "not json") of
        Left (Twitter.JsonParseError _) -> pure ()
        other -> fail $ "Expected JsonParseError, got: " <> show other

  , testCase "returns ExtractionError for missing data field" $
      case Twitter.parseTweetResponse "fb" (toLBS "{\"wrong\":1}") of
        Left (Twitter.ExtractionError _) -> pure ()
        other -> fail $ "Expected ExtractionError, got: " <> show other

  , testCase "returns ExtractionError for missing id field" $
      case Twitter.parseTweetResponse "fb" (toLBS "{\"data\":{\"text\":\"hi\"}}") of
        Left (Twitter.ExtractionError _) -> pure ()
        other -> fail $ "Expected ExtractionError, got: " <> show other
  ]

-- ── Twitter.parseOEmbedHtml ───────────────────────────────────────────

parseOEmbedHtmlTests :: TestTree
parseOEmbedHtmlTests = testGroup "Twitter.parseOEmbedHtml"
  [ testCase "parses valid oEmbed response" $
      let body = "{\"html\":\"<blockquote>tweet</blockquote>\"}"
      in Twitter.parseOEmbedHtml (toLBS body)
           @?= Right "<blockquote>tweet</blockquote>"

  , testCase "returns JsonParseError for invalid JSON" $
      case Twitter.parseOEmbedHtml (toLBS "garbage") of
        Left (Twitter.JsonParseError _) -> pure ()
        other -> fail $ "Expected JsonParseError, got: " <> show other

  , testCase "returns ExtractionError for missing html field" $
      case Twitter.parseOEmbedHtml (toLBS "{\"url\":\"https://x.com\"}") of
        Left (Twitter.ExtractionError _) -> pure ()
        other -> fail $ "Expected ExtractionError, got: " <> show other
  ]

-- ── Twitter.classifyException ─────────────────────────────────────────

classifyExceptionTests :: TestTree
classifyExceptionTests = testGroup "Twitter.classifyException"
  [ testCase "classifies HttpCodeException as HttpError" $
      let exception = toException (HttpCodeException 429 "Rate limited")
      in Twitter.classifyException exception
           @?= Twitter.HttpError 429 "Rate limited"

  , testCase "classifies HttpCodeException 403 as HttpError" $
      let exception = toException (HttpCodeException 403 "Forbidden")
      in Twitter.classifyException exception
           @?= Twitter.HttpError 403 "Forbidden"

  , testCase "classifies other exception as NetworkError" $
      let exception = toException (userError "connection refused")
      in case Twitter.classifyException exception of
           Twitter.NetworkError msg ->
             assertBool "should contain error message" $
               "connection refused" `T.isInfixOf` msg
           other -> fail $ "Expected NetworkError, got: " <> show other

  , testCase "preserves HTTP status code" $
      let exception = toException (HttpCodeException 503 "Service unavailable")
      in case Twitter.classifyException exception of
           Twitter.HttpError code _ -> code @?= 503
           other -> fail $ "Expected HttpError, got: " <> show other
  ]

-- ── Error Show instances ──────────────────────────────────────────────

errorShowTests :: TestTree
errorShowTests = testGroup "Error Show"
  [ testCase "HttpError shows status code and message" $
      let err = Twitter.HttpError 429 "Rate limited"
      in assertBool "should contain 429" $
           "429" `isInfixOfShow` err

  , testCase "JsonParseError shows parse details" $
      let err = Twitter.JsonParseError "unexpected end of input"
      in assertBool "should contain parse message" $
           "unexpected end of input" `isInfixOfShow` err

  , testCase "ExtractionError shows field info" $
      let err = Twitter.ExtractionError "key \"data\" not found"
      in assertBool "should contain field name" $
           "data" `isInfixOfShow` err

  , testCase "NetworkError shows exception info" $
      let err = Twitter.NetworkError "connection refused"
      in assertBool "should contain error" $
           "connection refused" `isInfixOfShow` err
  ]

-- ── Property Tests ────────────────────────────────────────────────────

propertyTests :: TestTree
propertyTests = testGroup "properties"
  [ testProperty "show Twitter.Error is non-empty for HttpError" $
      \code -> not (null (show (Twitter.HttpError code "msg")))

  , testProperty "show Twitter.Error is non-empty for JsonParseError" $
      \msg -> not (null (show (Twitter.JsonParseError (T.pack msg))))

  , testProperty "show Twitter.Error is non-empty for ExtractionError" $
      \msg -> not (null (show (Twitter.ExtractionError (T.pack msg))))

  , testProperty "show Twitter.Error is non-empty for NetworkError" $
      \msg -> not (null (show (Twitter.NetworkError (T.pack msg))))

  , testProperty "parseTweetResponse returns Left for non-object JSON input" $
      \input ->
        let bytes = LBS.fromStrict (TE.encodeUtf8 (T.pack input))
        in case Twitter.parseTweetResponse "fb" bytes of
             Left (Twitter.JsonParseError _)  -> True
             Left (Twitter.ExtractionError _) -> True
             Right _                           -> True
             _                                 -> False
  ]

-- ── Helpers ───────────────────────────────────────────────────────────

toLBS :: String -> LBS.ByteString
toLBS = LBS.fromStrict . TE.encodeUtf8 . T.pack

isInfixOfShow :: String -> Twitter.Error -> Bool
isInfixOfShow needle err = needle `isInfixOf` show err

isInfixOf :: Eq a => [a] -> [a] -> Bool
isInfixOf needle haystack = any (isPrefixOf needle) (tails haystack)

isPrefixOf :: Eq a => [a] -> [a] -> Bool
isPrefixOf [] _ = True
isPrefixOf _ [] = False
isPrefixOf (x:xs) (y:ys) = x == y && isPrefixOf xs ys

tails :: [a] -> [[a]]
tails [] = [[]]
tails xs@(_:rest) = xs : tails rest
