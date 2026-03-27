module Automation.InternalLinkingTest (tests) where

import Automation.InternalLinking
import Data.Text (Text)
import qualified Data.Text as T
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertEqual, assertBool, testCase)
import Test.Tasty.QuickCheck (testProperty)

tests :: TestTree
tests = testGroup "InternalLinking"
  [ constantsTests
  , stripEmojisTests
  , escapeRegexTests
  , formatWikilinkTests
  , extractContextTests
  , maskProtectedRegionsTests
  , contentAlreadyLinksToTests
  , findLinkCandidatesTests
  , extractBodyTests
  , alreadyAnalyzedTests
  , applyReplacementsTests
  , buildIdentificationPromptTests
  , propertyTests
  ]

-- --------------------------------------------------------------------------
-- Constants
-- --------------------------------------------------------------------------

constantsTests :: TestTree
constantsTests = testGroup "constants"
  [ testCase "defaultLinkingModel" $
      assertEqual "" "gemini-3.1-flash-lite-preview" defaultLinkingModel
  , testCase "linkableDirs contains books" $
      assertBool "books in linkableDirs" ("books" `elem` linkableDirs)
  , testCase "indexableDirs has 10 entries" $
      assertEqual "" 10 (length indexableDirs)
  , testCase "traversableDirs includes reflections" $
      assertBool "reflections in traversableDirs" ("reflections" `elem` traversableDirs)
  , testCase "traversableDirs includes systems-for-public-good" $
      assertBool "systems-for-public-good in traversableDirs"
        ("systems-for-public-good" `elem` traversableDirs)
  ]

-- --------------------------------------------------------------------------
-- stripEmojis
-- --------------------------------------------------------------------------

stripEmojisTests :: TestTree
stripEmojisTests = testGroup "stripEmojis"
  [ testCase "strips emoji from title" $
      assertEqual "" "Thinking, Fast and Slow" (stripEmojis "🤔🐇🐢 Thinking, Fast and Slow")
  , testCase "returns plain text unchanged" $
      assertEqual "" "Hello World" (stripEmojis "Hello World")
  , testCase "strips multiple emojis" $
      assertEqual "" "Hello" (stripEmojis "👋🌍 Hello")
  , testCase "handles empty string" $
      assertEqual "" "" (stripEmojis "")
  , testCase "collapses multiple spaces" $
      assertEqual "" "A B" (stripEmojis "A   B")
  ]

-- --------------------------------------------------------------------------
-- escapeRegex
-- --------------------------------------------------------------------------

escapeRegexTests :: TestTree
escapeRegexTests = testGroup "escapeRegex"
  [ testCase "escapes special chars" $
      assertEqual "" "hello\\.world" (escapeRegex "hello.world")
  , testCase "escapes multiple special chars" $
      assertBool "contains backslash" (T.isInfixOf "\\" (escapeRegex "foo+bar*baz"))
  , testCase "leaves plain text alone" $
      assertEqual "" "hello" (escapeRegex "hello")
  ]

-- --------------------------------------------------------------------------
-- formatWikilink
-- --------------------------------------------------------------------------

formatWikilinkTests :: TestTree
formatWikilinkTests = testGroup "formatWikilink"
  [ testCase "formats basic wikilink" $
      let entry = ContentEntry "books/test.md" "📖 Test Book" "Test Book"
      in assertEqual "" "[[books/test|📖 Test Book]]" (formatWikilink entry)
  , testCase "strips .md from path" $
      let entry = ContentEntry "books/foo.md" "Foo" "Foo"
      in assertBool "no .md in link" (not (T.isInfixOf ".md" (formatWikilink entry)))
  ]

-- --------------------------------------------------------------------------
-- extractContext
-- --------------------------------------------------------------------------

extractContextTests :: TestTree
extractContextTests = testGroup "extractContext"
  [ testCase "extracts context around position" $
      let ctx = extractContext "Hello World" 6 5
      in assertBool "contains World" (T.isInfixOf "World" ctx)
  , testCase "handles start of text" $
      let ctx = extractContext "Hello" 0 5
      in assertEqual "" "Hello" ctx
  , testCase "adds ellipsis for long text" $
      let content = T.replicate 300 "x"
          ctx = extractContext content 150 5
      in assertBool "has leading ellipsis" (T.isPrefixOf "..." ctx)
  ]

-- --------------------------------------------------------------------------
-- maskProtectedRegions
-- --------------------------------------------------------------------------

