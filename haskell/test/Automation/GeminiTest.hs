module Automation.GeminiTest (tests) where

import Data.List (isInfixOf)
import qualified Data.Text as T
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import Test.Tasty.QuickCheck (testProperty)
import qualified Test.QuickCheck as QC

import Automation.Json (Value (Object, Array, String, Number))
import qualified Automation.Gemini as Gemini

tests :: TestTree
tests = testGroup "Gemini"
  [ errorConstructorTests
  , renderErrorTests
  , isRateLimitErrorTests
  , isQuotaExhaustedErrorTests
  , parseResponseTextTests
  , extractTextTests
  , renderErrorPropertyTests
  ]

errorConstructorTests :: TestTree
errorConstructorTests = testGroup "Error constructors"
  [ testCase "JsonParseError equality" $
      Gemini.JsonParseError @?= Gemini.JsonParseError

  , testCase "ExtractionError equality" $
      Gemini.ExtractionError "no text" @?= Gemini.ExtractionError "no text"

  , testCase "ExtractionError inequality" $
      assertBool "different details should differ"
        (Gemini.ExtractionError "no text" /= Gemini.ExtractionError "no parts")

  , testCase "HttpError equality" $
      Gemini.HttpError 429 "rate limited" @?= Gemini.HttpError 429 "rate limited"

  , testCase "HttpError inequality on status" $
      assertBool "different statuses should differ"
        (Gemini.HttpError 429 "body" /= Gemini.HttpError 500 "body")

  , testCase "NoModelsProvided equality" $
      Gemini.NoModelsProvided @?= Gemini.NoModelsProvided

  , testCase "AllModelsFailed equality" $
      Gemini.AllModelsFailed "model" Gemini.JsonParseError
        @?= Gemini.AllModelsFailed "model" Gemini.JsonParseError

  , testCase "AllModelsFailed nested" $
      let inner = Gemini.HttpError 500 "server error"
          outer = Gemini.AllModelsFailed "gemini-flash" inner
      in outer @?= Gemini.AllModelsFailed "gemini-flash" (Gemini.HttpError 500 "server error")

  , testCase "Show instance for JsonParseError" $
      assertBool "Show should produce non-empty string"
        (not (null (show Gemini.JsonParseError)))

  , testCase "Show instance for nested AllModelsFailed" $
      let err = Gemini.AllModelsFailed "testmodel" (Gemini.ExtractionError "detail")
      in assertBool "Show should contain model name"
           ("testmodel" `isInfixOf` show err)
  ]

renderErrorTests :: TestTree
renderErrorTests = testGroup "renderError"
  [ testCase "JsonParseError renders descriptive message" $
      Gemini.renderError Gemini.JsonParseError
        @?= "Failed to parse Gemini response JSON"

  , testCase "ExtractionError includes detail" $
      Gemini.renderError (Gemini.ExtractionError "no text in part")
        @?= "Gemini response extraction failed: no text in part"

  , testCase "HttpError includes status and body" $ do
      let rendered = Gemini.renderError (Gemini.HttpError 429 "quota exceeded")
      assertBool "should contain status code" (T.isInfixOf "429" rendered)
      assertBool "should contain body" (T.isInfixOf "quota exceeded" rendered)

  , testCase "NoModelsProvided renders descriptive message" $
      Gemini.renderError Gemini.NoModelsProvided
        @?= "No models provided for fallback"

  , testCase "AllModelsFailed includes model and inner error" $ do
      let inner = Gemini.HttpError 500 "internal"
          rendered = Gemini.renderError (Gemini.AllModelsFailed "gemini-flash" inner)
      assertBool "should contain model name" (T.isInfixOf "gemini-flash" rendered)
      assertBool "should contain inner error" (T.isInfixOf "500" rendered)
      assertBool "should contain inner body" (T.isInfixOf "internal" rendered)

  , testCase "AllModelsFailed with nested AllModelsFailed" $ do
      let deepInner = Gemini.JsonParseError
          inner = Gemini.AllModelsFailed "model-b" deepInner
          outer = Gemini.AllModelsFailed "model-a" inner
          rendered = Gemini.renderError outer
      assertBool "should contain outer model" (T.isInfixOf "model-a" rendered)
      assertBool "should contain inner model" (T.isInfixOf "model-b" rendered)
  ]

