module Automation.BookReports.PendingStateTest (tests) where

import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=), assertBool)

import Automation.BookReports.PendingState
  ( PendingState (..)
  , clearPendingState
  , emptyPendingState
  , readPendingField
  , recordCompletedToday
  , writePendingState
  )
import Automation.BookReports.Types
  ( mkAsin
  , mkBookTitle
  , unAsin
  , unBookTitle
  )

tests :: TestTree
tests = testGroup "BookReports.PendingState"
  [ testCase "missing index file → empty state" $
      withSystemTempDirectory "book-reports-pending" $ \dir -> do
        state <- readPendingField (dir </> "missing.md")
        state @?= emptyPendingState

  , testCase "round-trip pending title and asin" $
      withSystemTempDirectory "book-reports-pending" $ \dir -> do
        let path = dir </> "index.md"
        TIO.writeFile path "---\ntitle: Books\n---\n\nbody\n"
        title <- expectRight (mkBookTitle "Sapiens")
        asinValue <- expectRight (mkAsin "0451524934")
        writePendingState path emptyPendingState
          { pendingTitle = Just title
          , pendingAsin  = Just asinValue
          }
        loaded <- readPendingField path
        fmap unBookTitle (pendingTitle loaded) @?= Just "Sapiens"
        fmap unAsin (pendingAsin loaded)       @?= Just "0451524934"

  , testCase "clearPendingState removes pending fields but keeps last_generated" $
      withSystemTempDirectory "book-reports-pending" $ \dir -> do
        let path = dir </> "index.md"
        TIO.writeFile path "---\ntitle: Books\n---\n\nbody\n"
        title <- expectRight (mkBookTitle "Sapiens")
        writePendingState path emptyPendingState { pendingTitle = Just title }
        clearPendingState path
        loaded <- readPendingField path
        pendingTitle loaded @?= Nothing
        pendingAsin loaded  @?= Nothing

  , testCase "recordCompletedToday clears pending and stores last_generated" $
      withSystemTempDirectory "book-reports-pending" $ \dir -> do
        let path = dir </> "index.md"
        TIO.writeFile path "---\ntitle: Books\n---\n\nbody\n"
        title <- expectRight (mkBookTitle "Sapiens")
        writePendingState path emptyPendingState { pendingTitle = Just title }
        recordCompletedToday path (read "2026-05-05")
        raw <- TIO.readFile path
        assertBool "frontmatter has last_generated"
          (T.isInfixOf "book_report_last_generated" raw)
        loaded <- readPendingField path
        pendingTitle loaded       @?= Nothing
        lastGeneratedOnDay loaded @?= Just (read "2026-05-05")
  ]
  where
    expectRight (Right v) = pure v
    expectRight (Left e)  = error (T.unpack e)
