module Automation.JsonTest (tests) where

import qualified Data.ByteString.Lazy as LBS
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Lazy as TL
import qualified Data.Text.Lazy.Encoding as TLE
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import Test.Tasty.QuickCheck (testProperty)
import qualified Test.Tasty.QuickCheck as QC

import Automation.Json

tests :: TestTree
tests = testGroup "Json"
  [ encodeTextTests
  , encodeTests
  , decodeTests
  , eitherDecodeTests
  , objectTests
  , fieldAccessTests
  , optionalFieldTests
  , withObjectTests
  , parseMaybeTests
  , roundTripTests
  , propertyTests
  ]

--------------------------------------------------------------------------------
-- encodeText
--------------------------------------------------------------------------------

encodeTextTests :: TestTree
encodeTextTests = testGroup "encodeText"
  [ testCase "encodes null" $
      encodeText Null @?= "null"
  , testCase "encodes true" $
      encodeText (Bool True) @?= "true"
  , testCase "encodes false" $
      encodeText (Bool False) @?= "false"
  , testCase "encodes integer number" $
      encodeText (Number 42) @?= "42"
  , testCase "encodes negative integer" $
      encodeText (Number (-3)) @?= "-3"
  , testCase "encodes fractional number" $
      assertBool "contains decimal" (T.isInfixOf "." (encodeText (Number 3.14)))
  , testCase "encodes NaN as null" $
      encodeText (Number (0/0)) @?= "null"
  , testCase "encodes Infinity as null" $
      encodeText (Number (1/0)) @?= "null"
  , testCase "encodes string" $
      encodeText (String "hello") @?= "\"hello\""
  , testCase "encodes string with special chars" $
      assertBool "escapes newline" (T.isInfixOf "\\n" (encodeText (String "a\nb")))
  , testCase "encodes empty array" $
      encodeText (Array []) @?= "[]"
  , testCase "encodes array with values" $
      encodeText (Array [Number 1, Number 2]) @?= "[1,2]"
  , testCase "encodes empty object" $
      encodeText (Object []) @?= "{}"
  , testCase "encodes object with fields" $
      let result = encodeText (Object [("key", String "val")])
      in result @?= "{\"key\":\"val\"}"
  , testCase "encodes nested structure" $
      let val = Object [("arr", Array [Number 1, Bool True, Null])]
          result = encodeText val
      in assertBool "contains arr" (T.isInfixOf "\"arr\"" result)
  ]

--------------------------------------------------------------------------------
-- encode (ByteString)
--------------------------------------------------------------------------------

encodeTests :: TestTree
encodeTests = testGroup "encode"
  [ testCase "encode produces valid UTF-8 ByteString" $
      let bs = encode (String "hello")
          txt = TL.toStrict $ TLE.decodeUtf8 bs
      in txt @?= "\"hello\""
  , testCase "encode null" $
      let bs = encode Null
          txt = TL.toStrict $ TLE.decodeUtf8 bs
      in txt @?= "null"
  ]

--------------------------------------------------------------------------------
-- decode
--------------------------------------------------------------------------------

decodeTests :: TestTree
decodeTests = testGroup "decode"
  [ testCase "decodes string" $
      let result = decode (jsonBytes "\"hello\"") :: Maybe Value
      in result @?= Just (String "hello")
  , testCase "decodes number" $
      let result = decode (jsonBytes "42") :: Maybe Value
      in result @?= Just (Number 42)
  , testCase "decodes true" $
      let result = decode (jsonBytes "true") :: Maybe Value
      in result @?= Just (Bool True)
  , testCase "decodes false" $
      let result = decode (jsonBytes "false") :: Maybe Value
      in result @?= Just (Bool False)
  , testCase "decodes null" $
      let result = decode (jsonBytes "null") :: Maybe Value
      in result @?= Just Null
  , testCase "decodes array" $
      let result = decode (jsonBytes "[1, 2, 3]") :: Maybe Value
      in result @?= Just (Array [Number 1, Number 2, Number 3])
  , testCase "decodes object" $
      let result = decode (jsonBytes "{\"key\": \"val\"}") :: Maybe Value
      in result @?= Just (Object [("key", String "val")])
  , testCase "decodes empty object" $
      let result = decode (jsonBytes "{}") :: Maybe Value
      in result @?= Just (Object [])
  , testCase "decodes empty array" $
      let result = decode (jsonBytes "[]") :: Maybe Value
      in result @?= Just (Array [])
  , testCase "returns Nothing for invalid JSON" $
      let result = decode (jsonBytes "not json") :: Maybe Value
      in result @?= Nothing
  , testCase "decodes nested object" $
      let result = decode (jsonBytes "{\"a\": {\"b\": 1}}") :: Maybe Value
      in result @?= Just (Object [("a", Object [("b", Number 1)])])
  , testCase "decodes negative number" $
      let result = decode (jsonBytes "-5") :: Maybe Value
      in result @?= Just (Number (-5))
  , testCase "decodes fractional number" $
      let result = decode (jsonBytes "3.14") :: Maybe Value
      in case result of
        Just (Number d) -> assertBool "close to 3.14" (abs (d - 3.14) < 0.001)
        _               -> assertBool "should decode number" False
  , testCase "decodes Text from string" $
      let result = decode (jsonBytes "\"world\"") :: Maybe Text
      in result @?= Just "world"
  , testCase "decodes Int from number" $
      let result = decode (jsonBytes "99") :: Maybe Int
      in result @?= Just 99
  , testCase "decodes Bool from true" $
      let result = decode (jsonBytes "true") :: Maybe Bool
      in result @?= Just True
  , testCase "decodes list of Int" $
      let result = decode (jsonBytes "[1, 2, 3]") :: Maybe [Int]
      in result @?= Just [1, 2, 3]
  ]