maskProtectedRegionsTests :: TestTree
maskProtectedRegionsTests = testGroup "maskProtectedRegions"
  [ testCase "preserves length" $
      let content = "---\ntitle: Test\n---\nHello World"
          masked = maskProtectedRegions content
      in assertEqual "same length" (T.length content) (T.length masked)
  , testCase "masks frontmatter" $
      let content = "---\ntitle: Test\n---\nHello World"
          masked = maskProtectedRegions content
      in assertBool "body visible" (T.isInfixOf "Hello World" masked)
  , testCase "masks inline code" $
      let content = "before `code here` after"
          masked = maskProtectedRegions content
      in assertBool "code masked" (not (T.isInfixOf "code here" masked))
  , testCase "masks wikilinks" $
      let content = "before [[some/link]] after"
          masked = maskProtectedRegions content
      in assertBool "wikilink masked" (not (T.isInfixOf "[[some/link]]" masked))
  , testCase "masks markdown links" $
      let content = "see [title](path.md) here"
          masked = maskProtectedRegions content
      in assertBool "md link masked" (not (T.isInfixOf "[title](path.md)" masked))
  , testCase "masks headings" $
      let content = "# My Heading\nBody text"
          masked = maskProtectedRegions content
      in assertBool "heading masked" (not (T.isInfixOf "# My Heading" masked))
  , testCase "masks URLs" $
      let content = "visit https://example.com today"
          masked = maskProtectedRegions content
      in assertBool "URL masked" (not (T.isInfixOf "https://example.com" masked))
  , testCase "masks bold markers" $
      let content = "some **bold** text"
          masked = maskProtectedRegions content
      in assertBool "bold markers masked" (not (T.isInfixOf "**" masked))
  ]

-- --------------------------------------------------------------------------
-- contentAlreadyLinksTo
-- --------------------------------------------------------------------------

contentAlreadyLinksToTests :: TestTree
contentAlreadyLinksToTests = testGroup "contentAlreadyLinksTo"
  [ testCase "detects wikilink" $
      let entry = ContentEntry "books/test.md" "Test" "Test"
          content = "see [[books/test|Test]] here"
      in assertBool "found link" (contentAlreadyLinksTo content entry)
  , testCase "detects path with pipe" $
      let entry = ContentEntry "books/test.md" "Test" "Test"
          content = "[[books/test|alias]]"
      in assertBool "found link" (contentAlreadyLinksTo content entry)
  , testCase "returns false when no link" $
      let entry = ContentEntry "books/test.md" "Test" "Test"
          content = "no links here at all"
      in assertBool "no link" (not (contentAlreadyLinksTo content entry))
  ]

-- --------------------------------------------------------------------------
-- findLinkCandidates
-- --------------------------------------------------------------------------

sampleEntry :: ContentEntry
sampleEntry = ContentEntry "books/thinking-fast.md" "🤔 Thinking, Fast and Slow" "Thinking, Fast and Slow"

findLinkCandidatesTests :: TestTree
findLinkCandidatesTests = testGroup "findLinkCandidates"
  [ testCase "finds title in content" $
      let content = "I recommend reading Thinking, Fast and Slow for insights"
          masked  = content
          candidates = findLinkCandidates [sampleEntry] content masked "reflections/2024-01-01.md"
      in assertEqual "one candidate" 1 (length candidates)
  , testCase "skips self-references" $
      let content = "I recommend Thinking, Fast and Slow for insights"
          masked  = content
          candidates = findLinkCandidates [sampleEntry] content masked "books/thinking-fast.md"
      in assertEqual "no candidates for self" 0 (length candidates)
  , testCase "skips already-linked content" $
      let content = "see [[books/thinking-fast|TFS]] and Thinking, Fast and Slow"
          masked  = maskProtectedRegions content
          candidates = findLinkCandidates [sampleEntry] content masked "reflections/2024-01-01.md"
      in assertEqual "no candidates (already linked)" 0 (length candidates)
  , testCase "prefers longer matches" $
      let short = ContentEntry "books/short.md" "📖 Fast and Slow" "Fast and Slow"
          long  = sampleEntry
          content = "I love Thinking, Fast and Slow as a book"
          masked  = content
          candidates = findLinkCandidates [short, long] content masked "reflections/test.md"
      in case candidates of
        (c:_) -> assertEqual "longer match wins" "books/thinking-fast.md" (ceRelativePath (lcEntry c))
        []    -> assertBool "should have found candidates" False
  , testCase "returns empty for no matches" $
      let content = "This has nothing to do with any book"
          masked  = content
          candidates = findLinkCandidates [sampleEntry] content masked "reflections/test.md"
      in assertEqual "no candidates" 0 (length candidates)
  ]

-- --------------------------------------------------------------------------
-- extractBody
-- --------------------------------------------------------------------------

