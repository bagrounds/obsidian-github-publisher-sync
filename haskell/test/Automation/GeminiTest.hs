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
  [ apiStatusTests
  , errorConstructorTests
  , showErrorTests
  , isRateLimitErrorTests
  , isQuotaExhaustedErrorTests
  , parseErrorBodyTests
  , parseResponseTextTests
  , extractTextTests
  , propertyTests
  ]

apiStatusTests :: TestTree
apiStatusTests = testGroup "ApiStatus"
  [ testCase "RESOURCE_EXHAUSTED parses to ResourceExhausted" $
      Gemini.parseApiStatus "RESOURCE_EXHAUSTED" @?= Gemini.ResourceExhausted

  , testCase "INVALID_ARGUMENT parses to InvalidArgument" $
      Gemini.parseApiStatus "INVALID_ARGUMENT" @?= Gemini.InvalidArgument

  , testCase "PERMISSION_DENIED parses to PermissionDenied" $
      Gemini.parseApiStatus "PERMISSION_DENIED" @?= Gemini.PermissionDenied

  , testCase "NOT_FOUND parses to NotFound" $
      Gemini.parseApiStatus "NOT_FOUND" @?= Gemini.NotFound

  , testCase "INTERNAL parses to InternalError" $
      Gemini.parseApiStatus "INTERNAL" @?= Gemini.InternalError

  , testCase "UNAVAILABLE parses to Unavailable" $
      Gemini.parseApiStatus "UNAVAILABLE" @?= Gemini.Unavailable

  , testCase "DEADLINE_EXCEEDED parses to DeadlineExceeded" $
      Gemini.parseApiStatus "DEADLINE_EXCEEDED" @?= Gemini.DeadlineExceeded

  , testCase "UNAUTHENTICATED parses to Unauthenticated" $
      Gemini.parseApiStatus "UNAUTHENTICATED" @?= Gemini.Unauthenticated

  , testCase "FAILED_PRECONDITION parses to FailedPrecondition" $
      Gemini.parseApiStatus "FAILED_PRECONDITION" @?= Gemini.FailedPrecondition

  , testCase "unknown status preserves original text" $
      Gemini.parseApiStatus "SOMETHING_NEW" @?= Gemini.UnknownStatus "SOMETHING_NEW"
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

  , testCase "HttpError with ApiStatus equality" $
      Gemini.HttpError 429 Gemini.ResourceExhausted "rate limited"
        @?= Gemini.HttpError 429 Gemini.ResourceExhausted "rate limited"

  , testCase "HttpError inequality on status" $
      assertBool "different statuses should differ"
        (Gemini.HttpError 429 Gemini.ResourceExhausted "body"
          /= Gemini.HttpError 500 Gemini.InternalError "body")

  , testCase "HttpError inequality on ApiStatus" $
      assertBool "different API statuses should differ"
        (Gemini.HttpError 429 Gemini.ResourceExhausted "body"
          /= Gemini.HttpError 429 (Gemini.UnknownStatus "OTHER") "body")

  , testCase "AllModelsFailed equality" $
      Gemini.AllModelsFailed "model" Gemini.JsonParseError
        @?= Gemini.AllModelsFailed "model" Gemini.JsonParseError

  , testCase "AllModelsFailed nested" $
      let inner = Gemini.HttpError 500 Gemini.InternalError "server error"
          outer = Gemini.AllModelsFailed "gemini-flash" inner
      in outer @?= Gemini.AllModelsFailed "gemini-flash"
           (Gemini.HttpError 500 Gemini.InternalError "server error")
  ]

showErrorTests :: TestTree
showErrorTests = testGroup "Show"
  [ testCase "Show JsonParseError is non-empty" $
      assertBool "Show should produce non-empty string"
        (not (null (show Gemini.JsonParseError)))

  , testCase "Show nested AllModelsFailed contains model name" $
      let err = Gemini.AllModelsFailed "testmodel" (Gemini.ExtractionError "detail")
      in assertBool "Show should contain model name"
           ("testmodel" `isInfixOf` show err)

  , testCase "Show HttpError contains ApiStatus constructor" $
      let err = Gemini.HttpError 429 Gemini.ResourceExhausted "message"
      in assertBool "Show should contain ResourceExhausted"
           ("ResourceExhausted" `isInfixOf` show err)

  , testCase "Show HttpError contains status code" $
      let err = Gemini.HttpError 429 Gemini.ResourceExhausted "message"
      in assertBool "Show should contain status code"
           ("429" `isInfixOf` show err)

  , testCase "Show HttpError contains message" $
      let err = Gemini.HttpError 429 Gemini.ResourceExhausted "rate limit exceeded"
      in assertBool "Show should contain message"
           ("rate limit exceeded" `isInfixOf` show err)
  ]

