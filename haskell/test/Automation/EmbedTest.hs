module Automation.EmbedTest (tests) where

import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))

import qualified Automation.Platforms.Bluesky as Bluesky

tests :: TestTree
tests = testGroup "Embed"
  [ embedResultTests
  ]

embedResultTests :: TestTree
embedResultTests = testGroup "EmbedResult"
  [ testCase "EmbedResult preserves HTML content" $
      Bluesky.erHtml (Bluesky.EmbedResult "<div>hello</div>") @?= "<div>hello</div>"

  , testCase "EmbedResult equality works" $
      Bluesky.EmbedResult "<p>a</p>" @?= Bluesky.EmbedResult "<p>a</p>"
  ]
