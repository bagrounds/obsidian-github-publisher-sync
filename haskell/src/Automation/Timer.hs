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
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Data.Time (NominalDiffTime, UTCTime, diffUTCTime, getCurrentTime)
import Numeric (showFFloat)

data TimerEntry = TimerEntry
  { teName      :: Text
  , teStartTime :: UTCTime
  , teEndTime   :: Maybe UTCTime
  } deriving (Show, Eq)

data PipelineTimer = PipelineTimer
  { ptEntries   :: IORef [TimerEntry]
  , ptStartTime :: UTCTime
  }

newPipelineTimer :: IO PipelineTimer
newPipelineTimer = PipelineTimer <$> newIORef [] <*> getCurrentTime

timerStart :: PipelineTimer -> Text -> IO ()
timerStart timer name = do
  now <- getCurrentTime
  modifyIORef' (ptEntries timer) (<> [TimerEntry name now Nothing])

timerEnd :: PipelineTimer -> Text -> IO ()
timerEnd timer name = do
  now <- getCurrentTime
  modifyIORef' (ptEntries timer) (fmap (closeEntry now))
  where
    closeEntry now entry
      | teName entry == name && teEndTime entry == Nothing =
          entry { teEndTime = Just now }
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
  entries <- readIORef (ptEntries timer)
  let totalDt = diffUTCTime now (ptStartTime timer)
      separator = T.replicate 52 "─"
  TIO.putStrLn ""
  TIO.putStrLn "⏱️  Pipeline Timing Summary:"
  TIO.putStrLn separator
  mapM_ (printEntry now totalDt) entries
  TIO.putStrLn separator
  TIO.putStrLn $
    "  🏁 Total pipeline time" <> T.replicate 13 " "
      <> " " <> padStart 7 (formatDuration totalDt) <> "s"

printEntry :: UTCTime -> NominalDiffTime -> TimerEntry -> IO ()
printEntry now totalDt entry =
  let endTime = fromMaybe now (teEndTime entry)
      durationDt = diffUTCTime endTime (teStartTime entry)
      status = maybe "⏳" (const "✅") (teEndTime entry)
  in TIO.putStrLn $
       "  " <> status <> " " <> padEnd 30 (teName entry)
         <> " " <> padStart 7 (formatDuration durationDt) <> "s"
         <> "  (" <> padStart 5 (formatPercent durationDt totalDt) <> "%)"
