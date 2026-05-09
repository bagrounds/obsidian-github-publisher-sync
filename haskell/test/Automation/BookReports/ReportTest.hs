module Automation.BookReports.ReportTest (tests) where

import qualified Data.Text as T
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)

import Automation.BookReports.Amazon (buildAffiliateUrlFromAsin, mkAffiliateTag)
import Automation.BookReports.Report
  ( assembleReportFile
  , bookFilePath
  , buildReportPrompt
  , reportSystemInstruction
  )
import Automation.BookReports.Types
  ( AmazonVariant (..)
  , mkAsin
  , mkBookSlug
  , mkBookTitle
  )

tests :: TestTree
tests = testGroup "BookReports.Report"
  [ testCase "system instruction enforces emoji-rich obsidian style" $ do
      assertBool "mentions emojis"        (T.isInfixOf "emoji" reportSystemInstruction)
      assertBool "mentions Obsidian-flavored markdown"
        (T.isInfixOf "Obsidian-flavored markdown" reportSystemInstruction)
      assertBool "warns against italicizing book titles"
        (T.isInfixOf "italics or quotes" reportSystemInstruction)
      assertBool "writes for TTS"         (T.isInfixOf "text-to-speech" reportSystemInstruction)

  , testCase "report prompt covers required sections" $ do
      title <- expectRight (mkBookTitle "Sapiens")
      tag <- expectRight (mkAffiliateTag "tag-20")
      asinValue <- expectRight (mkAsin "0451524934")
      let url = buildAffiliateUrlFromAsin tag asinValue
          prompt = buildReportPrompt title url Hardcover
      mapM_ (\heading -> assertBool ("mentions " <> T.unpack heading) (T.isInfixOf heading prompt))
        [ "TL;DR", "AI Summary", "Evaluation"
        , "Topics for Further Understanding", "FAQ"
        , "Book Recommendations", "Similar", "Contrasting", "Related"
        , "What Do You Think?"
        ]
      assertBool "warns not to include affiliate link"
        (T.isInfixOf "do not include" prompt || T.isInfixOf "do NOT" prompt)

  , testCase "bookFilePath places file under <vault>/books/<slug>.md" $ do
      slug <- expectRight (mkBookSlug "sapiens-a-brief-history")
      bookFilePath "/v" slug @?= "/v/books/sapiens-a-brief-history.md"

  , testCase "assembleReportFile wraps body with frontmatter, nav, attribution" $ do
      title <- expectRight (mkBookTitle "Sapiens")
      slug <- expectRight (mkBookSlug "sapiens")
      tag <- expectRight (mkAffiliateTag "tag-20")
      asinValue <- expectRight (mkAsin "0451524934")
      let url = buildAffiliateUrlFromAsin tag asinValue
          body = "# 📜 Sapiens\n\n📌 TL;DR.\n"
          today = read "2026-05-05"
          assembled = assembleReportFile title slug url Hardcover today "gemini-2.5-flash" body
      assertBool "frontmatter open"        (T.isInfixOf "---\nshare: true" assembled)
      assertBool "URL is canonical"        (T.isInfixOf "URL: https://bagrounds.org/books/sapiens" assembled)
      assertBool "title field"             (T.isInfixOf "title: Sapiens" assembled)
      assertBool "auto_generated true"     (T.isInfixOf "auto_generated: true" assembled)
      assertBool "model is recorded"       (T.isInfixOf "auto_generated_by: gemini-2.5-flash" assembled)
      assertBool "date is recorded"        (T.isInfixOf "auto_generated_on: 2026-05-05" assembled)
      assertBool "affiliate URL appears"   (T.isInfixOf "tag=tag-20" assembled)
      assertBool "amazon attribution line" (T.isInfixOf "As an Amazon Associate" assembled)
      assertBool "nav breadcrumb"          (T.isInfixOf "[Home]" assembled)
      assertBool "body H1 preserved"       (T.isInfixOf "# 📜 Sapiens" assembled)
  ]
  where
    expectRight (Right v) = pure v
    expectRight (Left e)  = error (T.unpack e)
