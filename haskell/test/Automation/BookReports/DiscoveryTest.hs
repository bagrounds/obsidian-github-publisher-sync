module Automation.BookReports.DiscoveryTest (tests) where

import qualified Data.Set as Set
import qualified Data.Text as T
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)

import Automation.BookReports.Discovery
  ( BookCandidate (..)
  , extractBookCandidatesFromReflection
  , isReflectionFileName
  )
import Automation.BookReports.Types (mkBookSlug, unBookSlug, unBookTitle)

tests :: TestTree
tests = testGroup "BookReports.Discovery"
  [ testGroup "isReflectionFileName"
      [ testCase "accepts YYYY-MM-DD.md base"  $ assertBool "" (isReflectionFileName "2026-05-05.md")
      , testCase "accepts plain YYYY-MM-DD"     $ assertBool "" (isReflectionFileName "2026-05-05")
      , testCase "rejects index"                $ isReflectionFileName "index.md"          @?= False
      , testCase "rejects wrong shape"          $ isReflectionFileName "2026-5-5.md"        @?= False
      , testCase "rejects wrong length"         $ isReflectionFileName "2026-05.md"         @?= False
      ]
  , testGroup "extractBookCandidatesFromReflection — markdown links"
      [ testCase "finds missing books from markdown links" $ do
          let content = T.unlines
                [ "## [📚 Books](../books/index.md)"
                , "- [🧪⚙️🧠 The Art of Doing Science and Engineering](../books/the-art-of-doing-science-and-engineering.md)"
                , "- [📜 Sapiens](../books/sapiens-a-brief-history-of-humankind.md)"
                ]
              knownSlug = unsafeSlug "sapiens-a-brief-history-of-humankind"
              candidates = extractBookCandidatesFromReflection (Set.fromList [knownSlug]) "/r/2026-05-05.md" content
          fmap (unBookSlug . candidateSlug) candidates
            @?= ["the-art-of-doing-science-and-engineering"]
      , testCase "skips books that already have pages" $ do
          let content = "- [📜 Sapiens](../books/sapiens.md)\n"
              candidates = extractBookCandidatesFromReflection (Set.fromList [unsafeSlug "sapiens"]) "/r" content
          candidates @?= []
      , testCase "ignores non-book markdown links" $ do
          let content = "- [Posts](../posts/index.md)\n"
              candidates = extractBookCandidatesFromReflection Set.empty "/r" content
          candidates @?= []
      ]
  , testGroup "extractBookCandidatesFromReflection — wikilinks"
      [ testCase "finds books referenced via wikilink" $ do
          let content = "- [[books/cradle-to-cradle|♻️ Cradle to Cradle]]\n"
              candidates = extractBookCandidatesFromReflection Set.empty "/r" content
          fmap (unBookSlug . candidateSlug) candidates @?= ["cradle-to-cradle"]
      , testCase "extracts alias as title for wikilink" $ do
          let content = "- [[books/cradle-to-cradle|♻️ Cradle to Cradle]]\n"
              candidates = extractBookCandidatesFromReflection Set.empty "/r" content
          fmap (unBookTitle . candidateTitle) candidates @?= ["♻️ Cradle to Cradle"]
      , testCase "uses path as title when wikilink has no alias" $ do
          let content = "- [[books/cradle-to-cradle]]\n"
              candidates = extractBookCandidatesFromReflection Set.empty "/r" content
          fmap (unBookTitle . candidateTitle) candidates @?= ["books/cradle-to-cradle"]
      , testCase "skips books/index" $ do
          let content = "- [[books/index|📚 Books]]\n"
              candidates = extractBookCandidatesFromReflection Set.empty "/r" content
          candidates @?= []
      ]
  , testGroup "extractBookCandidatesFromReflection — combined"
      [ testCase "deduplicates is the caller's responsibility" $ do
          let content = T.unlines
                [ "- [Sapiens](../books/sapiens.md)"
                , "- [[books/sapiens|Sapiens]]"
                ]
              candidates = extractBookCandidatesFromReflection Set.empty "/r" content
          length candidates @?= 2
      ]
  ]
  where
    unsafeSlug raw = case mkBookSlug raw of
      Right s -> s
      Left  e -> error (T.unpack e)
