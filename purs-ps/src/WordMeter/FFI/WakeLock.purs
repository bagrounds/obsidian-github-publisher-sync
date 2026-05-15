module WordMeter.FFI.WakeLock
  ( WakeLockSentinel
  , WakeLockError(..)
  , renderWakeLockError
  , wakeLockApiAvailable
  , requestScreenWakeLock
  , attachSentinelReleaseListener
  , releaseSentinel
  , sentinelsEqual
  ) where

import Prelude

import Effect (Effect)

-- | Opaque PureScript handle for a browser `WakeLockSentinel`. The JS
-- | side never inspects this value: it is produced by
-- | `requestScreenWakeLock` and consumed by `releaseSentinel` /
-- | `attachSentinelReleaseListener` / `sentinelsEqual`. Lifetime
-- | management — including the question of whether the program is
-- | currently holding a lock — lives entirely in
-- | `WordMeter.Capability.WakeLock`.
foreign import data WakeLockSentinel :: Type

-- | Why a wake-lock operation failed. `WakeLockUnsupported` means the
-- | browser does not expose `navigator.wakeLock.request`; the program
-- | can still run, the screen just will not stay on.
-- | `WakeLockUnavailable` carries the underlying error name (e.g.
-- | `NotAllowedError`) so the diagnostics drawer surfaces something
-- | actionable.
data WakeLockError
  = WakeLockUnsupported
  | WakeLockUnavailable String

derive instance eqWakeLockError :: Eq WakeLockError

instance showWakeLockError :: Show WakeLockError where
  show WakeLockUnsupported = "WakeLockUnsupported"
  show (WakeLockUnavailable detail) =
    "WakeLockUnavailable " <> show detail

renderWakeLockError :: WakeLockError -> String
renderWakeLockError = case _ of
  WakeLockUnsupported -> "wake lock not supported on this browser"
  WakeLockUnavailable detail -> "wake lock unavailable: " <> detail

-- | True iff `navigator.wakeLock.request` is callable. The capability
-- | layer queries this before every `requestScreenWakeLock` so the
-- | "unsupported" case is detected in PureScript rather than via a
-- | sentinel string from JavaScript.
foreign import wakeLockApiAvailable :: Effect Boolean

-- | Thin wrapper over `navigator.wakeLock.request('screen')`. Invokes
-- | exactly one of the two continuations: the sentinel callback on
-- | success, the error callback (carrying the browser's error name) on
-- | rejection. Callers must only invoke this when `wakeLockApiAvailable`
-- | returned `true`.
foreign import requestScreenWakeLock
  :: (WakeLockSentinel -> Effect Unit)
  -> (String -> Effect Unit)
  -> Effect Unit

-- | Subscribe to the sentinel's own `release` event, which fires both
-- | when the browser auto-releases (page hidden, etc.) and when the
-- | program calls `releaseSentinel`. The capability layer reconciles
-- | the two cases by comparing the sentinel against the one it
-- | currently considers held.
foreign import attachSentinelReleaseListener
  :: WakeLockSentinel -> Effect Unit -> Effect Unit

-- | Thin wrapper over `sentinel.release()`. Invokes exactly one of the
-- | two continuations: the success callback when the promise resolves,
-- | the error callback (carrying the browser's error name) when it
-- | rejects or when the synchronous call throws.
foreign import releaseSentinel
  :: WakeLockSentinel
  -> Effect Unit
  -> (String -> Effect Unit)
  -> Effect Unit

-- | Reference equality (`===`) on sentinel handles. The capability layer
-- | uses this to tell its own explicit release apart from a
-- | browser-initiated auto-release on the same sentinel.
foreign import sentinelsEqual :: WakeLockSentinel -> WakeLockSentinel -> Boolean
