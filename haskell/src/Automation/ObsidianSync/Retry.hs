module Automation.ObsidianSync.Retry
  ( RetryableSyncFailure (..)
  , SyncFailure (..)
  , classifySyncFailure
  , FileCount (..)
  , Outcome (..)
  , Attempt (..)
  , filesGained
  , consecutiveStalledAttempts
  , Policy (..)
  , syncPolicy
  , Jitter
  , mkJitter
  , backoffDelay
  , StopReason (..)
  , Decision (..)
  , decide
  ) where

import Data.List.NonEmpty (NonEmpty)
import qualified Data.List.NonEmpty as NonEmpty
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (NominalDiffTime)

data RetryableSyncFailure
  = LockContention
  | ConnectionLost
  deriving (Show, Eq, Bounded, Enum)

data SyncFailure
  = Retryable RetryableSyncFailure
  | Unrecoverable
  deriving (Show, Eq)

lockContentionSignature :: Text
lockContentionSignature = "Another sync instance"

connectionLostSignatures :: [Text]
connectionLostSignatures =
  [ "Error: Disconnected"
  , "Unable to connect to server"
  , "The connection to the server has encountered an error"
  ]

classifySyncFailure :: Text -> SyncFailure
classifySyncFailure message
  | lockContentionSignature `T.isInfixOf` message = Retryable LockContention
  | any (`T.isInfixOf` message) connectionLostSignatures = Retryable ConnectionLost
  | otherwise = Unrecoverable

newtype FileCount = FileCount Int
  deriving (Show, Eq, Ord)

data Outcome
  = Succeeded
  | Failed SyncFailure
  deriving (Show, Eq)

data Attempt = Attempt
  { outcome     :: Outcome
  , filesBefore :: FileCount
  , filesAfter  :: FileCount
  , duration    :: NominalDiffTime
  } deriving (Show, Eq)

filesGained :: Attempt -> Int
filesGained Attempt { filesBefore = FileCount before, filesAfter = FileCount after } = after - before

madeProgress :: Attempt -> Bool
madeProgress = (> 0) . filesGained

consecutiveStalledAttempts :: NonEmpty Attempt -> Int
consecutiveStalledAttempts = length . takeWhile (not . madeProgress) . reverse . NonEmpty.toList

data Policy = Policy
  { baseDelay             :: NominalDiffTime
  , maximumDelay          :: NominalDiffTime
  , maximumStalledRetries :: Int
  , deadline              :: NominalDiffTime
  } deriving (Show, Eq)

syncPolicy :: Policy
syncPolicy = Policy
  { baseDelay = 2
  , maximumDelay = 60
  , maximumStalledRetries = 5
  , deadline = 45 * 60
  }

newtype Jitter = Jitter Double
  deriving (Show, Eq)

mkJitter :: Double -> Jitter
mkJitter = Jitter . max 0 . min 1

backoffDelay :: Policy -> Int -> Jitter -> NominalDiffTime
backoffDelay Policy {..} retryNumber (Jitter fraction) =
  cappedDelay * realToFrac (0.5 + fraction / 2)
  where
    cappedDelay = min maximumDelay (baseDelay * 2 ^ max 0 (retryNumber - 1))

data StopReason
  = SyncCompleted
  | UnrecoverableFailure
  | NoProgress Int
  | DeadlineReached NominalDiffTime
  deriving (Show, Eq)

data Decision
  = RetryAfter NominalDiffTime
  | Stop StopReason
  deriving (Show, Eq)

decide :: Policy -> Jitter -> NominalDiffTime -> NonEmpty Attempt -> Decision
decide policy jitter elapsed attempts = case outcome (NonEmpty.last attempts) of
  Succeeded -> Stop SyncCompleted
  Failed Unrecoverable -> Stop UnrecoverableFailure
  Failed (Retryable _) -> decideRetryable
  where
    stalledAttempts = consecutiveStalledAttempts attempts
    delay = backoffDelay policy (length attempts) jitter
    nextRetryStart = elapsed + delay
    decideRetryable
      | stalledAttempts > maximumStalledRetries policy = Stop (NoProgress stalledAttempts)
      | nextRetryStart > deadline policy = Stop (DeadlineReached nextRetryStart)
      | otherwise = RetryAfter delay
