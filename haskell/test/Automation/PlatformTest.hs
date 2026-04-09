module Automation.PlatformTest (tests) where

import qualified Data.Text as T
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)
import Test.Tasty.QuickCheck (testProperty)
import qualified Test.QuickCheck as QC

import Automation.Platform (PlatformLimits (..), updatesSectionHeader)
import Automation.Platforms.Bluesky
  ( blueskyLimits
  , blueskyDisplayName
  , blueskySectionHeader
  , blueskyOembedInitialDelayMs
  , blueskyOembedRetryDelayMs
  )
import Automation.Platforms.Mastodon
  ( mastodonLimits
  , mastodonDisplayName
  , mastodonSectionHeader
  )
import Automation.Platforms.Twitter
  ( twitterLimits
  , twitterHandle
  , twitterDisplayName
  , tweetSectionHeader
  )

tests :: TestTree
tests = testGroup "Platform"
  [ limitsTests
  , displayNameTests
  , sectionHeaderTests
  , embedDelayTests
  ]

limitsTests :: TestTree
limitsTests = testGroup "PlatformLimits"
  [ testCase "twitterLimits has correct max characters" $
      platformMaxCharacters twitterLimits @?= 280

  , testCase "twitterLimits has URL count length" $
      platformUrlCountLength twitterLimits @?= Just 23

  , testCase "blueskyLimits has correct max characters" $
      platformMaxCharacters blueskyLimits @?= 300

  , testCase "blueskyLimits has no URL count length" $
      platformUrlCountLength blueskyLimits @?= Nothing

  , testCase "mastodonLimits has correct max characters" $
      platformMaxCharacters mastodonLimits @?= 500

  , testCase "mastodonLimits has no URL count length" $
      platformUrlCountLength mastodonLimits @?= Nothing

  , testProperty "all platform limits have positive max characters" $
      QC.forAll (QC.elements [twitterLimits, blueskyLimits, mastodonLimits]) $
        \limits -> platformMaxCharacters limits > 0

  , testProperty "twitter URL count length is less than max characters" $
      case platformUrlCountLength twitterLimits of
        Just urlLen -> urlLen < platformMaxCharacters twitterLimits
        Nothing -> True

  , testProperty "mastodon has highest character limit" $
      QC.forAll (QC.elements [twitterLimits, blueskyLimits]) $
        \limits -> platformMaxCharacters limits < platformMaxCharacters mastodonLimits
  ]

displayNameTests :: TestTree
displayNameTests = testGroup "display names"
  [ testCase "twitterHandle is non-empty" $
      assertBool "twitterHandle should be non-empty" (not (T.null twitterHandle))

  , testCase "all display names are consistent" $
      assertBool "display names should all match"
        (twitterDisplayName == blueskyDisplayName
          && blueskyDisplayName == mastodonDisplayName)
  ]

sectionHeaderTests :: TestTree
sectionHeaderTests = testGroup "section headers"
  [ testCase "tweetSectionHeader starts with ##" $
      assertBool "should start with ##" (T.isPrefixOf "## " tweetSectionHeader)

  , testCase "blueskySectionHeader starts with ##" $
      assertBool "should start with ##" (T.isPrefixOf "## " blueskySectionHeader)

  , testCase "mastodonSectionHeader starts with ##" $
      assertBool "should start with ##" (T.isPrefixOf "## " mastodonSectionHeader)

  , testCase "updatesSectionHeader starts with ##" $
      assertBool "should start with ##" (T.isPrefixOf "## " updatesSectionHeader)

  , testCase "all section headers are distinct" $
      let headers = [tweetSectionHeader, blueskySectionHeader, mastodonSectionHeader, updatesSectionHeader]
          unique = foldl (\acc x -> if x `elem` acc then acc else acc <> [x]) [] headers
      in assertBool "all headers should be unique" (length headers == length unique)
  ]

embedDelayTests :: TestTree
embedDelayTests = testGroup "embed delays"
  [ testCase "blueskyOembedInitialDelayMs is non-negative" $
      assertBool "should be non-negative" (blueskyOembedInitialDelayMs >= 0)

  , testCase "blueskyOembedRetryDelayMs is positive" $
      assertBool "should be positive" (blueskyOembedRetryDelayMs > 0)
  ]
