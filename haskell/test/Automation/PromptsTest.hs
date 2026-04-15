module Automation.PromptsTest (tests) where

import Data.Char (isAlphaNum, isAscii)
import qualified Data.Text as T
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import Test.Tasty.QuickCheck (testProperty)
import qualified Test.Tasty.QuickCheck as QC

import Automation.Prompts
import Automation.TestGenerators (testUrl, testTitle)
import qualified Automation.Platforms.Bluesky as Bluesky
import Automation.Platform (PlatformLimits (..))
import Automation.Reflection (ReflectionData (..))
import Automation.Title (unTitle)
import Automation.Url (unUrl)

tests :: TestTree
tests = testGroup "Prompts"
  [ constantTests
  , calculateQuestionBudgetTests
  , stripSubtitleTests
  , parseQuestionAndTagsTests
  , assemblePostTests
  , propertyTests
  ]

sampleReflection :: ReflectionData
sampleReflection = ReflectionData
  { rdDate                = "2026-04-01"
  , rdTitle               = testTitle "2026-04-01 | My Reflection"
  , rdUrl                 = testUrl "https://bagrounds.org/reflections/2026-04-01"
  , rdBody                = "Some reflection body content"
  , rdFilePath            = "reflections/2026-04-01.md"
  , rdHasTweetSection     = False
  , rdHasBlueskySection   = False
  , rdHasMastodonSection  = False
  }

--------------------------------------------------------------------------------
-- constants
--------------------------------------------------------------------------------

constantTests :: TestTree
constantTests = testGroup "constants"
  [ testCase "aiQuestionPrefix" $
      aiQuestionPrefix @?= "#AI Q: "
  ]

--------------------------------------------------------------------------------
-- calculateQuestionBudget
--------------------------------------------------------------------------------

calculateQuestionBudgetTests :: TestTree
calculateQuestionBudgetTests = testGroup "calculateQuestionBudget"
  [ testCase "returns positive budget for typical reflection" $
      let budget = calculateQuestionBudget sampleReflection
      in assertBool "budget is positive" (budget > 0)
  , testCase "budget decreases with longer title" $
      let shortTitle = sampleReflection { rdTitle = testTitle "Short" }
          longTitle = sampleReflection { rdTitle = testTitle (T.replicate 100 "x") }
      in assertBool "short title has more budget" $
        calculateQuestionBudget shortTitle > calculateQuestionBudget longTitle
  , testCase "budget decreases with longer URL" $
      let shortUrl = sampleReflection { rdUrl = testUrl "https://x.com/a" }
          longUrl = sampleReflection { rdUrl = testUrl ("https://example.com/" <> T.replicate 100 "x") }
      in assertBool "short URL has more budget" $
        calculateQuestionBudget shortUrl > calculateQuestionBudget longUrl
  , testCase "budget has minimum of 30" $
      let extreme = sampleReflection
            { rdTitle = testTitle (T.replicate 200 "x")
            , rdUrl = testUrl ("https://example.com/" <> T.replicate 200 "x")
            }
      in calculateQuestionBudget extreme @?= 30
  , testCase "budget is at most blueskyMaxLength" $
      let budget = calculateQuestionBudget sampleReflection
      in assertBool "budget within max" (budget <= platformMaxCharacters Bluesky.limits)
  ]

--------------------------------------------------------------------------------
-- stripSubtitle
--------------------------------------------------------------------------------

stripSubtitleTests :: TestTree
stripSubtitleTests = testGroup "stripSubtitle"
  [ testCase "strips subtitle after colon" $
      stripSubtitle "Main Title: A Subtitle" @?= "Main Title"
  , testCase "returns full title when no colon" $
      stripSubtitle "My Title" @?= "My Title"
  , testCase "handles colon at start" $
      stripSubtitle ": Only Subtitle" @?= ": Only Subtitle"
  , testCase "strips at first colon" $
      stripSubtitle "A: B: C" @?= "A"
  , testCase "trims whitespace from shortened title" $
      stripSubtitle "  Title  : Subtitle" @?= "Title"
  , testCase "handles empty string" $
      stripSubtitle "" @?= ""
  ]

--------------------------------------------------------------------------------
-- parseQuestionAndTags
--------------------------------------------------------------------------------

