module Automation.AiFictionTest (tests) where

import qualified Data.Text as T
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import Test.Tasty.QuickCheck (testProperty)
import qualified Test.Tasty.QuickCheck as QC

import Automation.AiFiction
import qualified Automation.Gemini as Gemini

tests :: TestTree
tests = testGroup "AiFiction"
  [ constantTests
  , stripForPromptTests
  , reflectionNeedsFictionTests
  , parseFictionResponseTests
  , buildFictionSignatureTests
  , applyFictionTests
  , propertyTests
  ]

--------------------------------------------------------------------------------
-- constants
--------------------------------------------------------------------------------

constantTests :: TestTree
constantTests = testGroup "constants"
  [ testCase "fictionSectionHeader" $
      fictionSectionHeader @?= "## 🤖🐲 AI Fiction"
  , testCase "defaultFictionModel" $
      defaultFictionModel @?= Gemini.Gemini25Flash
  ]

--------------------------------------------------------------------------------
-- stripForPrompt
--------------------------------------------------------------------------------

stripForPromptTests :: TestTree
stripForPromptTests = testGroup "stripForPrompt"
  [ testCase "strips frontmatter" $
      let content = "---\ntitle: My Post\n---\n# Heading\n\nBody text"
          result = stripForPrompt content
      in do
        assertBool "no frontmatter dashes" (not (T.isPrefixOf "---" result))
        assertBool "contains body" (T.isInfixOf "Body text" result)
  , testCase "returns body when no frontmatter" $
      let content = "# Heading\n\nBody text"
          result = stripForPrompt content
      in assertBool "contains body" (T.isInfixOf "Body text" result)
  , testCase "strips content after fiction section" $
      let content = "---\ntitle: Test\n---\n# Post\n\nGood stuff\n\n## 🤖🐲 AI Fiction\n\nFiction text"
          result = stripForPrompt content
      in do
        assertBool "contains good stuff" (T.isInfixOf "Good stuff" result)
        assertBool "no fiction text" (not (T.isInfixOf "Fiction text" result))
  , testCase "strips content after updates section" $
      let content = "---\ntitle: Test\n---\n# Post\n\nBody\n\n## 🔄 Updates\n\nUpdate text"
          result = stripForPrompt content
      in do
        assertBool "contains body" (T.isInfixOf "Body" result)
        assertBool "no update text" (not (T.isInfixOf "Update text" result))
  , testCase "strips content after tweet section" $
      let content = "---\ntitle: Test\n---\n# Post\n\nBody\n\n## 🐦 Tweet\n\nTweet embed"
          result = stripForPrompt content
      in do
        assertBool "contains body" (T.isInfixOf "Body" result)
        assertBool "no tweet embed" (not (T.isInfixOf "Tweet embed" result))
  , testCase "handles empty content" $
      stripForPrompt "" @?= ""
  , testCase "handles content with only frontmatter" $
      let content = "---\ntitle: Test\n---\n"
          result = stripForPrompt content
      in assertBool "result is empty or whitespace" (T.null (T.strip result))
  ]

--------------------------------------------------------------------------------
-- reflectionNeedsFiction
--------------------------------------------------------------------------------

reflectionNeedsFictionTests :: TestTree
reflectionNeedsFictionTests = testGroup "reflectionNeedsFiction"
  [ testCase "returns True when no fiction section" $
      reflectionNeedsFiction "# Post\n\nBody" @?= True
  , testCase "returns False when fiction section present" $
      reflectionNeedsFiction ("# Post\n\n" <> fictionSectionHeader <> "\n\nFiction") @?= False
  , testCase "returns True for empty content" $
      reflectionNeedsFiction "" @?= True
  ]

--------------------------------------------------------------------------------
-- parseFictionResponse
--------------------------------------------------------------------------------

