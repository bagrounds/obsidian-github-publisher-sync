module Automation.PacificTime
  ( todayPacificDay
  , yesterdayPacificDay
  , formatDay
  , formatDayHuman
  , pacificHour
  , toPacificLocalTime
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.Time
  ( Day
  , LocalTime
  , UTCTime
  , addDays
  , defaultTimeLocale
  , formatTime
  , getCurrentTime
  , localDay
  , localTimeOfDay
  , todHour
  )
import Data.Time.Zones (TZ, utcToLocalTimeTZ)
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

yesterdayPacificDay :: IO Day
yesterdayPacificDay = addDays (-1) <$> todayPacificDay

pacificHour :: UTCTime -> Int
pacificHour utcNow =
  todHour (localTimeOfDay (utcToLocalTimeTZ pacificTZ utcNow))

toPacificLocalTime :: UTCTime -> LocalTime
toPacificLocalTime = utcToLocalTimeTZ pacificTZ
