module Automation.PacificTime
  ( todayPacificDay
  , formatDay
  , formatDayHuman
  , pacificHour
  , pacificToUtcHour
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.Time
  ( Day
  , LocalTime (..)
  , TimeOfDay (..)
  , UTCTime (..)
  , defaultTimeLocale
  , formatTime
  , getCurrentTime
  , localDay
  , localTimeOfDay
  , todHour
  )
import Data.Time.Zones (TZ, localTimeToUTCTZ, utcToLocalTimeTZ)
import Data.Time.Zones.All (TZLabel (..), tzByLabel)

pacificTZ :: TZ
pacificTZ = tzByLabel America__Los_Angeles

formatDay :: Day -> Text
formatDay = T.pack . formatTime defaultTimeLocale "%Y-%m-%d"

formatDayHuman :: Day -> Text
formatDayHuman day = T.pack $ formatTime defaultTimeLocale "%A, %B %-d, %Y" day

todayPacificDay :: IO Day
todayPacificDay =
  localDay . utcToLocalTimeTZ pacificTZ <$> getCurrentTime

pacificHour :: UTCTime -> Int
pacificHour utcNow =
  todHour (localTimeOfDay (utcToLocalTimeTZ pacificTZ utcNow))

pacificToUtcHour :: Int -> Day -> Int
pacificToUtcHour hour day =
  let localTime = LocalTime day (TimeOfDay hour 0 0)
      utcTime = localTimeToUTCTZ pacificTZ localTime
      secondsPerHour = 3600
  in floor (utctDayTime utcTime / secondsPerHour) `mod` 24