isRateLimitErrorTests :: TestTree
isRateLimitErrorTests = testGroup "isRateLimitError"
  [ testCase "HttpError 429 is rate limit" $
      Gemini.isRateLimitError (Gemini.HttpError 429 "Too Many Requests")
        @?= True

  , testCase "HttpError with RESOURCE_EXHAUSTED is rate limit" $
      Gemini.isRateLimitError (Gemini.HttpError 403 "RESOURCE_EXHAUSTED")
        @?= True

  , testCase "HttpError with quota in body is rate limit" $
      Gemini.isRateLimitError (Gemini.HttpError 403 "quota limit reached")
        @?= True

  , testCase "HttpError 500 without rate limit text is not rate limit" $
      Gemini.isRateLimitError (Gemini.HttpError 500 "Internal Server Error")
        @?= False

  , testCase "JsonParseError is not rate limit" $
      Gemini.isRateLimitError Gemini.JsonParseError
        @?= False

  , testCase "ExtractionError is not rate limit" $
      Gemini.isRateLimitError (Gemini.ExtractionError "no text")
        @?= False

  , testCase "NoModelsProvided is not rate limit" $
      Gemini.isRateLimitError Gemini.NoModelsProvided
        @?= False

  , testCase "AllModelsFailed wrapping rate limit is rate limit" $
      Gemini.isRateLimitError (Gemini.AllModelsFailed "model" (Gemini.HttpError 429 "limit"))
        @?= True

  , testCase "AllModelsFailed wrapping non-rate-limit is not rate limit" $
      Gemini.isRateLimitError (Gemini.AllModelsFailed "model" Gemini.JsonParseError)
        @?= False
  ]

isQuotaExhaustedErrorTests :: TestTree
isQuotaExhaustedErrorTests = testGroup "isQuotaExhaustedError"
  [ testCase "HttpError with daily quota text is quota exhausted" $
      Gemini.isQuotaExhaustedError (Gemini.HttpError 429 "quota daily limit exceeded")
        @?= True

  , testCase "HttpError with per day quota text is quota exhausted" $
      Gemini.isQuotaExhaustedError (Gemini.HttpError 429 "quota per day exceeded")
        @?= True

  , testCase "HttpError with PerDay quota text is quota exhausted" $
      Gemini.isQuotaExhaustedError (Gemini.HttpError 429 "quota PerDay exceeded")
        @?= True

  , testCase "HttpError with only quota (no daily) is not quota exhausted" $
      Gemini.isQuotaExhaustedError (Gemini.HttpError 429 "quota rate limit")
        @?= False

  , testCase "HttpError without quota text is not quota exhausted" $
      Gemini.isQuotaExhaustedError (Gemini.HttpError 429 "Too Many Requests")
        @?= False

  , testCase "JsonParseError is not quota exhausted" $
      Gemini.isQuotaExhaustedError Gemini.JsonParseError
        @?= False

  , testCase "AllModelsFailed wrapping quota exhausted is quota exhausted" $
      Gemini.isQuotaExhaustedError
        (Gemini.AllModelsFailed "model" (Gemini.HttpError 429 "quota daily exceeded"))
        @?= True
  ]