parseQuestionAndTagsTests :: TestTree
parseQuestionAndTagsTests = testGroup "parseQuestionAndTags"
  [ testCase "parses question and tags from two lines" $
      parseQuestionAndTags "What is life?\nTag1 | Tag2" @?= ("What is life?", "Tag1 | Tag2")
  , testCase "returns question only for single line" $
      parseQuestionAndTags "Just a question?" @?= ("Just a question?", "")
  , testCase "returns empty pair for empty input" $
      parseQuestionAndTags "" @?= ("", "")
  , testCase "ignores extra lines" $
      parseQuestionAndTags "Q?\nTags\nExtra stuff" @?= ("Q?", "Tags")
  , testCase "strips whitespace from lines" $
      parseQuestionAndTags "  Question?  \n  Tags  " @?= ("Question?", "Tags")
  , testCase "skips blank lines" $
      parseQuestionAndTags "\n\nQuestion?\n\nTags" @?= ("Question?", "Tags")
  ]

--------------------------------------------------------------------------------
-- assemblePost
--------------------------------------------------------------------------------

assemblePostTests :: TestTree
assemblePostTests = testGroup "assemblePost"
  [ testCase "assembles full post with question and tags" $
      let result = assemblePost "My question?\nTag1 | Tag2" sampleReflection
      in do
        assertBool "contains title" (T.isInfixOf (unTitle (rdTitle sampleReflection)) result)
        assertBool "contains question" (T.isInfixOf "My question?" result)
        assertBool "contains AI prefix" (T.isInfixOf aiQuestionPrefix result)
        assertBool "contains tags" (T.isInfixOf "Tag1 | Tag2" result)
        assertBool "contains URL" (T.isInfixOf (unUrl (rdUrl sampleReflection)) result)
  , testCase "assembles post without question" $
      let result = assemblePost "" sampleReflection
      in do
        assertBool "contains title" (T.isInfixOf (unTitle (rdTitle sampleReflection)) result)
        assertBool "contains URL" (T.isInfixOf (unUrl (rdUrl sampleReflection)) result)
        assertBool "no AI prefix" (not (T.isInfixOf aiQuestionPrefix result))
  , testCase "assembles post with question but no tags" $
      let result = assemblePost "Question only?" sampleReflection
      in do
        assertBool "contains question" (T.isInfixOf "Question only?" result)
        assertBool "contains AI prefix" (T.isInfixOf aiQuestionPrefix result)
  , testCase "title appears first" $
      let result = assemblePost "Q?\nTags" sampleReflection
          titleIdx = T.length $ fst $ T.breakOn (unTitle (rdTitle sampleReflection)) result
          urlIdx = T.length $ fst $ T.breakOn (unUrl (rdUrl sampleReflection)) result
      in assertBool "title before URL" (titleIdx < urlIdx)
  ]

--------------------------------------------------------------------------------
-- property tests
--------------------------------------------------------------------------------

propertyTests :: TestTree
propertyTests = testGroup "properties"
  [ testProperty "calculateQuestionBudget always at least 30" $
      \(QC.ASCIIString title) (QC.ASCIIString url) ->
        let titleText = let t = T.pack title in if T.null (T.strip t) then "x" else t
            urlSuffix = filter isUnreservedUrlChar url
            urlText = "https://example.com/" <> T.pack urlSuffix
            rd = sampleReflection { rdTitle = testTitle titleText, rdUrl = testUrl urlText }
        in calculateQuestionBudget rd >= 30
  , testProperty "assemblePost always contains URL" $
      \(QC.ASCIIString modelOutput) ->
        let result = assemblePost (T.pack modelOutput) sampleReflection
        in T.isInfixOf (unUrl (rdUrl sampleReflection)) result
  , testProperty "assemblePost always contains title" $
      \(QC.ASCIIString modelOutput) ->
        let result = assemblePost (T.pack modelOutput) sampleReflection
        in T.isInfixOf (unTitle (rdTitle sampleReflection)) result
  , testProperty "stripSubtitle result is never longer than input" $
      \(QC.ASCIIString s) ->
        let txt = T.pack s
        in T.length (stripSubtitle txt) <= T.length txt
  ]

isUnreservedUrlChar :: Char -> Bool
isUnreservedUrlChar c = isAscii c && (isAlphaNum c || c `elem` ("-._~" :: String))
