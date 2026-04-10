module Automation.TaskRunner
  ( TaskResult
  , interTaskDelayMicroseconds
  , inferenceDashboards
  , runTasks
  , runTasksWithDelay
  , logMsg
  , formatTimestamp
  ) where

import Control.Concurrent (threadDelay)
import Control.Exception (SomeException, try)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Data.Time (defaultTimeLocale, formatTime, getCurrentTime)

import Automation.Scheduler (TaskId, taskIdToText)

type TaskResult = (TaskId, Bool, Maybe Text)

interTaskDelayMicroseconds :: Int
interTaskDelayMicroseconds = 30000000 -- 30 seconds

inferenceDashboards :: [(Text, Text)]
inferenceDashboards =
  [ ("Gemini API", "https://aistudio.google.com/apikey")
  , ("GCP Quotas", "https://console.cloud.google.com/iam-admin/quotas")
  , ("Cloudflare AI", "https://dash.cloudflare.com/?to=/:account/ai/workers-ai")
  , ("Hugging Face", "https://huggingface.co/settings/billing")
  , ("Together AI", "https://api.together.ai/settings/billing")
  ]

formatTimestamp :: IO Text
formatTimestamp = T.pack . formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%S%QZ" <$> getCurrentTime

logMsg :: Text -> IO ()
logMsg message = do
  timestamp <- formatTimestamp
  TIO.putStrLn $ "[" <> timestamp <> "] " <> message

runTasks :: Map TaskId (IO ()) -> [TaskId] -> IO [TaskResult]
runTasks = runTasksWithDelay interTaskDelayMicroseconds

runTasksWithDelay :: Int -> Map TaskId (IO ()) -> [TaskId] -> IO [TaskResult]
runTasksWithDelay delayMicroseconds runners taskIdentifiers = go taskIdentifiers []
  where
    go [] accumulator = pure (reverse accumulator)
    go (taskIdentifier : rest) accumulator = do
      case accumulator of
        [] -> pure ()
        _  -> do
          TIO.putStrLn $ "⏳ Inter-task delay: " <> T.pack (show (delayMicroseconds `div` 1000000)) <> "s"
          threadDelay delayMicroseconds

      let mRunner = Map.lookup taskIdentifier runners
      case mRunner of
        Nothing -> do
          logMsg $ "  ⚠️  Unknown task: " <> taskIdToText taskIdentifier
          go rest ((taskIdentifier, False, Just "no runner registered") : accumulator)
        Just runner -> do
          result <- try runner :: IO (Either SomeException ())
          case result of
            Right () -> go rest ((taskIdentifier, True, Nothing) : accumulator)
            Left exception -> do
              let errorMessage = T.pack (show exception)
              logMsg $ "❌ " <> taskIdToText taskIdentifier <> " — " <> errorMessage
              go rest ((taskIdentifier, False, Just errorMessage) : accumulator)