parseResponseTextTests :: TestTree
parseResponseTextTests = testGroup "parseResponseText"
  [ testCase "invalid JSON returns JsonParseError" $
      Gemini.parseResponseText "not json"
        @?= Left Gemini.JsonParseError

  , testCase "empty string returns JsonParseError" $
      Gemini.parseResponseText ""
        @?= Left Gemini.JsonParseError

  , testCase "valid response extracts text" $
      let json = "{\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"hello world\"}]}}]}"
      in Gemini.parseResponseText json
        @?= Right "hello world"

  , testCase "missing candidates returns ExtractionError" $
      Gemini.parseResponseText "{\"other\":\"value\"}"
        @?= Left (Gemini.ExtractionError "no candidates in response")

  , testCase "empty candidates array returns ExtractionError" $
      Gemini.parseResponseText "{\"candidates\":[]}"
        @?= Left (Gemini.ExtractionError "no candidates in response")
  ]

extractTextTests :: TestTree
extractTextTests = testGroup "extractText"
  [ testCase "non-object returns ExtractionError" $
      Gemini.extractText (String "not an object")
        @?= Left (Gemini.ExtractionError "response is not an object")

  , testCase "number returns ExtractionError" $
      Gemini.extractText (Number 42)
        @?= Left (Gemini.ExtractionError "response is not an object")

  , testCase "object without candidates returns ExtractionError" $
      Gemini.extractText (Object [("other", String "val")])
        @?= Left (Gemini.ExtractionError "no candidates in response")

  , testCase "candidates with non-object content returns ExtractionError" $
      let val = Object [("candidates", Array [Object [("content", String "not obj")]])]
      in Gemini.extractText val
        @?= Left (Gemini.ExtractionError "content is not an object")

  , testCase "content with no parts returns ExtractionError" $
      let val = Object [("candidates", Array [Object [("content", Object [("other", String "x")])]])]
      in Gemini.extractText val
        @?= Left (Gemini.ExtractionError "no parts in content")

  , testCase "parts with no text returns ExtractionError" $
      let val = Object [("candidates", Array [Object [("content", Object [("parts", Array [Object [("image", String "data")]])])]])]
      in Gemini.extractText val
        @?= Left (Gemini.ExtractionError "no text in part")

  , testCase "valid structure extracts text" $
      let val = Object
            [ ("candidates", Array
                [ Object
                    [ ("content", Object
                        [ ("parts", Array
                            [ Object [("text", String "extracted")] ]
                          )
                        ]
                      )
                    ]
                ]
              )
            ]
      in Gemini.extractText val
        @?= Right "extracted"
  ]

renderErrorPropertyTests :: TestTree
renderErrorPropertyTests = testGroup "properties"
  [ testProperty "renderError always produces non-empty text" $
      QC.forAll genError $ \err ->
        not (T.null (Gemini.renderError err))

  , testProperty "HttpError 429 is always a rate limit error" $
      QC.forAll (QC.arbitrary :: QC.Gen String) $ \body ->
        Gemini.isRateLimitError (Gemini.HttpError 429 (T.pack body))

  , testProperty "JsonParseError is never a rate limit error" $
      not (Gemini.isRateLimitError Gemini.JsonParseError)

  , testProperty "NoModelsProvided is never a rate limit error" $
      not (Gemini.isRateLimitError Gemini.NoModelsProvided)
  ]

genError :: QC.Gen Gemini.Error
genError = QC.oneof
  [ pure Gemini.JsonParseError
  , Gemini.ExtractionError . T.pack <$> QC.listOf1 QC.arbitraryASCIIChar
  , Gemini.HttpError <$> QC.elements [400, 401, 403, 429, 500, 503] <*> (T.pack <$> QC.arbitrary)
  , pure Gemini.NoModelsProvided
  , Gemini.AllModelsFailed . T.pack <$> QC.listOf1 QC.arbitraryASCIIChar <*> genLeafError
  ]

genLeafError :: QC.Gen Gemini.Error
genLeafError = QC.oneof
  [ pure Gemini.JsonParseError
  , Gemini.ExtractionError . T.pack <$> QC.listOf1 QC.arbitraryASCIIChar
  , Gemini.HttpError <$> QC.elements [400, 401, 403, 429, 500, 503] <*> (T.pack <$> QC.arbitrary)
  , pure Gemini.NoModelsProvided
  ]
