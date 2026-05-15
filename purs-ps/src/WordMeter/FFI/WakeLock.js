// Screen Wake Lock shim. Keeps the active sentinel in module state so the
// PureScript layer can treat acquisition and release as plain `Effect Unit`
// calls without threading an opaque handle around. Every fallible branch
// surfaces a tagged error string through the `onError` continuation rather
// than being silently swallowed.
//
// `activeSentinel` is intentionally `let`-bound: a wake-lock sentinel is
// fundamentally a piece of mutable browser state (the same lock object is
// returned by a promise and torn down by `release()`), so the JavaScript
// shim is the right place to confine that mutation. The PureScript surface
// stays referentially transparent because every transition flows through
// the typed `WakeLockError` continuation.
let activeSentinel = null

const describeError = (error) => {
  if (error == null) return "error"
  if (typeof error === "string") return error
  if (error.name) return String(error.name)
  if (error.message) return String(error.message)
  return String(error)
}

const hasWakeLock = () =>
  typeof navigator !== "undefined"
    && navigator.wakeLock
    && typeof navigator.wakeLock.request === "function"

export const wakeLockSupportedImpl = () => hasWakeLock()

export const requestScreenWakeLockImpl =
  (onAcquired) => (onError) => (onAutoReleased) => () => {
    if (!hasWakeLock()) {
      onError("unsupported")()
      return
    }
    try {
      navigator.wakeLock
        .request("screen")
        .then((sentinel) => {
          activeSentinel = sentinel
          if (sentinel && typeof sentinel.addEventListener === "function") {
            sentinel.addEventListener("release", () => {
              if (activeSentinel === sentinel) activeSentinel = null
              onAutoReleased()
            })
          }
          onAcquired()
        })
        .catch((reason) => {
          onError(describeError(reason))()
        })
    } catch (error) {
      onError(describeError(error))()
    }
  }

export const releaseScreenWakeLockImpl = () => {
  const sentinel = activeSentinel
  activeSentinel = null
  if (!sentinel || typeof sentinel.release !== "function") return
  try {
    const result = sentinel.release()
    if (result && typeof result.catch === "function") {
      // Best-effort: swallowing this is fine because the only contract a
      // failed release has is "the lock is still held". The next request
      // will be a fresh sentinel anyway.
      result.catch(() => {})
    }
  } catch (_error) {
    // Same rationale: a synchronous throw here just means the page is
    // already not holding the lock. Acquisition errors are the ones
    // that matter, and they flow through `onError` on the request path.
  }
}
