module Automation.PacificTime
  ( todayPacificDay
  , formatDay
  , formatDayHuman
  , pacificTimeZone
  , pacificHour
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.Time
  ( Day
  , DayOfWeek (..)
  , TimeZone (..)
  , UTCTime (..)
  , addDays
  , dayOfWeek
  , defaultTimeLocale
  , formatTime
  , fromGregorian
  , getCurrentTime
  , localDay
  , localTimeOfDay
  , secondsToDiffTime
  , todHour
  , toGregorian
  , utcToLocalTime
  )

formatDay :: Day -> Text
formatDay = T.pack . formatTime defaultTimeLocale "%Y-%m-%d"

formatDayHuman :: Day -> Text
formatDayHuman day = T.pack $ formatTime defaultTimeLocale "%A, %B %-d, %Y" day

todayPacificDay :: IO Day
todayPacificDay = do
  utcNow <- getCurrentTime
  let tz = pacificTimeZone utcNow
      localTime = utcToLocalTime tz utcNow
  pure $ localDay localTime

pacificHour :: UTCTime -> Int
pacificHour utcNow =
  todHour (localTimeOfDay (utcToLocalTime (pacificTimeZone utcNow) utcNow))

pacificTimeZone :: UTCTime -> TimeZone
pacificTimeZone utcNow
  | isPacificDST utcNow = TimeZone (-420) True "PDT"
  | otherwise            = TimeZone (-480) False "PST"

isPacificDST :: UTCTime -> Bool
isPacificDST utcNow =
  let (year, _, _) = toGregorian (utctDay utcNow)
      dstStart = UTCTime (nthSundayOf 2 year 3) (secondsToDiffTime (10 * 3600))
      dstEnd   = UTCTime (nthSundayOf 1 year 11) (secondsToDiffTime (9 * 3600))
  in utcNow >= dstStart && utcNow < dstEnd

nthSundayOf :: Int -> Integer -> Int -> Day
nthSundayOf n year month =
  let first = fromGregorian year month 1
      offset = daysUntilSunday (dayOfWeek first)
  in addDays (fromIntegral (offset + 7 * (n - 1))) first

daysUntilSunday :: DayOfWeek -> Int
daysUntilSunday = \case
  Sunday    -> 0
  Monday    -> 6
  Tuesday   -> 5
  Wednesday -> 4
  Thursday  -> 3
  Friday    -> 2
  Saturday  -> 1