--------------------------------------------------------------------------------
-- eitherDecode
--------------------------------------------------------------------------------

eitherDecodeTests :: TestTree
eitherDecodeTests = testGroup "eitherDecode"
  [ testCase "Right for valid JSON" $
      let result = eitherDecode (jsonBytes "\"ok\"") :: Either String Value
      in result @?= Right (String "ok")
  , testCase "Left for invalid JSON" $
      let result = eitherDecode (jsonBytes "bad") :: Either String Value
      in case result of
        Left _  -> pure ()
        Right _ -> assertBool "should be Left" False
  , testCase "Left for type mismatch" $
      let result = eitherDecode (jsonBytes "42") :: Either String Text
      in case result of
        Left _  -> pure ()
        Right _ -> assertBool "should be Left for type mismatch" False
  ]

--------------------------------------------------------------------------------
-- object and .=
--------------------------------------------------------------------------------

objectTests :: TestTree
objectTests = testGroup "object and .="
  [ testCase "builds object with .=" $
      let val = object ["name" .= ("Alice" :: Text), "age" .= (30 :: Int)]
      in case val of
        Object pairs -> do
          lookup "name" pairs @?= Just (String "Alice")
          lookup "age" pairs @?= Just (Number 30)
        _ -> assertBool "should be Object" False
  , testCase "builds empty object" $
      object [] @?= Object []
  , testCase ".= converts Bool" $
      snd ("key" .= True) @?= Bool True
  , testCase ".= converts Maybe to Null" $
      snd ("key" .= (Nothing :: Maybe Text)) @?= Null
  , testCase ".= converts Just value" $
      snd ("key" .= (Just "hi" :: Maybe Text)) @?= String "hi"
  , testCase ".= converts list" $
      snd ("key" .= ([1, 2] :: [Int])) @?= Array [Number 1, Number 2]
  ]

--------------------------------------------------------------------------------
-- .: (required field)
--------------------------------------------------------------------------------

fieldAccessTests :: TestTree
fieldAccessTests = testGroup ".:"
  [ testCase "extracts Text field" $
      let pairs = [("name", String "Bob")]
      in (pairs .: "name" :: Either String Text) @?= Right "Bob"
  , testCase "extracts Int field" $
      let pairs = [("count", Number 5)]
      in (pairs .: "count" :: Either String Int) @?= Right 5
  , testCase "returns Left for missing key" $
      let pairs = [("name", String "Bob")]
      in case (pairs .: "missing" :: Either String Text) of
        Left _  -> pure ()
        Right _ -> assertBool "should be Left" False
  , testCase "returns Left for type mismatch" $
      let pairs = [("name", Number 42)]
      in case (pairs .: "name" :: Either String Text) of
        Left _  -> pure ()
        Right _ -> assertBool "should be Left for type mismatch" False
  ]

--------------------------------------------------------------------------------
-- .:? (optional field)
--------------------------------------------------------------------------------

optionalFieldTests :: TestTree
optionalFieldTests = testGroup ".:?"
  [ testCase "returns Just for present field" $
      let pairs = [("name", String "Alice")]
      in (pairs .:? "name" :: Either String (Maybe Text)) @?= Right (Just "Alice")
  , testCase "returns Nothing for missing key" $
      let pairs = [("name", String "Alice")]
      in (pairs .:? "other" :: Either String (Maybe Text)) @?= Right Nothing
  , testCase "returns Nothing for Null value" $
      let pairs = [("name", Null)]
      in (pairs .:? "name" :: Either String (Maybe Text)) @?= Right Nothing
  ]

