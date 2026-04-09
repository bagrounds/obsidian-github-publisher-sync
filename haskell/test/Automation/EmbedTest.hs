module Automation.EmbedTest (tests) where

import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))

import Automation.Platforms.Bluesky (EmbedResult (..))

tests :: TestTree
tests = testGroup "Embed"
  [ embedResultTests
  ]

embedResultTests :: TestTree
embedResultTests = testGroup "EmbedResult"
  [ testCase "EmbedResult preserves HTML content" $
      erHtml (EmbedResult "<div>hello</div>") @?= "<div>hello</div>"

  , testCase "EmbedResult equality works" $
      EmbedResult "<p>a</p>" @?= EmbedResult "<p>a</p>"
  ]