isRateLimitErrorTests :: TestTree
isRateLimitErrorTests = testGroup "isRateLimitError"
  [ testCase "HttpError with ResourceExhausted is rate limit" $
      Gemini.isRateLimitError (Gemini.HttpError 429 Gemini.ResourceExhausted "Too Many Requests")
        @?= True

  , testCase "HttpError 403 with ResourceExhausted is rate limit" $
      Gemini.isRateLimitError (Gemini.HttpError 403 Gemini.ResourceExhausted "quota exceeded")
        @?= True

  , testCase "HttpError 500 with InternalError is not rate limit" $
      Gemini.isRateLimitError (Gemini.HttpError 500 Gemini.InternalError "Internal Server Error")
        @?= False

  , testCase "HttpError 429 with UnknownStatus is not rate limit" $
      Gemini.isRateLimitError (Gemini.HttpError 429 (Gemini.UnknownStatus "WEIRD") "body")
        @?= False

  , testCase "JsonParseError is not rate limit" $
      Gemini.isRateLimitError Gemini.JsonParseError
        @?= False

  , testCase "ExtractionError is not rate limit" $
      Gemini.isRateLimitError (Gemini.ExtractionError "no text")
        @?= False

  , testCase "AllModelsFailed wrapping ResourceExhausted is rate limit" $
      Gemini.isRateLimitError
        (Gemini.AllModelsFailed "model" (Gemini.HttpError 429 Gemini.ResourceExhausted "limit"))
        @?= True

  , testCase "AllModelsFailed wrapping non-rate-limit is not rate limit" $
      Gemini.isRateLimitError (Gemini.AllModelsFailed "model" Gemini.JsonParseError)
        @?= False
  ]

isQuotaExhaustedErrorTests :: TestTree
isQuotaExhaustedErrorTests = testGroup "isQuotaExhaustedError"
  [ testCase "ResourceExhausted with daily message is quota exhausted" $
      Gemini.isQuotaExhaustedError
        (Gemini.HttpError 429 Gemini.ResourceExhausted "Quota exceeded: daily limit reached")
        @?= True

  , testCase "ResourceExhausted with per day message is quota exhausted" $
      Gemini.isQuotaExhaustedError
        (Gemini.HttpError 429 Gemini.ResourceExhausted "per day quota exceeded")
        @?= True

  , testCase "ResourceExhausted with PerDay message is quota exhausted" $
      Gemini.isQuotaExhaustedError
        (Gemini.HttpError 429 Gemini.ResourceExhausted "GenerateContent PerDay limit exceeded")
        @?= True

  , testCase "ResourceExhausted without daily indicator is not quota exhausted" $
      Gemini.isQuotaExhaustedError
        (Gemini.HttpError 429 Gemini.ResourceExhausted "rate limit exceeded")
        @?= False

  , testCase "InternalError is not quota exhausted" $
      Gemini.isQuotaExhaustedError (Gemini.HttpError 500 Gemini.InternalError "server error")
        @?= False

  , testCase "JsonParseError is not quota exhausted" $
      Gemini.isQuotaExhaustedError Gemini.JsonParseError
        @?= False

  , testCase "AllModelsFailed wrapping quota exhausted is quota exhausted" $
      Gemini.isQuotaExhaustedError
        (Gemini.AllModelsFailed "model"
          (Gemini.HttpError 429 Gemini.ResourceExhausted "daily quota exceeded"))
        @?= True
  ]

