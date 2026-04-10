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
import qualified Automation.DailyUpdatesTest
import qualified Automation.StaticGiscusTest
import qualified Automation.AiBlogLinksTest
import qualified Automation.AiFictionTest
import qualified Automation.DailyReflectionTest
import qualified Automation.PromptsTest
import qualified Automation.JsonTest
import qualified Automation.OgMetadataTest
import qualified Automation.ReflectionTitleTest
import qualified Automation.ObsidianSyncTest
import qualified Automation.TypesTest
import qualified Automation.PlatformTest
import qualified Automation.CredentialsTest
import qualified Automation.EmbedTest
import qualified Automation.ContextTest

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
  , Automation.DailyUpdatesTest.tests
  , Automation.StaticGiscusTest.tests
  , Automation.AiBlogLinksTest.tests
  , Automation.AiFictionTest.tests
  , Automation.DailyReflectionTest.tests
  , Automation.PromptsTest.tests
  , Automation.JsonTest.tests
  , Automation.ReflectionTitleTest.tests
  , Automation.OgMetadataTest.tests
  , Automation.ObsidianSyncTest.tests
  , Automation.TypesTest.tests
  , Automation.PlatformTest.tests
  , Automation.CredentialsTest.tests
  , Automation.EmbedTest.tests
  , Automation.ContextTest.tests
  ]
