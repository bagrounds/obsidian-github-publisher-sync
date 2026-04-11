module Automation.ReflectionTitleTest (tests) where

import qualified Data.Text as T
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)

import Automation.ReflectionTitle
import qualified Automation.Gemini as Gemini

tests :: TestTree
tests = testGroup "ReflectionTitle"
  [ defaultModelTests
  , reflectionNeedsTitleTests
  , stripTitlePrefixesTests
  , extractTrailingEmojisTests
  , extractHeadingEmojisTests
  , extractLinkedTitlesTests
  , parseReflectionTitleTests
  , applyReflectionTitleTests
  , buildReflectionTitlePromptTests
  ]

defaultModelTests :: TestTree
defaultModelTests = testGroup "defaultTitleModel"
  [ testCase "is Gemini25Flash" $
      defaultTitleModel @?= Gemini.Gemini25Flash
  ]

reflectionNeedsTitleTests :: TestTree
reflectionNeedsTitleTests = testGroup "reflectionNeedsTitle"
  [ testCase "needs title when title equals date" $
      reflectionNeedsTitle "---\ntitle: 2025-01-15\n---\nbody" "2025-01-15" @?= True
  , testCase "needs title when quoted title equals date" $
      reflectionNeedsTitle "---\ntitle: \"2025-01-15\"\n---\nbody" "2025-01-15" @?= True
  , testCase "does not need title when title differs from date" $
      reflectionNeedsTitle "---\ntitle: My Creative Title\n---\nbody" "2025-01-15" @?= False
  , testCase "needs title when no title field" $
      reflectionNeedsTitle "---\ntags: foo\n---\nbody" "2025-01-15" @?= True
  , testCase "needs title when no frontmatter" $
      reflectionNeedsTitle "just body text" "2025-01-15" @?= True
  ]

stripTitlePrefixesTests :: TestTree
stripTitlePrefixesTests = testGroup "stripTitlePrefixes"
  [ testCase "strips date and pipe prefix" $
      stripTitlePrefixes "2025-01-15 | My Title" @?= "My Title"
  , testCase "returns plain title unchanged" $
      stripTitlePrefixes "My Title" @?= "My Title"
  , testCase "strips leading emojis" $
      assertBool "should not start with emoji" $
        not (T.null (stripTitlePrefixes "Hello World"))
  ]

extractTrailingEmojisTests :: TestTree
extractTrailingEmojisTests = testGroup "extractTrailingEmojis"
  [ testCase "extracts emojis from H2 headings" $
      let content = "## \x1F4D6 Books\n## \x1F3AE Games\nbody"
          result = extractTrailingEmojis content
      in assertBool "should extract something" $ not (T.null result)
  , testCase "returns empty for no H2 headings" $
      extractTrailingEmojis "just body text" @?= ""
  , testCase "returns empty for H2 without emojis" $
      extractTrailingEmojis "## Plain Heading\nbody" @?= ""
  , testCase "excludes the Updates section heading" $
      let content = "## \x1F4D6 Books\n## \x1F504 Updates\nbody"
          result = extractTrailingEmojis content
      in do
          assertBool "should contain book emoji" $ T.isInfixOf "\x1F4D6" result
          assertBool "should not contain updates emoji" $ not $ T.isInfixOf "\x1F504" result
  ]

extractHeadingEmojisTests :: TestTree
extractHeadingEmojisTests = testGroup "extractHeadingEmojis"
  [ testCase "extracts emoji from heading" $
      let result = extractHeadingEmojis "## \x1F4D6 Books"
      in assertBool "should contain book emoji" $ T.isInfixOf "\x1F4D6" result
  , testCase "returns empty for plain heading" $
      extractHeadingEmojis "## Plain" @?= ""
  ]

extractLinkedTitlesTests :: TestTree
extractLinkedTitlesTests = testGroup "extractLinkedTitles"
  [ testCase "extracts wikilink titles from list items" $
      let content = "---\ntitle: test\n---\n- [[books/foo|My Book]]\n- [[topics/bar|My Topic]]"
          titles = extractLinkedTitles content
      in assertBool "should find titles" $ length titles >= 2
  , testCase "returns empty for content without list items" $
      let titles = extractLinkedTitles "---\ntitle: test\n---\nNo list items"
      in titles @?= []
  , testCase "excludes list items from the Updates section" $
      let content = "---\ntitle: test\n---\n- [[books/foo|My Book]]\n\n## \x1F504 Updates\n### \x1F517 Internal Links\n- [[ai-blog/post|Vault Cache]]\n- [[other/file|Other File]]"
          titles = extractLinkedTitles content
      in do
          assertBool "should find book title" $ any (T.isInfixOf "My Book") titles
          assertBool "should not find update title" $ not $ any (T.isInfixOf "Vault Cache") titles
          assertBool "should not find other update" $ not $ any (T.isInfixOf "Other File") titles
          titles @?= ["My Book"]
  ]

parseReflectionTitleTests :: TestTree
parseReflectionTitleTests = testGroup "parseReflectionTitle"
  [ testCase "returns cleaned title" $
      parseReflectionTitle "My Creative Title" @?= "My Creative Title"
  , testCase "strips code fences" $
      parseReflectionTitle "```markdown\nMy Title\n```" @?= "My Title"
  , testCase "strips surrounding quotes" $
      parseReflectionTitle "\"My Title\"" @?= "My Title"
  , testCase "strips backticks" $
      parseReflectionTitle "`My Title`" @?= "My Title"
  , testCase "strips date prefix" $
      parseReflectionTitle "2025-01-15 | My Title" @?= "My Title"
  , testCase "takes first line only" $
      parseReflectionTitle "First Line\nSecond Line" @?= "First Line"
  ]

applyReflectionTitleTests :: TestTree
applyReflectionTitleTests = testGroup "applyReflectionTitle"
  [ testCase "updates frontmatter title" $
      let content = "---\ntitle: \"2025-01-15\"\n---\n# 2025-01-15\nbody"
          result = applyReflectionTitle content "2025-01-15" "Creative Part"
      in assertBool "should contain full title" $
           T.isInfixOf "2025-01-15 | Creative Part" result
  , testCase "updates H1 heading" $
      let content = "---\ntitle: \"2025-01-15\"\n---\n# 2025-01-15\nbody"
          result = applyReflectionTitle content "2025-01-15" "Creative Part"
      in assertBool "should have updated H1" $
           T.isInfixOf "# 2025-01-15 | Creative Part" result
  ]

buildReflectionTitlePromptTests :: TestTree
buildReflectionTitlePromptTests = testGroup "buildReflectionTitlePrompt"
  [ testCase "system prompt contains instructions" $
      let (system, _) = buildReflectionTitlePrompt ["Title A", "Title B"] ["Recent 1"]
      in assertBool "has instructions" $ T.isInfixOf "creative titles" system
  , testCase "user prompt contains linked titles" $
      let (_, user) = buildReflectionTitlePrompt ["Title A", "Title B"] []
      in do
          assertBool "has title A" $ T.isInfixOf "Title A" user
          assertBool "has title B" $ T.isInfixOf "Title B" user
  , testCase "system prompt contains recent examples" $
      let (system, _) = buildReflectionTitlePrompt [] ["Example Title"]
      in assertBool "has example" $ T.isInfixOf "Example Title" system
  ]
