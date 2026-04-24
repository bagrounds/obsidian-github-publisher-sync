module Automation.PlatformTest (tests) where

import qualified Data.Text as T
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import Test.Tasty.QuickCheck (testProperty)
import qualified Test.QuickCheck as QC

import Automation.Platform (PlatformLimits (..), updatesSectionHeader)
import qualified Automation.Platforms.Bluesky as Bluesky
import qualified Automation.Platforms.Mastodon as Mastodon
import qualified Automation.Platforms.Twitter as Twitter

tests :: TestTree
tests = testGroup "Platform"
  [ limitsTests
  , displayNameTests
  , sectionHeaderTests
  , embedDelayTests
  ]

limitsTests :: TestTree
limitsTests = testGroup "PlatformLimits"
  [ testCase "Twitter.limits has correct max characters" $
      platformMaxCharacters Twitter.limits @?= 280

  , testCase "Twitter.limits has URL count length" $
      platformUrlCountLength Twitter.limits @?= Just 23

  , testCase "Bluesky.limits has correct max characters" $
      platformMaxCharacters Bluesky.limits @?= 300

  , testCase "Bluesky.limits has no URL count length" $
      platformUrlCountLength Bluesky.limits @?= Nothing

  , testCase "Mastodon.limits has correct max characters" $
      platformMaxCharacters Mastodon.limits @?= 500

  , testCase "Mastodon.limits has no URL count length" $
      platformUrlCountLength Mastodon.limits @?= Nothing

  , testProperty "all platform limits have positive max characters" $
      QC.forAll (QC.elements [Twitter.limits, Bluesky.limits, Mastodon.limits]) $
        \limits -> platformMaxCharacters limits > 0

  , testProperty "twitter URL count length is less than max characters" $
      case platformUrlCountLength Twitter.limits of
        Just urlLen -> urlLen < platformMaxCharacters Twitter.limits
        Nothing -> True

  , testProperty "mastodon has highest character limit" $
      QC.forAll (QC.elements [Twitter.limits, Bluesky.limits]) $
        \limits -> platformMaxCharacters limits < platformMaxCharacters Mastodon.limits
  ]

displayNameTests :: TestTree
displayNameTests = testGroup "display names"
  [ testCase "Twitter.twitterHandle is non-empty" $
      assertBool "Twitter.twitterHandle should be non-empty" (not (T.null Twitter.twitterHandle))

  , testCase "all display names are consistent" $
      assertBool "display names should all match"
        (Twitter.displayName == Bluesky.displayName
          && Bluesky.displayName == Mastodon.displayName)
  ]

sectionHeaderTests :: TestTree
sectionHeaderTests = testGroup "section headers"
  [ testCase "Twitter.sectionHeader starts with ##" $
      assertBool "should start with ##" (T.isPrefixOf "## " Twitter.sectionHeader)

  , testCase "Bluesky.sectionHeader starts with ##" $
      assertBool "should start with ##" (T.isPrefixOf "## " Bluesky.sectionHeader)

  , testCase "Mastodon.sectionHeader starts with ##" $
      assertBool "should start with ##" (T.isPrefixOf "## " Mastodon.sectionHeader)

  , testCase "updatesSectionHeader starts with ##" $
      assertBool "should start with ##" (T.isPrefixOf "## " updatesSectionHeader)

  , testCase "all section headers are distinct" $
      let headers = [Twitter.sectionHeader, Bluesky.sectionHeader, Mastodon.sectionHeader, updatesSectionHeader]
          unique = foldl (\acc x -> if x `elem` acc then acc else acc <> [x]) [] headers
      in assertBool "all headers should be unique" (length headers == length unique)
  ]

embedDelayTests :: TestTree
embedDelayTests = testGroup "embed delays"
  [ testCase "Bluesky.defaultOEmbedConfig initialDelayMilliseconds is non-negative" $
      assertBool "should be non-negative" (Bluesky.initialDelayMilliseconds Bluesky.defaultOEmbedConfig >= 0)

  , testCase "Bluesky.defaultOEmbedConfig retryDelayMilliseconds is positive" $
      assertBool "should be positive" (Bluesky.retryDelayMilliseconds Bluesky.defaultOEmbedConfig > 0)
  ]
