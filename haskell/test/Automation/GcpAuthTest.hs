module Automation.GcpAuthTest (tests) where

import qualified Data.Text as T
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)

import Automation.GcpAuth

tests :: TestTree
tests = testGroup "GcpAuth"
  [ parseServiceAccountKeyTests
  , parseRSAPrivateKeyTests
  , scopeTests
  ]

parseServiceAccountKeyTests :: TestTree
parseServiceAccountKeyTests = testGroup "parseServiceAccountKey"
  [ testCase "parses valid JSON" $
      let json = "{\"project_id\":\"my-project\",\"client_email\":\"test@test.iam.gserviceaccount.com\",\"private_key\":\"-----BEGIN PRIVATE KEY-----\\nfake\\n-----END PRIVATE KEY-----\"}"
      in case parseServiceAccountKey json of
        Right key -> do
          projectId key @?= "my-project"
          clientEmail key @?= "test@test.iam.gserviceaccount.com"
        Left err -> error ("Parse failed: " <> T.unpack err)
  , testCase "rejects empty project_id" $
      let json = "{\"project_id\":\"\",\"client_email\":\"test@test.iam.gserviceaccount.com\",\"private_key\":\"key\"}"
      in case parseServiceAccountKey json of
        Left err -> assertBool "contains project_id" (T.isInfixOf "project_id" err)
        Right _ -> error "Should have failed"
  , testCase "rejects missing fields" $
      case parseServiceAccountKey "{}" of
        Left _ -> pure ()
        Right _ -> error "Should have failed"
  ]

parseRSAPrivateKeyTests :: TestTree
parseRSAPrivateKeyTests = testGroup "parseRSAPrivateKey"
  [ testCase "fails on empty text" $
      case parseRSAPrivateKey "" of
        Left _ -> pure ()
        Right _ -> error "Should have failed on empty input"
  , testCase "fails on invalid PEM" $
      case parseRSAPrivateKey "not a real key" of
        Left err -> assertBool "contains error info" (not (T.null err))
        Right _ -> error "Should have failed on invalid PEM"
  , testCase "fails on truncated base64" $
      let badPem = "-----BEGIN PRIVATE KEY-----\nnotvalidbase64!\n-----END PRIVATE KEY-----"
      in case parseRSAPrivateKey badPem of
        Left _ -> pure ()
        Right _ -> error "Should have failed on bad base64"
  , testCase "parses a well-formed PKCS#8 RSA key" $
      case parseRSAPrivateKey testPkcs8Key of
        Right _ -> pure ()
        Left err -> error ("Failed to parse test key: " <> T.unpack err)
  ]

scopeTests :: TestTree
scopeTests = testGroup "scopes"
  [ testCase "cloudPlatformScope is correct" $
      cloudPlatformScope @?= "https://www.googleapis.com/auth/cloud-platform"
  ]

testPkcs8Key :: T.Text
testPkcs8Key = T.intercalate "\n"
  [ "-----BEGIN PRIVATE KEY-----"
  , "MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQDwzj23iOgjvg5I"
  , "fawVmq27IgOVLSiZ8ues+cLjzOjPRvfjO3lKMkmZGW9lk/NF6gVHjcyZoNwx2F6f"
  , "ySdvA5Ujs+V91X1d9IyNlK2LKvFXKB2q8piJL0+O70MNuyLVh0xjaPA5LGdGty/W"
  , "7UIyvGBMhAOKxmjUDnLnIgzEBN00Pxo/aPH4yDg7h+X6jivuh2CyoupvF5bNHLlj"
  , "2eTGll5mLSbaImXWMgK+JF6DDOZlcj9bj6Zn5W0kzLaiN9FAweeL19WEvIBW4w8i"
  , "FUGak51V+mcjzhvzjEe+vfsmHlIUtqML9raqJRrqdbjpoipqlBpPYYvMc9K4BNJA"
  , "xgD9NuthAgMBAAECggEADcQUhiH291gdk+pPRJrnlJuQrd37hLV8pghPKluj8XmC"
  , "oURcni+6wlxQYHOxRA1pSNpj2GJ4RAc0/Zhvvypqw7Q8idGDDbR1toBJ3XtSeaOK"
  , "8qNUsf744thtsmLAzokiBkrQ9MvDiajePMCqeKEJNkaTt0K5amn7CpiJN0l55csb"
  , "Tz197dJFsFHTAgkmxOfRn4icf2DPoeyssNUybsLLftjTR1v+2VdkCsEQ5neLaHzy"
  , "czIkQQCx3XN31sgvtrqBY8Or4zEmDEKONFJIF/d0neZPIki2TQ68sUKUtJIMZ46f"
  , "Fmp5I5/m/C9zXrm3RpZGb1rq5ardOznfEgOj/P9k6wKBgQD5M90EJt5LvZwV3rsx"
  , "0o9T5cb2AKJStPdvpCvI/SjV5epDiGk79LV5TSZNQ3XZ6Z2hodUxVYeil12Y/crx"
  , "D2os8CwPFaie+vvssqYW/oZ0g4p0BBlV/DEgLaE/wWLzQrzBn9Wu0xU/xUJhodPM"
  , "tvfV1xJ5qEBQAmBpjWatjAF8zwKBgQD3X75G5sZkKpdeR5zw4XjZ1fcdMPlHmOS1"
  , "O2Zpab/sFTvgIRZi4SmgODyURQ9r3utolryltpFjxgXmuMB6dFwgz98L+C4jEKE8"
  , "Is1339TztHq+Xct8xBJMFvPw64fRGH3IV7GuskNepCmz2zBizkF9LOHT0Xgnyisi"
  , "6LCa1o0AzwKBgQDIfD4imfabbrcFLUTix2iB8clInqf47BhpG+YR9AIHW8pFfJhV"
  , "IQFiznuzC0PkBbvIjn8LCqltWGN3sy6zE1izQKHhnOYkyP0mp29R7oFTeYRI5AdS"
  , "Euue3LbuqPGnjZh4GdP6q11cCaHnFB9mggkPY9E8SO08sTzJjnX9xzZnJwKBgF9V"
  , "lbYrcB/gTi+2d6RZsMJ69F5apmdSZCn4N3K+n4lzcXziI4d98RXfNnGJ3/SZl63a"
  , "Ed/naUbDZTjS0NMgjvTSR8qMHfPDj+/mFbtyFtbJIljFOwvdYJPUcLTTgKczwh34"
  , "tfB2oQITUEMRYSdjB9ge+PUyEBV9k3xDovQ5ZWP/AoGAB7X93fIZ/g5rUhkPuHh6"
  , "TFIIcWyW3FrX9ooha3aXo07YtUgcYJayh06VyZ+dTwgOlVr77DQ/D1EBdpLEqkAM"
  , "MGKK+fGTAjVDYbKIPern0kbABkjbz1nhCdHcaa8+23vZattCe9bW86reNHyOLTWy"
  , "5Ps5rCsNqPOJ4QDDvLobDTg="
  , "-----END PRIVATE KEY-----"
  ]