extractBodyTests :: TestTree
extractBodyTests = testGroup "extractBody"
  [ testCase "extracts body after frontmatter" $
      let content = "---\ntitle: Test\n---\nBody here"
      in assertEqual "" "Body here" (extractBody content)
  , testCase "returns content when no frontmatter" $
      let content = "No frontmatter here"
      in assertEqual "" "No frontmatter here" (extractBody content)
  ]

-- --------------------------------------------------------------------------
-- alreadyAnalyzed
-- --------------------------------------------------------------------------

alreadyAnalyzedTests :: TestTree
alreadyAnalyzedTests = testGroup "alreadyAnalyzed"
  [ testCase "false when no analysis field" $
      assertBool "not analyzed" (not (alreadyAnalyzed "---\ntitle: Test\n---\nBody"))
  , testCase "true when analysis field present" $
      assertBool "analyzed" (alreadyAnalyzed "---\nlink_analysis_model: gemini-2.5-flash\n---\nBody")
  , testCase "false when force_analyze_links is true" $
      assertBool "force re-analyze"
        (not (alreadyAnalyzed "---\nlink_analysis_model: gemini-2.5-flash\nforce_analyze_links: true\n---\nBody"))
  ]

-- --------------------------------------------------------------------------
-- applyReplacements
-- --------------------------------------------------------------------------

applyReplacementsTests :: TestTree
applyReplacementsTests = testGroup "applyReplacements"
  [ testCase "applies single replacement" $
      let content = "I read Thinking, Fast and Slow yesterday"
          candidate = LinkCandidate
            { lcEntry       = sampleEntry
            , lcMatchedText = "Thinking, Fast and Slow"
            , lcPosition    = 7
            , lcContext     = ""
            }
          result = applyReplacements content [candidate] [True]
      in assertBool "contains wikilink" (T.isInfixOf "[[books/thinking-fast|" result)
  , testCase "skips invalid candidates" $
      let content = "I read Thinking, Fast and Slow yesterday"
          candidate = LinkCandidate
            { lcEntry       = sampleEntry
            , lcMatchedText = "Thinking, Fast and Slow"
            , lcPosition    = 7
            , lcContext     = ""
            }
          result = applyReplacements content [candidate] [False]
      in assertEqual "unchanged" content result
  , testCase "handles multiple replacements" $
      let entry2 = ContentEntry "books/other.md" "📖 Other Book Title" "Other Book Title"
          content = "Read Thinking, Fast and Slow and Other Book Title"
          c1 = LinkCandidate sampleEntry "Thinking, Fast and Slow" 5 ""
          c2 = LinkCandidate entry2 "Other Book Title" 33 ""
          result = applyReplacements content [c1, c2] [True, True]
      in do
          assertBool "has first link" (T.isInfixOf "[[books/thinking-fast|" result)
          assertBool "has second link" (T.isInfixOf "[[books/other|" result)
  ]

-- --------------------------------------------------------------------------
-- buildIdentificationPrompt
-- --------------------------------------------------------------------------

buildIdentificationPromptTests :: TestTree
buildIdentificationPromptTests = testGroup "buildIdentificationPrompt"
  [ testCase "includes book titles" $
      let prompt = buildIdentificationPrompt "Some body text" [sampleEntry]
      in assertBool "has title" (T.isInfixOf "Thinking, Fast and Slow" prompt)
  , testCase "includes document body" $
      let prompt = buildIdentificationPrompt "My document content" [sampleEntry]
      in assertBool "has body" (T.isInfixOf "My document content" prompt)
  , testCase "includes JSON instruction" $
      let prompt = buildIdentificationPrompt "body" [sampleEntry]
      in assertBool "has JSON instruction" (T.isInfixOf "JSON array" prompt)
  ]

-- --------------------------------------------------------------------------
-- Property tests
-- --------------------------------------------------------------------------

propertyTests :: TestTree
propertyTests = testGroup "properties"
  [ testProperty "maskProtectedRegions preserves length" $ \s ->
      let txt = T.pack (s :: String)
          masked = maskProtectedRegions txt
      in T.length masked == T.length txt
  , testProperty "stripEmojis never increases length beyond original" $ \s ->
      let txt = T.pack (s :: String)
      in T.length (stripEmojis txt) <= T.length txt
  , testProperty "formatWikilink contains entry title" $ \s ->
      let title = T.pack (s :: String)
          entry = ContentEntry "books/test.md" title title
          wl = formatWikilink entry
      in T.isInfixOf title wl
  , testProperty "applyReplacements with all-false validations returns original" $ \s ->
      let content = T.pack (s :: String)
          candidates = [LinkCandidate sampleEntry "test" 0 ""]
          result = applyReplacements content candidates [False]
      in result == content
  ]
