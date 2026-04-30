module Automation.ReflectionTest (tests) where

import Data.Time (LocalTime (..), TimeOfDay (..), fromGregorian)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))

import Automation.Reflection (eligibleReflectionDays)

tests :: TestTree
tests = testGroup "Reflection"
  [ eligibleReflectionDaysTests
  ]

eligibleReflectionDaysTests :: TestTree
eligibleReflectionDaysTests = testGroup "eligibleReflectionDays"
  [ testCase "today is included when today's cutoff has passed" $
      let localNow = LocalTime (fromGregorian 2026 4 29) (TimeOfDay 22 30 0)
          cutoff day = LocalTime day (TimeOfDay 22 0 0)
      in eligibleReflectionDays localNow cutoff @?=
           [ fromGregorian 2026 4 29
           , fromGregorian 2026 4 28
           , fromGregorian 2026 4 27
           , fromGregorian 2026 4 26
           , fromGregorian 2026 4 25
           ]

  , testCase "today is excluded when today's cutoff has not yet passed" $
      let localNow = LocalTime (fromGregorian 2026 4 29) (TimeOfDay 21 59 59)
          cutoff day = LocalTime day (TimeOfDay 22 0 0)
      in eligibleReflectionDays localNow cutoff @?=
           [ fromGregorian 2026 4 28
           , fromGregorian 2026 4 27
           , fromGregorian 2026 4 26
           , fromGregorian 2026 4 25
           ]

  , testCase "at exactly the cutoff time, today is eligible" $
      let localNow = LocalTime (fromGregorian 2026 4 29) (TimeOfDay 22 0 0)
          cutoff day = LocalTime day (TimeOfDay 22 0 0)
      in eligibleReflectionDays localNow cutoff @?=
           [ fromGregorian 2026 4 29
           , fromGregorian 2026 4 28
           , fromGregorian 2026 4 27
           , fromGregorian 2026 4 26
           , fromGregorian 2026 4 25
           ]

  , testCase "one second before today's cutoff, today is not eligible" $
      let localNow = LocalTime (fromGregorian 2026 4 29) (TimeOfDay 21 59 59)
          cutoff day = LocalTime day (TimeOfDay 22 0 0)
          result = eligibleReflectionDays localNow cutoff
      in elem (fromGregorian 2026 4 29) result @?= False

  , testCase "candidate window is exactly 5 days when all are eligible" $
      let localNow = LocalTime (fromGregorian 2026 4 29) (TimeOfDay 22 30 0)
          cutoff day = LocalTime day (TimeOfDay 22 0 0)
      in length (eligibleReflectionDays localNow cutoff) @?= 5

  , testCase "days are returned newest-first" $
      let localNow = LocalTime (fromGregorian 2026 4 29) (TimeOfDay 23 0 0)
          cutoff day = LocalTime day (TimeOfDay 22 0 0)
      in eligibleReflectionDays localNow cutoff @?=
           [ fromGregorian 2026 4 29
           , fromGregorian 2026 4 28
           , fromGregorian 2026 4 27
           , fromGregorian 2026 4 26
           , fromGregorian 2026 4 25
           ]

  , testCase "midnight run does not include the new day when cutoff is 10 PM" $
      let localNow = LocalTime (fromGregorian 2026 4 30) (TimeOfDay 0 0 0)
          cutoff day = LocalTime day (TimeOfDay 22 0 0)
      in eligibleReflectionDays localNow cutoff @?=
           [ fromGregorian 2026 4 29
           , fromGregorian 2026 4 28
           , fromGregorian 2026 4 27
           , fromGregorian 2026 4 26
           ]

  , testCase "correctly handles month boundary" $
      let localNow = LocalTime (fromGregorian 2026 5 2) (TimeOfDay 22 30 0)
          cutoff day = LocalTime day (TimeOfDay 22 0 0)
      in eligibleReflectionDays localNow cutoff @?=
           [ fromGregorian 2026 5 2
           , fromGregorian 2026 5 1
           , fromGregorian 2026 4 30
           , fromGregorian 2026 4 29
           , fromGregorian 2026 4 28
           ]
  ]
