module Automation.InternalLinkingTest (tests) where

import Automation.InternalLinking
  ( defaultLinkingModel
  , indexableDirs
  , traversableDirs
  , extractBody
  , alreadyAnalyzed
  , applyReplacements
  )
import Automation.InternalLinking.CandidateDiscovery
  ( ContentEntry (..)
  , LinkCandidate (..)
  , linkableDirs
  , escapeRegex
  , formatWikilink
  , extractContext
  , extractMainTitle
  , contentAlreadyLinksTo
  , findLinkCandidates
  )
import Automation.InternalLinking.Gemini (buildIdentificationPrompt)
import Automation.InternalLinking.LinkExtraction (extractLinkedPaths, normalizeFilePath)
import Automation.InternalLinking.Masking (maskProtectedRegions)
import Automation.Text (stripEmojis)
import Automation.TestGenerators (testTitle, testRelativePath)
import qualified Data.Text as T
import qualified Automation.Gemini as Gemini
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertEqual, assertBool, testCase)
import Test.Tasty.QuickCheck (testProperty)
import qualified Test.QuickCheck as QC

tests :: TestTree
tests = testGroup "InternalLinking"
  [ constantsTests
  , stripEmojisTests
  , escapeRegexTests
  , formatWikilinkTests
  , extractContextTests
  , extractMainTitleTests
  , normalizeFilePathTests
  , maskProtectedRegionsTests
  , contentAlreadyLinksToTests
  , findLinkCandidatesTests
  , subtitleMatchingTests
  , extractBodyTests
  , alreadyAnalyzedTests
  , extractLinkedPathsTests
  , applyReplacementsTests
  , buildIdentificationPromptTests
  , propertyTests
  ]

