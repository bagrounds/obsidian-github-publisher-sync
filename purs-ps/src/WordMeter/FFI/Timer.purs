-- | Thin foreign shims over `window.setTimeout` and
-- | `window.clearTimeout`. Used by `WordMeter.Capability.Recognition`
-- | to schedule the 250 ms auto-restart that legacy recognition
-- | depends on. The handle is opaque on purpose: callers never inspect
-- | it, they only pass it back to `cancelScheduled`.
module WordMeter.FFI.Timer
  ( TimerHandle
  , scheduleAfter
  , cancelScheduled
  ) where

import Prelude

import Effect (Effect)

foreign import data TimerHandle :: Type

-- | Schedule `callback` to fire after `delayMilliseconds`. Returns the
-- | handle so the caller can cancel the scheduled fire through
-- | `cancelScheduled`.
foreign import scheduleAfter
  :: Int -> Effect Unit -> Effect TimerHandle

-- | Cancel a previously-scheduled callback. Idempotent: cancelling a
-- | handle that already fired is a successful no-op.
foreign import cancelScheduled :: TimerHandle -> Effect Unit