--------------------------------------------------------------------------------
-- withObject
--------------------------------------------------------------------------------

withObjectTests :: TestTree
withObjectTests = testGroup "withObject"
  [ testCase "succeeds for Object value" $
      let result = withObject "test" (.: "x") (Object [("x", Number 1)]) :: Either String Int
      in result @?= Right 1
  , testCase "fails for non-Object value" $
      let result = withObject "test" (\_ -> Right (42 :: Int)) (String "oops")
      in case result of
        Left msg -> assertBool "mentions test" (T.isInfixOf "test" (T.pack msg))
        Right _  -> assertBool "should be Left" False
  , testCase "fails for Array" $
      let result = withObject "arr" (\_ -> Right (0 :: Int)) (Array [])
      in case result of
        Left _ -> pure ()
        Right _ -> assertBool "should be Left for Array" False
  , testCase "fails for Null" $
      let result = withObject "n" (\_ -> Right (0 :: Int)) Null
      in case result of
        Left _ -> pure ()
        Right _ -> assertBool "should be Left for Null" False
  ]

--------------------------------------------------------------------------------
-- parseMaybe
--------------------------------------------------------------------------------

parseMaybeTests :: TestTree
parseMaybeTests = testGroup "parseMaybe"
  [ testCase "returns Just on success" $
      parseMaybe fromValue (String "ok") @?= (Just "ok" :: Maybe Text)
  , testCase "returns Nothing on failure" $
      parseMaybe (\v -> fromValue v :: Either String Text) (Number 42) @?= Nothing
  ]

--------------------------------------------------------------------------------
-- round-trip tests
--------------------------------------------------------------------------------

roundTripTests :: TestTree
roundTripTests = testGroup "round-trip"
  [ testCase "string round-trip" $
      roundTrip (String "hello world") @?= Right (String "hello world")
  , testCase "number round-trip" $
      roundTrip (Number 42) @?= Right (Number 42)
  , testCase "bool round-trip" $
      roundTrip (Bool True) @?= Right (Bool True)
  , testCase "null round-trip" $
      roundTrip Null @?= Right Null
  , testCase "array round-trip" $
      roundTrip (Array [Number 1, String "two"]) @?= Right (Array [Number 1, String "two"])
  , testCase "object round-trip" $
      roundTrip (Object [("k", String "v")]) @?= Right (Object [("k", String "v")])
  , testCase "nested structure round-trip" $
      let val = Object [("list", Array [Number 1, Bool False, Null])]
      in roundTrip val @?= Right val
  , testCase "string with escapes round-trip" $
      roundTrip (String "line1\nline2\ttab") @?= Right (String "line1\nline2\ttab")
  , testCase "empty string round-trip" $
      roundTrip (String "") @?= Right (String "")
  , testCase "empty object round-trip" $
      roundTrip (Object []) @?= Right (Object [])
  , testCase "empty array round-trip" $
      roundTrip (Array []) @?= Right (Array [])
  ]

--------------------------------------------------------------------------------
-- property tests
--------------------------------------------------------------------------------

propertyTests :: TestTree
propertyTests = testGroup "properties"
  [ testProperty "string Value round-trips" $
      \(QC.ASCIIString s) ->
        let val = String (T.pack s)
        in roundTrip val == Right val
  , testProperty "integer Value round-trips" $
      \(n :: Int) ->
        let val = Number (fromIntegral n)
        in roundTrip val == Right val
  , testProperty "bool Value round-trips" $
      \(b :: Bool) ->
        roundTrip (Bool b) == Right (Bool b)
  , testProperty "encodeText of String always starts with quote" $
      \(QC.ASCIIString s) ->
        T.isPrefixOf "\"" (encodeText (String (T.pack s)))
  , testProperty ".= then .: round-trips for Text" $
      \(QC.ASCIIString s) ->
        let txt = T.pack s
            pairs = ["k" .= txt]
        in (pairs .: "k" :: Either String Text) == Right txt
  , testProperty ".:? returns Right Nothing for missing key" $
      \(QC.ASCIIString k) ->
        let pairs = [("__reserved__", String "val")]
            key = T.pack k
        in (T.null key || key == "__reserved__")
          || ((pairs .:? key :: Either String (Maybe Text)) == Right Nothing)
  ]

--------------------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------------------

jsonBytes :: Text -> LBS.ByteString
jsonBytes = TLE.encodeUtf8 . TL.fromStrict

roundTrip :: Value -> Either String Value
roundTrip = eitherDecode . encode