parseErrorBodyTests :: TestTree
parseErrorBodyTests = testGroup "parseErrorBody"
  [ testCase "parses structured Gemini error JSON" $
      let body = "{\"error\":{\"code\":429,\"status\":\"RESOURCE_EXHAUSTED\",\"message\":\"Rate limit exceeded\"}}"
          (status, message) = Gemini.parseErrorBody body
      in do
        status @?= Gemini.ResourceExhausted
        message @?= "Rate limit exceeded"

  , testCase "parses INVALID_ARGUMENT error" $
      let body = "{\"error\":{\"code\":400,\"status\":\"INVALID_ARGUMENT\",\"message\":\"Bad request\"}}"
          (status, message) = Gemini.parseErrorBody body
      in do
        status @?= Gemini.InvalidArgument
        message @?= "Bad request"

  , testCase "falls back to UnknownStatus for non-JSON" $
      let (status, _) = Gemini.parseErrorBody "not json"
      in case status of
        Gemini.UnknownStatus _ -> pure ()
        other -> assertBool ("expected UnknownStatus, got " <> show other) False

  , testCase "falls back to UnknownStatus for missing error field" $
      let (status, _) = Gemini.parseErrorBody "{\"other\":\"value\"}"
      in case status of
        Gemini.UnknownStatus _ -> pure ()
        other -> assertBool ("expected UnknownStatus, got " <> show other) False

  , testCase "falls back to UnknownStatus for missing status field" $
      let (status, _) = Gemini.parseErrorBody "{\"error\":{\"code\":500,\"message\":\"oops\"}}"
      in case status of
        Gemini.UnknownStatus _ -> pure ()
        other -> assertBool ("expected UnknownStatus, got " <> show other) False

  , testCase "extracts message when status is missing" $
      let (_, message) = Gemini.parseErrorBody "{\"error\":{\"code\":500,\"message\":\"server broke\"}}"
      in message @?= "server broke"
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

propertyTests :: TestTree
propertyTests = testGroup "properties"
  [ testProperty "show always produces non-empty string" $
      QC.forAll genError $ \err ->
        not (null (show err))

  , testProperty "HttpError with ResourceExhausted is always rate limited" $
      QC.forAll (T.pack <$> (QC.arbitrary :: QC.Gen String)) $ \message ->
        Gemini.isRateLimitError (Gemini.HttpError 429 Gemini.ResourceExhausted message)

  , testProperty "JsonParseError is never a rate limit error" $
      not (Gemini.isRateLimitError Gemini.JsonParseError)

  , testProperty "all known ApiStatus values round-trip through parseApiStatus" $
      QC.forAll genKnownStatus $ \(statusText, expected) ->
        Gemini.parseApiStatus statusText == expected
  ]

genError :: QC.Gen Gemini.Error
genError = QC.oneof
  [ pure Gemini.JsonParseError
  , Gemini.ExtractionError . T.pack <$> QC.listOf1 QC.arbitraryASCIIChar
  , Gemini.HttpError <$> QC.elements [400, 401, 403, 429, 500, 503] <*> genApiStatus <*> (T.pack <$> QC.arbitrary)
  , Gemini.AllModelsFailed . T.pack <$> QC.listOf1 QC.arbitraryASCIIChar <*> genLeafError
  ]

genLeafError :: QC.Gen Gemini.Error
genLeafError = QC.oneof
  [ pure Gemini.JsonParseError
  , Gemini.ExtractionError . T.pack <$> QC.listOf1 QC.arbitraryASCIIChar
  , Gemini.HttpError <$> QC.elements [400, 401, 403, 429, 500, 503] <*> genApiStatus <*> (T.pack <$> QC.arbitrary)
  ]

genApiStatus :: QC.Gen Gemini.ApiStatus
genApiStatus = QC.oneof
  [ pure Gemini.ResourceExhausted
  , pure Gemini.InvalidArgument
  , pure Gemini.PermissionDenied
  , pure Gemini.NotFound
  , pure Gemini.InternalError
  , pure Gemini.Unavailable
  , pure Gemini.DeadlineExceeded
  , pure Gemini.Unauthenticated
  , pure Gemini.FailedPrecondition
  , Gemini.UnknownStatus . T.pack <$> QC.listOf1 QC.arbitraryASCIIChar
  ]

genKnownStatus :: QC.Gen (T.Text, Gemini.ApiStatus)
genKnownStatus = QC.elements
  [ ("RESOURCE_EXHAUSTED", Gemini.ResourceExhausted)
  , ("INVALID_ARGUMENT", Gemini.InvalidArgument)
  , ("PERMISSION_DENIED", Gemini.PermissionDenied)
  , ("NOT_FOUND", Gemini.NotFound)
  , ("INTERNAL", Gemini.InternalError)
  , ("UNAVAILABLE", Gemini.Unavailable)
  , ("DEADLINE_EXCEEDED", Gemini.DeadlineExceeded)
  , ("UNAUTHENTICATED", Gemini.Unauthenticated)
  , ("FAILED_PRECONDITION", Gemini.FailedPrecondition)
  ]
