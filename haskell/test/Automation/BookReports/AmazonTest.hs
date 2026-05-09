module Automation.BookReports.AmazonTest (tests) where

import qualified Data.Text as T
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool, assertFailure)

import Automation.BookReports.Amazon
  ( buildAffiliateUrlFromAsin
  , buildAmazonResolutionPrompt
  , extractAsinFromUrl
  , mkAffiliateTag
  , parseAmazonResolutionResponse
  , unAffiliateTag
  , unAmazonAffiliateUrl
  )
import Automation.BookReports.Types
  ( AmazonResolution (..)
  , AmazonVariant (..)
  , defaultVariantPriority
  , mkAsin
  , mkBookTitle
  , unAsin
  )

tests :: TestTree
tests = testGroup "BookReports.Amazon"
  [ testGroup "AffiliateTag smart constructor"
      [ testCase "rejects empty" $
          mkAffiliateTag "" @?= Left "AffiliateTag must not be empty"
      , testCase "rejects spaces" $
          mkAffiliateTag "bad tag" @?= Left "AffiliateTag must be ASCII alphanumeric or hyphen: bad tag"
      , testCase "accepts standard form" $
          fmap unAffiliateTag (mkAffiliateTag "bagrounds-20") @?= Right "bagrounds-20"
      ]
  , testGroup "buildAffiliateUrlFromAsin"
      [ testCase "produces canonical /dp/<ASIN>?tag=<tag>" $ do
          tag <- expectRight (mkAffiliateTag "tag-20")
          asinValue <- expectRight (mkAsin "0451524934")
          unAmazonAffiliateUrl (buildAffiliateUrlFromAsin tag asinValue)
            @?= "https://www.amazon.com/dp/0451524934?tag=tag-20"
      ]
  , testGroup "extractAsinFromUrl"
      [ testCase "from /dp/ path" $
          fmap unAsin (extractAsinFromUrl "https://www.amazon.com/dp/0451524934") @?= Just "0451524934"
      , testCase "from /gp/product/ path" $
          fmap unAsin (extractAsinFromUrl "https://www.amazon.com/gp/product/B07XKJL2QY/ref=foo")
            @?= Just "B07XKJL2QY"
      , testCase "rejects URLs without ASIN segment" $
          extractAsinFromUrl "https://www.amazon.com/" @?= Nothing
      ]
  , testGroup "buildAmazonResolutionPrompt"
      [ testCase "mentions title" $ do
          title <- expectRight (mkBookTitle "Sapiens")
          let prompt = buildAmazonResolutionPrompt title defaultVariantPriority
          assertBool "prompt mentions title" (T.isInfixOf "Sapiens" prompt)
      , testCase "lists priority order" $ do
          title <- expectRight (mkBookTitle "Sapiens")
          let prompt = buildAmazonResolutionPrompt title defaultVariantPriority
          assertBool "prompt lists Hardcover > Paperback > Kindle > Audible"
            (T.isInfixOf "Hardcover > Paperback > Kindle > Audible" prompt)
      ]
  , testGroup "parseAmazonResolutionResponse"
      [ testCase "accepts valid JSON object" $ do
          let raw = "{\"found\":true,\"asin\":\"0451524934\",\"variant\":\"Paperback\",\"url\":\"https://www.amazon.com/dp/0451524934\"}"
          case parseAmazonResolutionResponse defaultVariantPriority raw of
            Right resolution -> do
              unAsin (resolvedAsin resolution) @?= "0451524934"
              resolvedVariant resolution @?= Paperback
            Left err -> assertFailure (T.unpack err)
      , testCase "strips ```json code fences" $ do
          let raw = "```json\n{\"found\":true,\"asin\":\"B07XKJL2QY\",\"variant\":\"Kindle\",\"url\":\"https://www.amazon.com/dp/B07XKJL2QY\"}\n```"
          case parseAmazonResolutionResponse defaultVariantPriority raw of
            Right resolution -> resolvedVariant resolution @?= Kindle
            Left err -> assertFailure (T.unpack err)
      , testCase "rejects found:false" $ do
          let raw = "{\"found\":false}"
          case parseAmazonResolutionResponse defaultVariantPriority raw of
            Right _ -> assertFailure "should have rejected"
            Left err -> assertBool "mentions found" (T.isInfixOf "found" err)
      , testCase "rejects unrecognised variant" $ do
          let raw = "{\"found\":true,\"asin\":\"0451524934\",\"variant\":\"Vinyl\",\"url\":\"x\"}"
          case parseAmazonResolutionResponse defaultVariantPriority raw of
            Right _   -> assertFailure "should have rejected"
            Left err  -> assertBool "mentions variant" (T.isInfixOf "Vinyl" err)
      , testCase "rejects ASIN failing format check" $ do
          let raw = "{\"found\":true,\"asin\":\"NOTASIN\",\"variant\":\"Paperback\",\"url\":\"x\"}"
          case parseAmazonResolutionResponse defaultVariantPriority raw of
            Right _  -> assertFailure "should have rejected"
            Left err -> assertBool "mentions ASIN" (T.isInfixOf "ASIN" err)
      ]
  ]
  where
    expectRight (Right v) = pure v
    expectRight (Left e)  = assertFailure (T.unpack e) >> error "unreachable"
