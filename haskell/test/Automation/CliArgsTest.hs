module Automation.CliArgsTest (tests) where

import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))
import Test.Tasty.QuickCheck (testProperty)
import qualified Test.QuickCheck as QC
import qualified Data.Text as T

import Automation.CliArgs (CliArgs (..), parseCliArgs)

tests :: TestTree
tests = testGroup "CliArgs"
  [ parseCliArgsTests
  , properties
  ]

parseCliArgsTests :: TestTree
parseCliArgsTests = testGroup "parseCliArgs"
  [ testCase "empty args produces default CliArgs" $
      parseCliArgs [] @?= CliArgs Nothing Nothing

  , testCase "parses --hour flag" $
      parseCliArgs ["--hour", "5"] @?= CliArgs (Just 5) Nothing

  , testCase "parses --task flag" $
      parseCliArgs ["--task", "social-posting"] @?= CliArgs Nothing (Just "social-posting")

  , testCase "parses both --hour and --task" $
      parseCliArgs ["--hour", "3", "--task", "ai-fiction"] @?= CliArgs (Just 3) (Just "ai-fiction")

  , testCase "parses flags in reverse order" $
      parseCliArgs ["--task", "internal-linking", "--hour", "14"] @?= CliArgs (Just 14) (Just "internal-linking")

  , testCase "ignores unknown flags" $
      parseCliArgs ["--unknown", "foo", "--hour", "7"] @?= CliArgs (Just 7) Nothing

  , testCase "last --hour wins when duplicated" $
      parseCliArgs ["--hour", "3", "--hour", "9"] @?= CliArgs (Just 9) Nothing

  , testCase "last --task wins when duplicated" $
      parseCliArgs ["--task", "a", "--task", "b"] @?= CliArgs Nothing (Just "b")

  , testCase "ignores trailing --hour without value" $
      parseCliArgs ["--task", "foo", "--hour"] @?= CliArgs Nothing (Just "foo")

  , testCase "ignores trailing --task without value" $
      parseCliArgs ["--hour", "12", "--task"] @?= CliArgs (Just 12) Nothing
  ]

properties :: TestTree
properties = testGroup "properties"
  [ testProperty "parsed hour override matches input" $
      QC.forAll (QC.choose (0, 23)) $ \hour ->
        cliHourOverride (parseCliArgs ["--hour", show hour]) == Just hour

  , testProperty "parsed task override matches input" $
      QC.forAll genTaskName $ \taskName ->
        cliTaskOverride (parseCliArgs ["--task", taskName]) == Just (T.pack taskName)
  ]

genTaskName :: QC.Gen String
genTaskName = QC.listOf1 (QC.elements (['a'..'z'] <> ['-']))
