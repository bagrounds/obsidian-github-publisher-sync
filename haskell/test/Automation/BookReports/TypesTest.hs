module Automation.BookReports.TypesTest (tests) where

import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))
import Test.Tasty.QuickCheck (testProperty)

import qualified Data.Text as T

import Automation.BookReports.Types
  ( AmazonVariant (..)
  , defaultVariantPriority
  , mkAsin
  , mkBookAuthor
  , mkBookSlug
  , mkBookTitle
  , slugFromTitle
  , unAsin
  , unBookSlug
  , unBookTitle
  , variantFromText
  , variantToText
  )

tests :: TestTree
tests = testGroup "BookReports.Types"
  [ testGroup "BookTitle smart constructor"
      [ testCase "rejects empty text" $
          mkBookTitle "" @?= Left "BookTitle must not be empty or whitespace"
      , testCase "rejects whitespace-only text" $
          mkBookTitle "   " @?= Left "BookTitle must not be empty or whitespace"
      , testCase "trims surrounding whitespace" $
          fmap unBookTitle (mkBookTitle "  Sapiens  ") @?= Right "Sapiens"
      ]
  , testGroup "BookAuthor smart constructor"
      [ testCase "rejects empty text" $
          mkBookAuthor "" @?= Left "BookAuthor must not be empty or whitespace"
      , testCase "accepts non-empty author" $
          fmap show (mkBookAuthor "Yuval Noah Harari") @?= Right "BookAuthor \"Yuval Noah Harari\""
      ]
  , testGroup "BookSlug smart constructor"
      [ testCase "rejects uppercase" $
          fmap unBookSlug (mkBookSlug "Foo") @?= Left "BookSlug must be lowercase ASCII alphanumeric or hyphen, got: Foo"
      , testCase "rejects spaces" $
          fmap unBookSlug (mkBookSlug "foo bar") @?= Left "BookSlug must be lowercase ASCII alphanumeric or hyphen, got: foo bar"
      , testCase "accepts lower-kebab" $
          fmap unBookSlug (mkBookSlug "foo-bar-123") @?= Right "foo-bar-123"
      ]
  , testGroup "slugFromTitle"
      [ testCase "kebab-cases simple titles" $
          unBookSlug (slugFromTitle (unsafeTitle "Sapiens: A Brief History")) @?= "sapiens-a-brief-history"
      , testCase "collapses runs of non-alphanumerics" $
          unBookSlug (slugFromTitle (unsafeTitle "  Foo --- Bar !!! Baz  ")) @?= "foo-bar-baz"
      , testProperty "result has no leading or trailing hyphens" $ \title ->
          let slug = unBookSlug (slugFromTitle (unsafeTitle (T.pack ("X" <> title <> "X"))))
          in not ("-" `T.isPrefixOf` slug) && not ("-" `T.isSuffixOf` slug)
      , testProperty "result never contains consecutive hyphens" $ \title ->
          let slug = unBookSlug (slugFromTitle (unsafeTitle (T.pack ("X" <> title <> "X"))))
          in not (T.isInfixOf "--" slug)
      ]
  , testGroup "Asin smart constructor"
      [ testCase "rejects too short" $
          fmap unAsin (mkAsin "ABC") @?= Left "ASIN must be 10 characters, got 3: ABC"
      , testCase "rejects too long" $
          fmap unAsin (mkAsin "ABCDEFGHIJKL") @?= Left "ASIN must be 10 characters, got 12: ABCDEFGHIJKL"
      , testCase "rejects non-alphanumeric" $
          fmap unAsin (mkAsin "ABCD!FGHIJ") @?= Left "ASIN must be ASCII alphanumeric: ABCD!FGHIJ"
      , testCase "uppercases lowercase" $
          fmap unAsin (mkAsin "0451524934") @?= Right "0451524934"
      , testCase "trims and uppercases" $
          fmap unAsin (mkAsin "  abcdefghij  ") @?= Right "ABCDEFGHIJ"
      ]
  , testGroup "AmazonVariant"
      [ testCase "round-trips known variants" $ do
          mapM_ (\v -> variantFromText (variantToText v) @?= Just v) [Hardcover, Paperback, Kindle, Audible]
      , testCase "accepts common synonyms" $ do
          variantFromText "audiobook"        @?= Just Audible
          variantFromText "Kindle Edition"   @?= Just Kindle
          variantFromText "softcover"        @?= Just Paperback
          variantFromText "hardback"         @?= Just Hardcover
      , testCase "rejects unknown" $
          variantFromText "vinyl" @?= Nothing
      , testCase "default priority order" $
          defaultVariantPriority @?= [Hardcover, Paperback, Kindle, Audible]
      ]
  ]
  where
    unsafeTitle raw = case mkBookTitle raw of
      Right t -> t
      Left  e -> error (T.unpack e)