constantsTests :: TestTree
constantsTests = testGroup "constants"
  [ testCase "defaultLinkingModel" $
      assertEqual "" Gemini.Gemini31FlashLite defaultLinkingModel
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

escapeRegexTests :: TestTree
escapeRegexTests = testGroup "escapeRegex"
  [ testCase "escapes special chars" $
      assertEqual "" "hello\\.world" (escapeRegex "hello.world")
  , testCase "escapes multiple special chars" $
      assertBool "contains backslash" (T.isInfixOf "\\" (escapeRegex "foo+bar*baz"))
  , testCase "leaves plain text alone" $
      assertEqual "" "hello" (escapeRegex "hello")
  ]

formatWikilinkTests :: TestTree
formatWikilinkTests = testGroup "formatWikilink"
  [ testCase "formats basic wikilink" $
      let entry = ContentEntry (testRelativePath "books/test.md") (testTitle "📖 Test Book") (testTitle "Test Book")
      in assertEqual "" "[[books/test|📖 Test Book]]" (formatWikilink entry)
  , testCase "strips .md from path" $
      let entry = ContentEntry (testRelativePath "books/foo.md") (testTitle "Foo") (testTitle "Foo")
      in assertBool "no .md in link" (not (T.isInfixOf ".md" (formatWikilink entry)))
  ]

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

extractMainTitleTests :: TestTree
extractMainTitleTests = testGroup "extractMainTitle"
  [ testCase "extracts main title before colon-space" $
      assertEqual "" (Just "Domain-Driven Design")
        (extractMainTitle "Domain-Driven Design: Tackling Complexity in the Heart of Software")
  , testCase "returns Nothing when no subtitle separator" $
      assertEqual "" Nothing (extractMainTitle "Thinking, Fast and Slow")
  , testCase "returns Nothing when main title too short" $
      assertEqual "" Nothing (extractMainTitle "AI 2041: Ten Visions for Our Future")
  , testCase "extracts single-word main title" $
      assertEqual "" (Just "Abundance") (extractMainTitle "Abundance: The Inner Path to Wealth")
  , testCase "extracts single-word main title for distinctive books" $
      assertEqual "" (Just "Antifragile") (extractMainTitle "Antifragile: Things That Gain from Disorder")
  , testCase "extracts single-word main title for Refactoring" $
      assertEqual "" (Just "Refactoring") (extractMainTitle "Refactoring: Improving the Design of Existing Code")
  , testCase "extracts main title from dash-separated subtitle" $
      assertEqual "" (Just "System Design Interview")
        (extractMainTitle "System Design Interview - An Insider's Guide")
  , testCase "prefers colon separator over dash separator" $
      assertEqual "" (Just "Factfulness")
        (extractMainTitle "Factfulness: Ten Reasons We're Wrong About the World - and Why Things Are Better Than You Think")
  , testCase "extracts from first colon-space only" $
      assertEqual "" (Just "A Pattern Language")
        (extractMainTitle "A Pattern Language: Towns, Buildings, Construction")
  , testCase "returns Nothing for colon without space" $
      assertEqual "" Nothing (extractMainTitle "Title:NoSpace")
  , testCase "returns valid main title meeting minimum length" $
      assertEqual "" (Just "Against the Grain")
        (extractMainTitle "Against the Grain: A Deep History of the Earliest States")
  ]

normalizeFilePathTests :: TestTree
normalizeFilePathTests = testGroup "normalizeFilePath"
  [ testCase "resolves parent directory references" $
      assertEqual "" "books/foo.md"
        (normalizeFilePath "reflections/../books/foo.md")
  , testCase "resolves current directory references" $
      assertEqual "" "books/foo.md"
        (normalizeFilePath "books/./foo.md")
  , testCase "preserves simple paths" $
      assertEqual "" "books/foo.md"
        (normalizeFilePath "books/foo.md")
  , testCase "handles multiple parent refs" $
      assertEqual "" "foo.md"
        (normalizeFilePath "a/b/../../foo.md")
  , testCase "handles complex nested path" $
      assertEqual "" "reflections/topics/bar.md"
        (normalizeFilePath "reflections/2025/../topics/./bar.md")
  , testCase "preserves absolute-like paths" $
      assertEqual "" "content/reflections/some-book.md"
        (normalizeFilePath "content/reflections/some-book.md")
  ]

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

contentAlreadyLinksToTests :: TestTree
contentAlreadyLinksToTests = testGroup "contentAlreadyLinksTo"
  [ testCase "detects wikilink" $
      let entry = ContentEntry (testRelativePath "books/test.md") (testTitle "Test") (testTitle "Test")
          content = "see [[books/test|Test]] here"
      in assertBool "found link" (contentAlreadyLinksTo content entry)
  , testCase "detects path with pipe" $
      let entry = ContentEntry (testRelativePath "books/test.md") (testTitle "Test") (testTitle "Test")
          content = "[[books/test|alias]]"
      in assertBool "found link" (contentAlreadyLinksTo content entry)
  , testCase "returns false when no link" $
      let entry = ContentEntry (testRelativePath "books/test.md") (testTitle "Test") (testTitle "Test")
          content = "no links here at all"
      in assertBool "no link" (not (contentAlreadyLinksTo content entry))
  ]

sampleEntry :: ContentEntry
sampleEntry = ContentEntry (testRelativePath "books/thinking-fast.md") (testTitle "🤔 Thinking, Fast and Slow") (testTitle "Thinking, Fast and Slow")

findLinkCandidatesTests :: TestTree
findLinkCandidatesTests = testGroup "findLinkCandidates"
  [ testCase "finds title in content" $
      let content = "I recommend reading Thinking, Fast and Slow for insights"
          masked  = content
          candidates = findLinkCandidates [sampleEntry] content masked (testRelativePath "reflections/2024-01-01.md")
      in assertEqual "one candidate" 1 (length candidates)
  , testCase "skips self-references" $
      let content = "I recommend Thinking, Fast and Slow for insights"
          masked  = content
          candidates = findLinkCandidates [sampleEntry] content masked (testRelativePath "books/thinking-fast.md")
      in assertEqual "no candidates for self" 0 (length candidates)
  , testCase "skips already-linked content" $
      let content = "see [[books/thinking-fast|TFS]] and Thinking, Fast and Slow"
          masked  = maskProtectedRegions content
          candidates = findLinkCandidates [sampleEntry] content masked (testRelativePath "reflections/2024-01-01.md")
      in assertEqual "no candidates (already linked)" 0 (length candidates)
  , testCase "prefers longer matches" $
      let short = ContentEntry (testRelativePath "books/short.md") (testTitle "📖 Fast and Slow") (testTitle "Fast and Slow")
          long  = sampleEntry
          content = "I love Thinking, Fast and Slow as a book"
          masked  = content
          candidates = findLinkCandidates [short, long] content masked (testRelativePath "reflections/test.md")
      in case candidates of
        (c:_) -> assertEqual "longer match wins" (testRelativePath "books/thinking-fast.md") (relativePath (entry c))
        []    -> assertBool "should have found candidates" False
  , testCase "returns empty for no matches" $
      let content = "This has nothing to do with any book"
          masked  = content
          candidates = findLinkCandidates [sampleEntry] content masked (testRelativePath "reflections/test.md")
      in assertEqual "no candidates" 0 (length candidates)
  , testCase "self-exclusion works with different RelativePath values" $
      let entry = ContentEntry (testRelativePath "articles/my-article.md") (testTitle "My Great Article") (testTitle "My Great Article")
          content = "I wrote My Great Article about testing"
          masked  = content
          selfPath = testRelativePath "articles/my-article.md"
          otherPath = testRelativePath "reflections/2026-06-01.md"
          candidatesSelf = findLinkCandidates [entry] content masked selfPath
          candidatesOther = findLinkCandidates [entry] content masked otherPath
      in do
        assertEqual "self path yields no candidates" 0 (length candidatesSelf)
        assertEqual "other path yields candidates" 1 (length candidatesOther)
  , testCase "multiple entries with self-exclusion only removes matching entry" $
      let entryA = ContentEntry (testRelativePath "books/book-a.md") (testTitle "Functional Programming") (testTitle "Functional Programming")
          entryB = ContentEntry (testRelativePath "books/book-b.md") (testTitle "Category Theory") (testTitle "Category Theory")
          content = "I love Functional Programming and Category Theory"
          masked  = content
          candidates = findLinkCandidates [entryA, entryB] content masked (testRelativePath "books/book-a.md")
      in do
        assertEqual "only non-self entry matches" 1 (length candidates)
        case candidates of
          (c:_) -> assertEqual "matched entry is book-b" (testRelativePath "books/book-b.md") (relativePath (entry c))
          [] -> assertBool "should have found one candidate" False
  ]

dddEntry :: ContentEntry
dddEntry = ContentEntry
  (testRelativePath "books/domain-driven-design.md")
  (testTitle "🧩 Domain-Driven Design: Tackling Complexity in the Heart of Software")
  (testTitle "Domain-Driven Design: Tackling Complexity in the Heart of Software")

subtitleMatchingTests :: TestTree
subtitleMatchingTests = testGroup "subtitle matching"
  [ testCase "matches main title when full title not in content" $
      let content = "I loved reading Domain-Driven Design and it changed my perspective"
          masked  = content
          candidates = findLinkCandidates [dddEntry] content masked (testRelativePath "reflections/test.md")
      in do
          assertEqual "one candidate" 1 (length candidates)
          case candidates of
            (c:_) -> do
              assertEqual "matched main title" "Domain-Driven Design" (matchedText c)
              assertEqual "correct entry" (testRelativePath "books/domain-driven-design.md") (relativePath (entry c))
            [] -> assertBool "should have candidates" False
  , testCase "prefers full title over main title" $
      let content = "The book Domain-Driven Design: Tackling Complexity in the Heart of Software is excellent"
          masked  = content
          candidates = findLinkCandidates [dddEntry] content masked (testRelativePath "reflections/test.md")
      in do
          assertEqual "one candidate" 1 (length candidates)
          case candidates of
            (c:_) -> assertBool "matched full title"
              (T.isInfixOf "Tackling Complexity" (matchedText c))
            [] -> assertBool "should have candidates" False
  , testCase "does not match subtitle prefix for entries without subtitles" $
      let content = "I read Thinking yesterday"
          masked  = content
          candidates = findLinkCandidates [sampleEntry] content masked (testRelativePath "reflections/test.md")
      in assertEqual "no candidates" 0 (length candidates)
  , testCase "matches main title in book recommendation list" $
      let entry = ContentEntry
            (testRelativePath "books/a-pattern-language.md")
            (testTitle "🏘️ A Pattern Language: Towns, Buildings, Construction")
            (testTitle "A Pattern Language: Towns, Buildings, Construction")
          content = "Recommended books:\n- A Pattern Language by Christopher Alexander"
          masked  = content
          candidates = findLinkCandidates [entry] content masked (testRelativePath "reflections/test.md")
      in do
          assertEqual "one candidate" 1 (length candidates)
          case candidates of
            (c:_) -> assertEqual "matched" "A Pattern Language" (matchedText c)
            [] -> assertBool "should have candidates" False
  , testCase "respects protected regions for main title matches" $
      let content = "## Domain-Driven Design\nBody text without any book references"
          masked  = maskProtectedRegions content
          candidates = findLinkCandidates [dddEntry] content masked (testRelativePath "reflections/test.md")
      in assertEqual "no candidates" 0 (length candidates)
  , testCase "uses full title in wikilink even when matched via partial" $
      let content = "I loved reading Domain-Driven Design and it changed my perspective"
          masked  = content
          candidates = findLinkCandidates [dddEntry] content masked (testRelativePath "reflections/test.md")
          result = applyReplacements content candidates (replicate (length candidates) True)
      in assertBool "wikilink uses full title"
           (T.isInfixOf "Domain-Driven Design: Tackling Complexity" result)
  , testCase "matches single-word main title from book recommendation" $
      let refactoringEntry = ContentEntry
            (testRelativePath "books/refactoring.md")
            (testTitle "🗑️ Refactoring: Improving the Design of Existing Code")
            (testTitle "Refactoring: Improving the Design of Existing Code")
          content = "* Refactoring by Martin Fowler is relevant because it covers restructuring code"
          masked  = content
          candidates = findLinkCandidates [refactoringEntry] content masked (testRelativePath "ai-blog/test.md")
      in do
          assertEqual "one candidate" 1 (length candidates)
          case candidates of
            (c:_) -> assertEqual "matched text" "Refactoring" (matchedText c)
            [] -> assertBool "should have candidates" False
  , testCase "matches single-word Antifragile via main title" $
      let antifragileEntry = ContentEntry
            (testRelativePath "books/antifragile.md")
            (testTitle "📉 Antifragile: Things That Gain from Disorder")
            (testTitle "Antifragile: Things That Gain from Disorder")
          content = "Antifragile by Nassim Nicholas Taleb offers a contrasting perspective"
          masked  = content
          candidates = findLinkCandidates [antifragileEntry] content masked (testRelativePath "ai-blog/test.md")
      in do
          assertEqual "one candidate" 1 (length candidates)
          case candidates of
            (c:_) -> assertEqual "matched text" "Antifragile" (matchedText c)
            [] -> assertBool "should have candidates" False
  , testCase "matches dash-separated subtitle via main title" $
      let systemDesignEntry = ContentEntry
            (testRelativePath "books/system-design-interview.md")
            (testTitle "🎨 System Design Interview - An Insider's Guide")
            (testTitle "System Design Interview - An Insider's Guide")
          content = "I recommend System Design Interview for preparing"
          masked  = content
          candidates = findLinkCandidates [systemDesignEntry] content masked (testRelativePath "reflections/test.md")
      in do
          assertEqual "one candidate" 1 (length candidates)
          case candidates of
            (c:_) -> assertEqual "matched text" "System Design Interview" (matchedText c)
            [] -> assertBool "should have candidates" False
  ]

extractBodyTests :: TestTree
extractBodyTests = testGroup "extractBody"
  [ testCase "extracts body after frontmatter" $
      let content = "---\ntitle: Test\n---\nBody here"
      in assertEqual "" "Body here" (extractBody content)
  , testCase "returns content when no frontmatter" $
      let content = "No frontmatter here"
      in assertEqual "" "No frontmatter here" (extractBody content)
  ]

alreadyAnalyzedTests :: TestTree
alreadyAnalyzedTests = testGroup "alreadyAnalyzed"
  [ testCase "false when no analysis field" $
      assertBool "not analyzed" (not (alreadyAnalyzed "---\ntitle: Test\n---\nBody"))
  , testCase "true when analysis field present" $
      assertBool "analyzed" (alreadyAnalyzed "---\nlink_analysis_model: gemini-2.5-flash\n---\nBody")
  , testCase "false when force_analyze_links is true" $
      assertBool "force re-analyze"
        (not (alreadyAnalyzed "---\nlink_analysis_model: gemini-2.5-flash\nforce_analyze_links: true\n---\nBody"))
  , testCase "true when force_analyze_links is false" $
      assertBool "should be analyzed"
        (alreadyAnalyzed "---\nlink_analysis_model: gemini-2.5-flash\nforce_analyze_links: false\n---\nBody")
  , testCase "false when no frontmatter at all" $
      assertBool "not analyzed" (not (alreadyAnalyzed "Just plain text"))
  , testCase "true with different model name" $
      assertBool "analyzed with different model"
        (alreadyAnalyzed "---\nlink_analysis_model: gemini-3-flash-preview\n---\nBody")
  ]

extractLinkedPathsTests :: TestTree
extractLinkedPathsTests = testGroup "extractLinkedPaths"
  [ testCase "skips external URLs" $
      let body = "See [title](https://example.com/foo.md) here"
          paths = extractLinkedPaths body "reflections/2025-01-01.md" "/content"
      in assertEqual "should find no paths" 0 (length paths)
  , testCase "returns empty for plain text" $
      let body = "No links here at all"
          paths = extractLinkedPaths body "reflections/2025-01-01.md" "/content"
      in assertEqual "should find no paths" 0 (length paths)
  , testCase "skips external URLs" $
      let body = "See [title](https://example.com/foo.md) here"
          paths = extractLinkedPaths body "reflections/2025-01-01.md" "/content"
      in assertEqual "should find no paths" 0 (length paths)
  , testCase "extracts multiple different links" $
      let body = "Read [[books/a]] and [[topics/b]] today"
          paths = extractLinkedPaths body "reflections/2025-01-01.md" "/content"
      in assertEqual "should find two" 2 (length paths)
  , testCase "resolves plain wikilinks relative to note directory" $
      let body = "I enjoyed [[some-book]] today"
          paths = extractLinkedPaths body "reflections/2025-01-01.md" "/content"
      in assertEqual "should resolve to reflections/some-book.md"
           ["reflections/some-book.md"] paths
  , testCase "resolves relative markdown links" $
      let body = "See [book](../books/foo.md) for details"
          paths = extractLinkedPaths body "reflections/2025-01-01.md" "/content"
      in assertEqual "should resolve to books/foo.md"
           ["books/foo.md"] paths
  ]

applyReplacementsTests :: TestTree
applyReplacementsTests = testGroup "applyReplacements"
  [ testCase "applies single replacement" $
      let content = "I read Thinking, Fast and Slow yesterday"
          candidate = LinkCandidate
            { entry       = sampleEntry
            , matchedText = "Thinking, Fast and Slow"
            , position    = 7
            , context     = ""
            }
          result = applyReplacements content [candidate] [True]
      in assertBool "contains wikilink" (T.isInfixOf "[[books/thinking-fast|" result)
  , testCase "skips invalid candidates" $
      let content = "I read Thinking, Fast and Slow yesterday"
          candidate = LinkCandidate
            { entry       = sampleEntry
            , matchedText = "Thinking, Fast and Slow"
            , position    = 7
            , context     = ""
            }
          result = applyReplacements content [candidate] [False]
      in assertEqual "unchanged" content result
  , testCase "handles multiple replacements" $
      let entry2 = ContentEntry (testRelativePath "books/other.md") (testTitle "📖 Other Book Title") (testTitle "Other Book Title")
          content = "Read Thinking, Fast and Slow and Other Book Title"
          c1 = LinkCandidate sampleEntry "Thinking, Fast and Slow" 5 ""
          c2 = LinkCandidate entry2 "Other Book Title" 33 ""
          result = applyReplacements content [c1, c2] [True, True]
      in do
          assertBool "has first link" (T.isInfixOf "[[books/thinking-fast|" result)
          assertBool "has second link" (T.isInfixOf "[[books/other|" result)
  , testCase "returns original for empty candidates" $
      let content = "no links here"
          result = applyReplacements content [] []
      in assertEqual "unchanged" content result
  , testCase "applies replacement with all-true validations" $
      let entry = ContentEntry (testRelativePath "books/test.md") (testTitle "📖 Test") (testTitle "Test")
          content = "I love Test here"
          c = LinkCandidate entry "Test" 7 ""
          result = applyReplacements content [c] [True]
      in assertBool "should have wikilink" (T.isInfixOf "[[books/test|" result)
  ]

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
  , testCase "includes relative paths" $
      let prompt = buildIdentificationPrompt "body" [sampleEntry]
      in assertBool "has relative path" (T.isInfixOf "books/thinking-fast.md" prompt)
  , testCase "handles multiple entries" $
      let entry2 = ContentEntry (testRelativePath "books/other.md") (testTitle "📖 Other") (testTitle "Other")
          prompt = buildIdentificationPrompt "body" [sampleEntry, entry2]
      in do
          assertBool "has first" (T.isInfixOf "Thinking, Fast and Slow" prompt)
          assertBool "has second" (T.isInfixOf "Other" prompt)
  , testCase "handles empty entries" $
      let prompt = buildIdentificationPrompt "body" []
      in assertBool "still has system prompt" (T.isInfixOf "editorial assistant" prompt)
  , testCase "includes also-known-as for entries with subtitles" $
      let prompt = buildIdentificationPrompt "body text" [dddEntry]
      in assertBool "has also known as" (T.isInfixOf "also known as \"Domain-Driven Design\"" prompt)
  , testCase "does not include also-known-as for entries without subtitles" $
      let prompt = buildIdentificationPrompt "body text" [sampleEntry]
      in assertBool "no also known as" (not (T.isInfixOf "also known as" prompt))
  ]

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
      in not (T.null (T.strip title)) QC.==>
        let entry = ContentEntry (testRelativePath "books/test.md") (testTitle title) (testTitle title)
            wl = formatWikilink entry
        in T.isInfixOf title wl
  , testProperty "applyReplacements with all-false validations returns original" $ \s ->
      let content = T.pack (s :: String)
          candidates = [LinkCandidate sampleEntry "test" 0 ""]
          result = applyReplacements content candidates [False]
      in result == content
  ]

