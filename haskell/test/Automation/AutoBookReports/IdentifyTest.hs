{-# LANGUAGE OverloadedStrings #-}

module Automation.AutoBookReports.IdentifyTest (tests) where

import qualified Data.Text as T
import Test.Tasty
import Test.Tasty.HUnit

import Automation.AutoBookReports.Identify

tests :: TestTree
tests = testGroup "AutoBookReports.Identify"
  [ testGroup "buildIdentificationPrompt"
    [ testCase "lists known slugs as a bullet list" $ do
        let (sys, user) = buildIdentificationPrompt ["deep-work", "atomic-habits"] ["body text"]
        assertBool "user contains bullets" $
          T.isInfixOf "- deep-work" user && T.isInfixOf "- atomic-habits" user
        assertBool "system mentions slug rule" (T.isInfixOf "slug" sys)
    , testCase "indicates none when no known slugs" $ do
        let (_, user) = buildIdentificationPrompt [] ["body"]
        assertBool "shows (none)" (T.isInfixOf "(none)" user)
    , testCase "indicates none when no reflections" $ do
        let (_, user) = buildIdentificationPrompt ["foo"] []
        assertBool "shows no reflections placeholder" (T.isInfixOf "(no recent reflections)" user)
    , testCase "system instruction asks for JSON only" $ do
        let (sys, _) = buildIdentificationPrompt [] []
        assertBool "asks for JSON" (T.isInfixOf "JSON array" sys)
        assertBool "asks no prose" (T.isInfixOf "No prose" sys)
    ]

  , testGroup "parseIdentificationResponse"
    [ testCase "parses well-formed JSON array" $ do
        let raw = "[{\"title\":\"Foo\",\"author\":\"Bar\",\"context\":\"...\"}]"
        case parseIdentificationResponse raw of
          Right [c] -> do
            candidateTitle c @?= "Foo"
            candidateAuthor c @?= "Bar"
          other -> assertFailure ("expected one candidate, got " <> show other)

    , testCase "parses code-fenced JSON" $ do
        let raw = "```json\n[{\"title\":\"Foo\",\"author\":\"Bar\",\"context\":\"\"}]\n```"
        case parseIdentificationResponse raw of
          Right [_] -> pure ()
          other -> assertFailure ("expected one candidate, got " <> show other)

    , testCase "parses empty array" $
        parseIdentificationResponse "[]" @?= Right []

    , testCase "rejects non-array JSON" $
        case parseIdentificationResponse "{\"foo\":1}" of
          Left _ -> pure ()
          Right xs -> assertFailure ("expected Left, got " <> show xs)

    , testCase "rejects gibberish" $
        case parseIdentificationResponse "not json at all" of
          Left _ -> pure ()
          Right xs -> assertFailure ("expected Left, got " <> show xs)

    , testCase "skips entries with empty title" $ do
        let raw = "[{\"title\":\"\",\"author\":\"Bar\",\"context\":\"\"},{\"title\":\"Real\",\"author\":\"Person\",\"context\":\"\"}]"
        case parseIdentificationResponse raw of
          Right [c] -> candidateTitle c @?= "Real"
          other -> assertFailure ("expected one candidate, got " <> show other)

    , testCase "skips entries with empty author" $ do
        let raw = "[{\"title\":\"Foo\",\"author\":\"\",\"context\":\"\"}]"
        parseIdentificationResponse raw @?= Right []

    , testCase "context defaults to empty when omitted" $ do
        let raw = "[{\"title\":\"Foo\",\"author\":\"Bar\"}]"
        case parseIdentificationResponse raw of
          Right [c] -> candidateContext c @?= ""
          other -> assertFailure ("expected one candidate, got " <> show other)
    ]
  ]
