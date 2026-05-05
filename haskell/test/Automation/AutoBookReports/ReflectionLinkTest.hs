{-# LANGUAGE OverloadedStrings #-}

module Automation.AutoBookReports.ReflectionLinkTest (tests) where

import qualified Data.Text as T
import Test.Tasty
import Test.Tasty.HUnit

import Automation.AutoBookReports.ReflectionLink

tests :: TestTree
tests = testGroup "AutoBookReports.ReflectionLink"
  [ testGroup "buildBookListItem"
    [ testCase "uses 🆕📚 prefix and wikilink" $
        buildBookListItem "deep-work" "Deep Work"
          @?= "- 🆕📚 Auto-generated report on [[books/deep-work|Deep Work]]"
    ]

  , testGroup "insertBookLink"
    [ testCase "appends inside an existing Books section" $ do
        let content = T.unlines
              [ "# 2026-05-05"
              , ""
              , "## [📚 Books](../books/index.md)"
              , "- ⏯️ Continuing [[books/foo|Foo]]"
              , ""
              , "## [📺 Videos](../videos/index.md)"
              , "- something"
              ]
            updated = insertBookLink content "deep-work" "Deep Work"
        assertBool "contains new item" $
          T.isInfixOf "- 🆕📚 Auto-generated report on [[books/deep-work|Deep Work]]" updated
        assertBool "preserves Foo entry" $ T.isInfixOf "- ⏯️ Continuing [[books/foo|Foo]]" updated
        assertBool "preserves Videos section" $ T.isInfixOf "## [📺 Videos]" updated

    , testCase "is idempotent for an already-linked slug" $ do
        let withLink = T.unlines
              [ "## [📚 Books](../books/index.md)"
              , "- 🆕📚 Auto-generated report on [[books/deep-work|Deep Work]]"
              ]
            updated = insertBookLink withLink "deep-work" "Deep Work"
        updated @?= withLink

    , testCase "creates section when absent" $ do
        let content = "# 2026-05-05\n\n(no books section yet)\n"
            updated = insertBookLink content "deep-work" "Deep Work"
        assertBool "now contains section" $ T.isInfixOf booksSectionHeading updated
        assertBool "now contains item" $
          T.isInfixOf "[[books/deep-work|Deep Work]]" updated
    ]
  ]
