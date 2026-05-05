{-# LANGUAGE OverloadedStrings #-}

module Automation.AutoBookReports.AmazonLinkTest (tests) where

import qualified Data.Text as T
import Test.Tasty
import Test.Tasty.HUnit

import Automation.AutoBookReports.AmazonLink

tests :: TestTree
tests = testGroup "AutoBookReports.AmazonLink"
  [ testGroup "defaultVariantPriority"
    [ testCase "starts with Hardcover" $
        take 1 defaultVariantPriority @?= [Hardcover]
    , testCase "covers all variants exactly once" $ do
        length defaultVariantPriority @?= 4
        let vs = [minBound .. maxBound :: AmazonVariant]
        assertBool "all present" (all (`elem` defaultVariantPriority) vs)
    ]

  , testGroup "variantToText / variantFromText"
    [ testCase "round-trip for all variants" $
        mapM_ (\v -> variantFromText (variantToText v) @?= Just v)
              [minBound .. maxBound :: AmazonVariant]
    , testCase "tolerates synonyms" $ do
        variantFromText "audiobook" @?= Just Audible
        variantFromText "Hardback" @?= Just Hardcover
        variantFromText "  Kindle Edition  " @?= Just Kindle
    , testCase "rejects unknown" $
        variantFromText "Brain Implant" @?= Nothing
    ]

  , testGroup "isValidAsin"
    [ testCase "accepts a 10-char alphanumeric ASIN" $
        assertBool "valid" (isValidAsin "B08L5W3W7Y")
    , testCase "rejects too short" $
        assertBool "invalid" (not (isValidAsin "B08L5W3"))
    , testCase "rejects too long" $
        assertBool "invalid" (not (isValidAsin "B08L5W3W7Y0"))
    , testCase "rejects non-ASCII" $
        assertBool "invalid" (not (isValidAsin "B08L5W3W7Ÿ"))
    , testCase "rejects punctuation" $
        assertBool "invalid" (not (isValidAsin "B08L5W3-7Y"))
    ]

  , testGroup "formatAffiliateUrl"
    [ testCase "constructs canonical URL" $
        formatAffiliateUrl "B08L5W3W7Y" "test-tag-20"
          @?= "https://www.amazon.com/dp/B08L5W3W7Y?tag=test-tag-20"
    , testCase "uppercases ASIN" $
        formatAffiliateUrl "b08l5w3w7y" "tag"
          @?= "https://www.amazon.com/dp/B08L5W3W7Y?tag=tag"
    ]

  , testGroup "buildLookupPrompt"
    [ testCase "embeds title and author" $ do
        let (_, user) = buildLookupPrompt "Foo" "Bar" defaultVariantPriority
        assertBool "title" (T.isInfixOf "Foo" user)
        assertBool "author" (T.isInfixOf "Bar" user)
    , testCase "embeds priority list in system" $ do
        let (sys, _) = buildLookupPrompt "Foo" "Bar" defaultVariantPriority
        assertBool "Hardcover" (T.isInfixOf "Hardcover" sys)
        assertBool "Audible" (T.isInfixOf "Audible" sys)
    , testCase "instructs JSON-only response" $ do
        let (sys, _) = buildLookupPrompt "Foo" "Bar" defaultVariantPriority
        assertBool "json" (T.isInfixOf "JSON" sys)
    ]

  , testGroup "parseLookupResponse"
    [ testCase "parses found ASIN+variant" $
        parseLookupResponse "{\"found\":true,\"asin\":\"B08L5W3W7Y\",\"variant\":\"Hardcover\"}"
          @?= Right (AmazonResolution "B08L5W3W7Y" Hardcover)

    , testCase "parses code-fenced response" $
        parseLookupResponse "```json\n{\"found\":true,\"asin\":\"B08L5W3W7Y\",\"variant\":\"Kindle\"}\n```"
          @?= Right (AmazonResolution "B08L5W3W7Y" Kindle)

    , testCase "uppercases lower-case ASIN" $
        case parseLookupResponse "{\"found\":true,\"asin\":\"b08l5w3w7y\",\"variant\":\"Hardcover\"}" of
          Right r -> resolvedAsin r @?= "B08L5W3W7Y"
          Left e  -> assertFailure (T.unpack e)

    , testCase "rejects when found is false" $
        case parseLookupResponse "{\"found\":false}" of
          Left _ -> pure ()
          Right r -> assertFailure ("expected Left, got " <> show r)

    , testCase "rejects invalid ASIN" $
        case parseLookupResponse "{\"found\":true,\"asin\":\"too-short\",\"variant\":\"Hardcover\"}" of
          Left _ -> pure ()
          Right r -> assertFailure ("expected Left, got " <> show r)

    , testCase "rejects unknown variant" $
        case parseLookupResponse "{\"found\":true,\"asin\":\"B08L5W3W7Y\",\"variant\":\"NeuralLink\"}" of
          Left _ -> pure ()
          Right r -> assertFailure ("expected Left, got " <> show r)

    , testCase "rejects gibberish" $
        case parseLookupResponse "not even close" of
          Left _ -> pure ()
          Right r -> assertFailure ("expected Left, got " <> show r)
    ]
  ]
