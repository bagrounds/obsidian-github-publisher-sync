-- | Capability for the live tick driver. Production code in
-- | `WordMeter.Main` starts the interval on Toggle-to-start and
-- | cancels it on Toggle-to-stop so the rate/duration UI keeps
-- | refreshing once per `tickIntervalMilliseconds` while the
-- | recognizer is active. The `AppM` instance owns the
-- | `IntervalHandle` ref in `ApplicationEnvironment`.
module WordMeter.Capability.Ticker
  ( class Ticker
  , startTickerInterval
  , stopTickerInterval
  , tickIntervalMilliseconds
  ) where

import Prelude

import Control.Monad.Reader.Class (ask)
import Data.Maybe (Maybe(..))
import Effect (Effect)
import Effect.Class (liftEffect)
import Effect.Ref as Ref
import WordMeter.AppM (AppM(..), ApplicationEnvironment, runAppM)
import WordMeter.FFI.Timer as Timer

-- | Legacy `TICK_INTERVAL_MILLISECONDS` from `word-meter.js`. The
-- | live stats panel refreshes at this cadence while listening so
-- | trailing-window rates, captions, and timeline ages stay current
-- | even when no transcript callback has fired in a while.
tickIntervalMilliseconds :: Int
tickIntervalMilliseconds = 200

class Monad m <= Ticker m where
  -- | Start an interval that fires `tickAction` every
  -- | `tickIntervalMilliseconds`. If an interval is already running
  -- | the previous one is cancelled first so we cannot leak handles.
  startTickerInterval :: m Unit -> m Unit
  -- | Cancel the active interval, if any. Idempotent: a successful
  -- | no-op when nothing is running.
  stopTickerInterval :: m Unit

instance tickerAppM :: Ticker AppM where
  startTickerInterval tickAction =
    AppM do
      environment <- ask
      liftEffect (startTickerIntervalInEnvironment environment tickAction)
  stopTickerInterval =
    AppM do
      environment <- ask
      liftEffect (stopTickerIntervalInEnvironment environment)

startTickerIntervalInEnvironment
  :: ApplicationEnvironment -> AppM Unit -> Effect Unit
startTickerIntervalInEnvironment environment tickAction = do
  stopTickerIntervalInEnvironment environment
  handle <- Timer.scheduleAtIntervals tickIntervalMilliseconds
    (runAppM environment tickAction)
  Ref.write (Just handle) environment.tickIntervalHandleRef

stopTickerIntervalInEnvironment :: ApplicationEnvironment -> Effect Unit
stopTickerIntervalInEnvironment environment = do
  held <- Ref.read environment.tickIntervalHandleRef
  case held of
    Nothing -> pure unit
    Just handle -> do
      Ref.write Nothing environment.tickIntervalHandleRef
      Timer.cancelInterval handle
