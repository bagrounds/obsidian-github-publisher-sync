module Automation.Timer
  ( PipelineTimer
  , TimerEntry (..)
  , newPipelineTimer
  , timerStart
  , timerEnd
  , timerTime
  , printTimerSummary
  ) where

import Control.Exception (finally)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Maybe (fromMaybe, isNothing)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Data.Time (NominalDiffTime, UTCTime, diffUTCTime, getCurrentTime)
import Numeric (showFFloat)

data TimerEntry = TimerEntry
  { name      :: Text
  , startTime :: UTCTime
  , endTime   :: Maybe UTCTime
  } deriving (Show, Eq)

data PipelineTimer = PipelineTimer
  { entries       :: IORef [TimerEntry]
  , pipelineStart :: UTCTime
  }

newPipelineTimer :: IO PipelineTimer
newPipelineTimer = PipelineTimer <$> newIORef [] <*> getCurrentTime

timerStart :: PipelineTimer -> Text -> IO ()
timerStart timer timerName = do
  now <- getCurrentTime
  modifyIORef' (entries timer) (<> [TimerEntry timerName now Nothing])

timerEnd :: PipelineTimer -> Text -> IO ()
timerEnd timer timerName = do
  now <- getCurrentTime
  modifyIORef' (entries timer) (fmap (closeEntry now))
  where
    closeEntry now entry
      | name entry == timerName && isNothing (endTime entry) =
          entry { endTime = Just now }
      | otherwise = entry

timerTime :: PipelineTimer -> Text -> IO a -> IO a
timerTime timer name action = do
  timerStart timer name
  action `finally` timerEnd timer name

formatDuration :: NominalDiffTime -> Text
formatDuration dt = T.pack $ showFFloat (Just 1) (realToFrac dt :: Double) ""

formatPercent :: NominalDiffTime -> NominalDiffTime -> Text
formatPercent part whole
  | whole > 0 =
      T.pack $ showFFloat (Just 1) ((realToFrac part / realToFrac whole :: Double) * 100) ""
  | otherwise = "0.0"

padEnd :: Int -> Text -> Text
padEnd n t = t <> T.replicate (max 0 (n - T.length t)) " "

padStart :: Int -> Text -> Text
padStart n t = T.replicate (max 0 (n - T.length t)) " " <> t

printTimerSummary :: PipelineTimer -> IO ()
printTimerSummary timer = do
  now <- getCurrentTime
  timerEntries <- readIORef (entries timer)
  let totalDuration = diffUTCTime now (pipelineStart timer)
      separator = T.replicate 52 "─"
  TIO.putStrLn ""
  TIO.putStrLn "⏱️  Pipeline Timing Summary:"
  TIO.putStrLn separator
  mapM_ (printEntry now totalDuration) timerEntries
  TIO.putStrLn separator
  TIO.putStrLn $
    "  🏁 Total pipeline time" <> T.replicate 13 " "
      <> " " <> padStart 7 (formatDuration totalDuration) <> "s"

printEntry :: UTCTime -> NominalDiffTime -> TimerEntry -> IO ()
printEntry now totalDuration entry =
  let entryEndTime = fromMaybe now (endTime entry)
      duration = diffUTCTime entryEndTime (startTime entry)
      status = maybe "⏳" (const "✅") (endTime entry)
  in TIO.putStrLn $
       "  " <> status <> " " <> padEnd 30 (name entry)
         <> " " <> padStart 7 (formatDuration duration) <> "s"
         <> "  (" <> padStart 5 (formatPercent duration totalDuration) <> "%)"
