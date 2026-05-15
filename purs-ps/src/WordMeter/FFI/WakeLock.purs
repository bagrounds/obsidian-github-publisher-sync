module WordMeter.FFI.WakeLock
  ( WakeLockError(..)
  , renderWakeLockError
  , requestScreenWakeLock
  , releaseScreenWakeLock
  , wakeLockSupported
  ) where

import Prelude

import Effect (Effect)

-- | Why a wake-lock acquisition failed. `WakeLockUnsupported` means the
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

foreign import wakeLockSupportedImpl :: Effect Boolean

wakeLockSupported :: Effect Boolean
wakeLockSupported = wakeLockSupportedImpl

-- | `requestScreenWakeLock onAcquired onError onAutoReleased` kicks off
-- | the asynchronous `navigator.wakeLock.request('screen')` call. The
-- | JS shim keeps the underlying handle in module-level state so the
-- | PureScript side never has to thread an opaque value around. Exactly
-- | one of `onAcquired` or `onError` will be invoked per request;
-- | `onAutoReleased` is invoked when the browser releases the lock on
-- | its own (e.g. when the page becomes hidden).
foreign import requestScreenWakeLockImpl
  :: Effect Unit
  -> (String -> Effect Unit)
  -> Effect Unit
  -> Effect Unit

requestScreenWakeLock
  :: Effect Unit
  -> (WakeLockError -> Effect Unit)
  -> Effect Unit
  -> Effect Unit
requestScreenWakeLock onAcquired onError onAutoReleased =
  requestScreenWakeLockImpl
    onAcquired
    (\reason -> onError (interpretReason reason))
    onAutoReleased

interpretReason :: String -> WakeLockError
interpretReason reason
  | reason == "unsupported" = WakeLockUnsupported
  | otherwise = WakeLockUnavailable reason

-- | Synchronous from PureScript's perspective even though the underlying
-- | `lock.release()` returns a promise: the JS shim fires-and-forgets
-- | the release and clears its stored handle immediately. The
-- | diagnostics that matter (success vs. failure of acquisition) live
-- | on the acquisition path; release is best-effort.
foreign import releaseScreenWakeLockImpl :: Effect Unit

releaseScreenWakeLock :: Effect Unit
releaseScreenWakeLock = releaseScreenWakeLockImpl
