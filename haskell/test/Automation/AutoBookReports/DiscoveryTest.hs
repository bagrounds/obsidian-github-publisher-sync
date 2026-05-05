{-# LANGUAGE OverloadedStrings #-}

module Automation.AutoBookReports.DiscoveryTest (tests) where

import Test.Tasty
import Test.Tasty.HUnit

import Automation.AutoBookReports.Discovery

tests :: TestTree
tests = testGroup "AutoBookReports.Discovery"
  [ testGroup "isReflectionFile"
    [ testCase "accepts YYYY-MM-DD.md" $
        assertBool "should accept" (isReflectionFile "2026-05-05.md")
    , testCase "rejects non-date filenames" $
        assertBool "should reject" (not (isReflectionFile "index.md"))
    , testCase "rejects with wrong extension" $
        assertBool "should reject" (not (isReflectionFile "2026-05-05.txt"))
    , testCase "rejects shorter date" $
        assertBool "should reject" (not (isReflectionFile "2026-5-5.md"))
    , testCase "rejects extra suffix" $
        assertBool "should reject" (not (isReflectionFile "2026-05-05-extra.md"))
    ]

  , testGroup "filterRecentReflections"
    [ testCase "drops non-date entries" $
        filterRecentReflections (fmap show [(2020 :: Int) .. 2026]) @?= []
    , testCase "respects window size and ordering" $ do
        let window = recentReflectionWindow
            sample = [ "2026-04-30.md"
                     , "2026-05-01.md"
                     , "2026-05-02.md"
                     , "2026-05-03.md"
                     , "2026-05-04.md"
                     , "2026-05-05.md"
                     , "2026-04-29.md"
                     , "2026-04-28.md"
                     , "2026-04-27.md"
                     , "2026-04-26.md"
                     , "index.md"  -- ignored
                     ]
            result = filterRecentReflections sample
        assertBool "size is at most window" (length result <= window)
        assertBool "first is the latest by date" (take 1 result == ["2026-05-05.md"])
    ]

  , testGroup "knownBookSlug"
    [ testCase "extracts slug from .md file" $
        knownBookSlug "deep-work.md" @?= Just "deep-work"
    , testCase "rejects non-md files" $
        knownBookSlug "deep-work.txt" @?= Nothing
    ]

  , testGroup "extractReflectionBody"
    [ testCase "strips frontmatter" $
        extractReflectionBody "---\ntitle: foo\n---\n# heading\nbody"
          @?= "# heading\nbody"
    , testCase "leaves content alone when no frontmatter" $
        extractReflectionBody "# heading\nbody" @?= "# heading\nbody"
    ]
  ]
