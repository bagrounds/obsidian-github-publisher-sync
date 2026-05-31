module Automation.AiFictionTest (tests) where

import Data.List (nub)
import qualified Data.List.NonEmpty as NE
import Data.List.NonEmpty (NonEmpty ((:|)))
import Data.Time (LocalTime (..), TimeOfDay (..), fromGregorian, addDays)
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
  , fictionModelPoolTests
  , selectFictionModelChainTests
  , fictionEligibilityCutoffTests
  , stripForPromptTests
  , reflectionNeedsFictionTests
  , parseFictionResponseTests
  , buildFictionSignatureTests
  , applyFictionTests
  , propertyTests
  ]

constantTests :: TestTree
constantTests = testGroup "constants"
  [ testCase "fictionSectionHeader" $
      fictionSectionHeader @?= "## 🤖🐲 AI Fiction"
  , testCase "defaultFictionModel" $
      defaultFictionModel @?= Gemini.Gemini25Flash
  ]

fictionModelPoolTests :: TestTree
fictionModelPoolTests = testGroup "fictionModelPool"
  [ testCase "contains more than one model to rotate through" $
      assertBool "pool has at least two models" (length (NE.toList fictionModelPool) >= 2)
  , testCase "has no duplicate models" $
      let models = NE.toList fictionModelPool
      in length (nub models) @?= length models
  , testCase "every pool model is a known Gemini text model" $
      assertBool "all pool models are known" $
        all (`elem` Gemini.knownModels) (NE.toList fictionModelPool)
  , testCase "does not include the image-generation model" $
      assertBool "no image model in pool" $
        Gemini.Gemini31FlashImage `notElem` NE.toList fictionModelPool
  ]

selectFictionModelChainTests :: TestTree
selectFictionModelChainTests = testGroup "selectFictionModelChain"
  [ testCase "chain contains every model in the pool (full fallback)" $
      let chain = selectFictionModelChain (fromGregorian 2026 5 27) fictionModelPool
      in nub (NE.toList chain) `sameElements` NE.toList fictionModelPool
  , testCase "selection is deterministic for a given day" $
      let day = fromGregorian 2026 5 27
          a = selectFictionModelChain day fictionModelPool
          b = selectFictionModelChain day fictionModelPool
      in NE.head a @?= NE.head b
  , testCase "consecutive days rotate to a different primary model" $
      let d0 = fromGregorian 2026 5 27
          d1 = fromGregorian 2026 5 28
      in assertBool "different primary model on next day"
           (NE.head (selectFictionModelChain d0 fictionModelPool)
              /= NE.head (selectFictionModelChain d1 fictionModelPool))
  , testCase "rotation cycles back after pool-length days" $
      let poolLen = length (NE.toList fictionModelPool)
          d0 = fromGregorian 2026 5 27
          dCycle = addDays (toInteger poolLen) d0
      in NE.head (selectFictionModelChain d0 fictionModelPool)
           @?= NE.head (selectFictionModelChain dCycle fictionModelPool)
  , testCase "single-model pool always selects that model" $
      let pool = Gemini.Gemini25Flash :| []
          chain = selectFictionModelChain (fromGregorian 2026 5 27) pool
      in NE.toList chain @?= [Gemini.Gemini25Flash]
  ]
  where
    sameElements xs ys = do
      length xs @?= length ys
      assertBool "same elements" (all (`elem` ys) xs && all (`elem` xs) ys)

fictionEligibilityCutoffTests :: TestTree
fictionEligibilityCutoffTests = testGroup "fictionEligibilityCutoff"
  [ testCase "cutoff for a mid-month day is that day at 22:00:00" $
      fictionEligibilityCutoff (fromGregorian 2026 4 29)
        @?= LocalTime (fromGregorian 2026 4 29) (TimeOfDay 22 0 0)
  , testCase "cutoff for the first of a month is that day at 22:00:00" $
      fictionEligibilityCutoff (fromGregorian 2026 5 1)
        @?= LocalTime (fromGregorian 2026 5 1) (TimeOfDay 22 0 0)
  , testCase "cutoff for January 1 is that day at 22:00:00" $
      fictionEligibilityCutoff (fromGregorian 2027 1 1)
        @?= LocalTime (fromGregorian 2027 1 1) (TimeOfDay 22 0 0)
  , testCase "10 PM exactly on the day is eligible" $
      LocalTime (fromGregorian 2026 4 29) (TimeOfDay 22 0 0)
        >= fictionEligibilityCutoff (fromGregorian 2026 4 29)
        @?= True
  , testCase "one second before cutoff on the day is not eligible" $
      LocalTime (fromGregorian 2026 4 29) (TimeOfDay 21 59 59)
        >= fictionEligibilityCutoff (fromGregorian 2026 4 29)
        @?= False
  , testCase "midnight after the day is eligible" $
      LocalTime (fromGregorian 2026 4 30) (TimeOfDay 0 0 0)
        >= fictionEligibilityCutoff (fromGregorian 2026 4 29)
        @?= True
  , testCase "next day at noon is eligible" $
      LocalTime (fromGregorian 2026 4 30) (TimeOfDay 12 0 0)
        >= fictionEligibilityCutoff (fromGregorian 2026 4 29)
        @?= True
  , testCase "same day at noon is not yet eligible" $
      LocalTime (fromGregorian 2026 4 29) (TimeOfDay 12 0 0)
        >= fictionEligibilityCutoff (fromGregorian 2026 4 29)
        @?= False
  ]

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

reflectionNeedsFictionTests :: TestTree
reflectionNeedsFictionTests = testGroup "reflectionNeedsFiction"
  [ testCase "returns True when no fiction section" $
      reflectionNeedsFiction "# Post\n\nBody" @?= True
  , testCase "returns False when fiction section present" $
      reflectionNeedsFiction ("# Post\n\n" <> fictionSectionHeader <> "\n\nFiction") @?= False
  , testCase "returns True for empty content" $
      reflectionNeedsFiction "" @?= True
  ]

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

buildFictionSignatureTests :: TestTree
buildFictionSignatureTests = testGroup "buildFictionSignature"
  [ testCase "formats model signature" $
      buildFictionSignature "gemini-2.5-flash" @?= "\n\n✍️ Written by gemini-2.5-flash"
  , testCase "formats custom model" $
      buildFictionSignature "gpt-4" @?= "\n\n✍️ Written by gpt-4"
  ]

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

propertyTests :: TestTree
propertyTests = testGroup "properties"
  [ testProperty "parseFictionResponse never contains double quotes" $
      \(QC.ASCIIString string) ->
        not (T.any (== '"') (parseFictionResponse (T.pack string)))
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
