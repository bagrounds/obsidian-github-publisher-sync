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
import qualified Automation.BlueskyTest
import qualified Automation.MastodonTest
import qualified Automation.SocialPostingTest

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
  , Automation.BlueskyTest.tests
  , Automation.MastodonTest.tests
  , Automation.SocialPostingTest.tests
  ]
