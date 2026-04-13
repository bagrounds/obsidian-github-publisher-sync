module Automation.BlogImage.EligibilityTest (tests) where

import Data.Maybe (isNothing)
import qualified Data.Text as T
import Data.Time (fromGregorian)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import Test.Tasty.QuickCheck (testProperty, forAll, listOf1, elements)

import Automation.BlogImage.ContentDirectory (ContentDirectory (..))
import Automation.BlogImage.Eligibility

tests :: TestTree
tests = testGroup "BlogImage.Eligibility"
  [ testGroup "hasEmbeddedImage"
      [ testCase "detects Obsidian image embed" $
          hasEmbeddedImage "some text\n![[attachments/photo.jpg]]\nmore" @?= True
      , testCase "detects Obsidian embed without attachments prefix" $
          hasEmbeddedImage "![[my-image.png]]" @?= True
      , testCase "detects markdown image embed" $
          hasEmbeddedImage "![alt text](images/photo.webp)" @?= True
      , testCase "returns False for plain text" $
          hasEmbeddedImage "no images here" @?= False
      , testCase "returns False for non-image embed" $
          hasEmbeddedImage "![[some-note]]" @?= False
      , testCase "detects all image extensions" $ do
          assertBool "jpg" $ hasEmbeddedImage "![[photo.jpg]]"
          assertBool "jpeg" $ hasEmbeddedImage "![[photo.jpeg]]"
          assertBool "png" $ hasEmbeddedImage "![[photo.png]]"
          assertBool "gif" $ hasEmbeddedImage "![[photo.gif]]"
          assertBool "webp" $ hasEmbeddedImage "![[photo.webp]]"
      ]
  , testGroup "shouldRegenerateImage"
      [ testCase "returns True when regenerate_image is true" $
          shouldRegenerateImage "---\nregenerate_image: true\n---\nbody" @?= True
      , testCase "returns False when field is absent" $
          shouldRegenerateImage "---\ntitle: hello\n---\nbody" @?= False
      , testCase "returns False for no frontmatter" $
          shouldRegenerateImage "just body text" @?= False
      , testCase "case insensitive" $
          shouldRegenerateImage "---\nregenerate_image: TRUE\n---\nbody" @?= True
      , testCase "accepts yes" $
          shouldRegenerateImage "---\nregenerate_image: yes\n---\nbody" @?= True
      ]
  , testGroup "shouldHaveImage"
      [ testCase "accepts markdown file" $
          shouldHaveImage "my-post.md" @?= True
      , testCase "rejects index.md" $
          shouldHaveImage "index.md" @?= False
      , testCase "rejects AGENTS.md" $
          shouldHaveImage "AGENTS.md" @?= False
      , testCase "rejects IDEAS.md" $
          shouldHaveImage "IDEAS.md" @?= False
      , testCase "rejects non-markdown" $
          shouldHaveImage "photo.jpg" @?= False
      , testCase "rejects empty string" $
          shouldHaveImage "" @?= False
      ]
  , testGroup "isPostFile"
      [ testCase "accepts dated markdown file" $
          isPostFile "2024-01-15-my-post.md" @?= True
      , testCase "rejects non-dated file" $
          isPostFile "my-post.md" @?= False
      , testCase "rejects excluded files" $
          isPostFile "index.md" @?= False
      ]
  , testGroup "hasDatePrefix"
      [ testCase "valid date prefix" $
          hasDatePrefix "2024-01-15-my-post.md" @?= True
      , testCase "date-only" $
          hasDatePrefix "2024-01-15" @?= True
      , testCase "too short" $
          hasDatePrefix "abc" @?= False
      , testCase "non-digit year" $
          hasDatePrefix "abcd-01-15" @?= False
      ]
  , testGroup "parseDateFromFilename"
      [ testCase "parses date from standard filename" $
          parseDateFromFilename "2026-04-08-my-post.md" @?= Just (fromGregorian 2026 4 8)
      , testCase "parses date from date-only filename" $
          parseDateFromFilename "2025-01-15.md" @?= Just (fromGregorian 2025 1 15)
      , testCase "returns Nothing for non-date filename" $
          parseDateFromFilename "readme.md" @?= Nothing
      , testCase "returns Nothing for short filename" $
          parseDateFromFilename "abc" @?= Nothing
      ]
  , testGroup "isDateOnlyTitle"
      [ testCase "returns True when title matches date" $
          isDateOnlyTitle "---\ntitle: 2026-04-04\n---\nbody" (fromGregorian 2026 4 4) @?= True
      , testCase "returns False for creative title" $
          isDateOnlyTitle "---\ntitle: My Post\n---\nbody" (fromGregorian 2026 4 4) @?= False
      , testCase "returns False when dates do not match" $
          isDateOnlyTitle "---\ntitle: 2026-04-03\n---\nbody" (fromGregorian 2026 4 4) @?= False
      ]
  , testGroup "checkCandidateEligibility"
      [ testCase "eligible file without image returns Eligible False" $
          checkCandidateEligibility Books (fromGregorian 2026 4 8) "2026-04-01-post.md"
            "---\ntitle: My Post\n---\nSome content"
            @?= Eligible False
      , testCase "file with embedded image returns Ineligible AlreadyHasImage" $
          checkCandidateEligibility Books (fromGregorian 2026 4 8) "2026-04-01-post.md"
            "---\ntitle: My Post\n---\n![[attachments/photo.jpg]]\ncontent"
            @?= Ineligible AlreadyHasImage
      , testCase "future reflection returns Ineligible FutureReflection" $
          checkCandidateEligibility Reflections (fromGregorian 2026 4 8) "2026-04-09.md"
            "---\ntitle: Future\n---\nbody"
            @?= Ineligible FutureReflection
      , testCase "untitled reflection returns Ineligible UntitledReflection" $
          checkCandidateEligibility Reflections (fromGregorian 2026 4 8) "2026-04-07.md"
            "---\ntitle: \"2026-04-07\"\n---\n# 2026-04-07\nbody"
            @?= Ineligible UntitledReflection
      , testCase "eligible file needing regeneration returns Eligible True" $
          checkCandidateEligibility Books (fromGregorian 2026 4 8) "2026-04-01-post.md"
            "---\ntitle: My Post\nregenerate_image: true\n---\n![[attachments/old.jpg]]\ncontent"
            @?= Eligible True
      ]
  , testGroup "properties"
      [ testProperty "hasEmbeddedImage returns False for alphanumeric text" $
          forAll (fmap T.pack $ listOf1 $ elements (['a'..'z'] <> ['0'..'9'] <> [' ', '\n'])) $
            \t -> not (hasEmbeddedImage t)
      , testProperty "parseDateFromFilename returns Nothing for text shorter than 10 chars" $
          \s -> let t = T.pack (take 9 s)
                in (T.length t < 10) ==> isNothing (parseDateFromFilename t)
      ]
  ]
  where
    (==>) :: Bool -> Bool -> Bool
    (==>) False _ = True
    (==>) True  b = b
