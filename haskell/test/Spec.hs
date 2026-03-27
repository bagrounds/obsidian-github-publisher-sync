module Main (main) where

import Test.Tasty (defaultMain, testGroup)

import qualified Automation.SchedulerTest
import qualified Automation.TextTest
import qualified Automation.HtmlTest
import qualified Automation.FrontmatterTest
import qualified Automation.RetryTest
import qualified Automation.EnvTest
import qualified Automation.BlogSeriesConfigTest
import qualified Automation.EmbedSectionTest
import qualified Automation.BlogPromptTest
import qualified Automation.BlogSeriesTest
import qualified Automation.BlogImageTest
import qualified Automation.InternalLinkingTest

main :: IO ()
main = defaultMain $ testGroup "Automation"
  [ Automation.SchedulerTest.tests
  , Automation.TextTest.tests
  , Automation.HtmlTest.tests
  , Automation.FrontmatterTest.tests
  , Automation.RetryTest.tests
  , Automation.EnvTest.tests
  , Automation.BlogSeriesConfigTest.tests
  , Automation.EmbedSectionTest.tests
  , Automation.BlogPromptTest.tests
  , Automation.BlogSeriesTest.tests
  , Automation.BlogImageTest.tests
  , Automation.InternalLinkingTest.tests
  ]
