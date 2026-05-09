module Automation.BookReports.DiscoveryTest (tests) where

import qualified Data.Set as Set
import qualified Data.Text as T
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool, assertEqual)

import Automation.BookReports.Discovery
  ( BookCandidate (..)
  , extractCandidatesFromBookReport
  )
import Automation.BookReports.Types
  ( mkBookSlug
  , unBookAuthor
  , unBookSlug
  , unBookTitle
  )

tests :: TestTree
tests = testGroup "BookReports.Discovery"
  [ testGroup "extractCandidatesFromBookReport — bold-title bullets"
      [ testCase "finds a plain-text bold-title recommendation" $ do
          let body = T.unlines
                [ "## 📚 Additional Book Recommendations"
                , ""
                , "* 📖 **Meditation for Fidgety Skeptics** by Dan Harris: A practical follow-up."
                ]
              candidates = extractCandidatesFromBookReport Set.empty "/books/sample.md" body
          fmap (unBookTitle . candidateTitle) candidates
            @?= ["Meditation for Fidgety Skeptics"]
          fmap (fmap unBookAuthor . candidateAuthor) candidates
            @?= [Just "Dan Harris"]
          fmap (unBookSlug . candidateSlug) candidates
            @?= ["meditation-for-fidgety-skeptics"]

      , testCase "skips lines that already contain a markdown link" $ do
          let body = "* **[🧘 Mindfulness in Plain English](./mindfulness-in-plain-english.md)** by Henepola Gunaratana: Classic guide.\n"
              candidates = extractCandidatesFromBookReport Set.empty "/books/sample.md" body
          candidates @?= []

      , testCase "skips lines that already contain an Obsidian wikilink" $ do
          let body = "* 📖 [[books/cradle-to-cradle|♻️ Cradle to Cradle]] by William McDonough: A foundational text.\n"
              candidates = extractCandidatesFromBookReport Set.empty "/books/sample.md" body
          candidates @?= []

      , testCase "skips a candidate whose slug is already a known book" $ do
          let body = "* 📖 **Sapiens** by Yuval Noah Harari: A sweeping history of humankind.\n"
              known = Set.fromList [unsafeSlug "sapiens"]
              candidates = extractCandidatesFromBookReport known "/books/sample.md" body
          candidates @?= []
      ]

  , testGroup "extractCandidatesFromBookReport — plain (unbold) bullets"
      [ testCase "matches `* 📖 Title by Author: ...`" $ do
          let body = "* 📖 Four Thousand Weeks by Oliver Burkeman: Challenges productivity.\n"
              candidates = extractCandidatesFromBookReport Set.empty "/books/sample.md" body
          fmap (unBookTitle . candidateTitle) candidates @?= ["Four Thousand Weeks"]
          fmap (fmap unBookAuthor . candidateAuthor) candidates @?= [Just "Oliver Burkeman"]

      , testCase "rejects bullets that have no ` by ` clause" $ do
          let body = "* 📖 Some random thought without an author attribution.\n"
              candidates = extractCandidatesFromBookReport Set.empty "/books/sample.md" body
          candidates @?= []

      , testCase "rejects bullets whose extracted title is too short" $ do
          let body = "* 📖 Hi by Anonymous: too short to count.\n"
              candidates = extractCandidatesFromBookReport Set.empty "/books/sample.md" body
          candidates @?= []
      ]

  , testGroup "extractCandidatesFromBookReport — non-bullet content"
      [ testCase "ignores prose paragraphs that happen to say 'X by Y'" $ do
          let body = "Some prose where Foo by Bar happens to appear.\n"
              candidates = extractCandidatesFromBookReport Set.empty "/books/sample.md" body
          candidates @?= []

      , testCase "ignores headings" $ do
          let body = "## 📚 Book Recommendations by section\n"
              candidates = extractCandidatesFromBookReport Set.empty "/books/sample.md" body
          candidates @?= []
      ]

  , testGroup "extractCandidatesFromBookReport — cross-cutting"
      [ testCase "deduplicates is the caller's responsibility" $ do
          let body = T.unlines
                [ "* 📖 **Sapiens** by Yuval Noah Harari: First mention."
                , "* 📖 Sapiens by Yuval Noah Harari: Second mention."
                ]
              candidates = extractCandidatesFromBookReport Set.empty "/books/sample.md" body
          assertEqual "both mentions returned" 2 (length candidates)
          assertBool "all share the same slug" $
            length (Set.fromList (fmap candidateSlug candidates)) == 1

      , testCase "preserves the source file path on the candidate" $ do
          let body = "* 📖 **Atomic Habits** by James Clear: A primer on habit science.\n"
              candidates = extractCandidatesFromBookReport Set.empty "/books/some-other-book.md" body
          fmap candidateSourceFile candidates @?= ["/books/some-other-book.md"]
      ]
  ]
  where
    unsafeSlug raw = case mkBookSlug raw of
      Right s -> s
      Left  e -> error (T.unpack e)