parseFictionResponseTests :: TestTree
parseFictionResponseTests = testGroup "parseFictionResponse"
  [ testCase "strips markdown code fences" $
      parseFictionResponse "```markdown\nSome fiction\n```" @?= "Some fiction"
  , testCase "strips md code fences" $
      parseFictionResponse "```md\nSome fiction\n```" @?= "Some fiction"
  , testCase "strips plain code fences" $
      parseFictionResponse "```\nSome fiction\n```" @?= "Some fiction"
  , testCase "removes quotation marks" $
      parseFictionResponse "She said \"hello\" and he replied 'yes'" @?= "She said hello and he replied yes"
  , testCase "removes curly quotes" $
      parseFictionResponse "\x201cHello\x201d and \x2018world\x2019" @?= "Hello and world"
  , testCase "removes backticks" $
      parseFictionResponse "some `code` here" @?= "some code here"
  , testCase "strips fiction section header from response" $
      parseFictionResponse (fictionSectionHeader <> "\n\nFiction text") @?= "Fiction text"
  , testCase "strips leading and trailing whitespace" $
      parseFictionResponse "  \n  Fiction text  \n  " @?= "Fiction text"
  , testCase "handles already clean text" $
      parseFictionResponse "Clean fiction text" @?= "Clean fiction text"
  , testCase "handles empty input" $
      parseFictionResponse "" @?= ""
  ]

--------------------------------------------------------------------------------
-- buildFictionSignature
--------------------------------------------------------------------------------

buildFictionSignatureTests :: TestTree
buildFictionSignatureTests = testGroup "buildFictionSignature"
  [ testCase "formats model signature" $
      buildFictionSignature "gemini-2.5-flash" @?= "\n\n✍️ Written by gemini-2.5-flash"
  , testCase "formats custom model" $
      buildFictionSignature "gpt-4" @?= "\n\n✍️ Written by gpt-4"
  ]

--------------------------------------------------------------------------------
-- applyFiction
--------------------------------------------------------------------------------

applyFictionTests :: TestTree
applyFictionTests = testGroup "applyFiction"
  [ testCase "appends fiction at end when no insert point" $
      let content = "# Post\n\nBody text"
          result = applyFiction content "My fiction" Nothing
      in do
        assertBool "contains fiction header" (T.isInfixOf fictionSectionHeader result)
        assertBool "contains fiction text" (T.isInfixOf "My fiction" result)
        assertBool "contains original body" (T.isInfixOf "Body text" result)
  , testCase "inserts fiction before updates section" $
      let content = "# Post\n\nBody text\n\n## 🔄 Updates\n\nUpdate content"
          result = applyFiction content "My fiction" Nothing
      in do
        assertBool "fiction before updates" $
          let fIdx = T.length $ fst $ T.breakOn fictionSectionHeader result
              uIdx = T.length $ fst $ T.breakOn "## 🔄 Updates" result
          in fIdx < uIdx
        assertBool "contains updates" (T.isInfixOf "Update content" result)
  , testCase "inserts fiction before tweet section" $
      let content = "# Post\n\nBody text\n\n## 🐦 Tweet\n\nTweet embed"
          result = applyFiction content "My fiction" Nothing
      in do
        assertBool "fiction before tweet" $
          let fIdx = T.length $ fst $ T.breakOn fictionSectionHeader result
              tIdx = T.length $ fst $ T.breakOn "## 🐦 Tweet" result
          in fIdx < tIdx
  , testCase "includes model signature when provided" $
      let content = "# Post\n\nBody"
          result = applyFiction content "Fiction" (Just "gemini-2.5-flash")
      in assertBool "contains signature" (T.isInfixOf "✍️ Written by gemini-2.5-flash" result)
  , testCase "no signature when model is Nothing" $
      let content = "# Post\n\nBody"
          result = applyFiction content "Fiction" Nothing
      in assertBool "no signature" (not (T.isInfixOf "✍️ Written by" result))
  , testCase "handles empty content" $
      let result = applyFiction "" "Fiction" Nothing
      in assertBool "contains fiction" (T.isInfixOf "Fiction" result)
  ]

--------------------------------------------------------------------------------
-- property tests
--------------------------------------------------------------------------------

propertyTests :: TestTree
propertyTests = testGroup "properties"
  [ testProperty "parseFictionResponse never contains double quotes" $
      \(QC.ASCIIString s) ->
        not (T.any (== '"') (parseFictionResponse (T.pack s)))
  , testProperty "applyFiction always includes fiction section header" $
      \(QC.ASCIIString body) (QC.ASCIIString fiction) ->
        let content = T.pack body
            fic = T.pack fiction
            result = applyFiction content fic Nothing
        in T.isInfixOf fictionSectionHeader result
  , testProperty "reflectionNeedsFiction is False after applyFiction" $
      \(QC.ASCIIString body) ->
        let content = T.pack body
            result = applyFiction content "Some fiction" Nothing
        in not (reflectionNeedsFiction result)
  ]
