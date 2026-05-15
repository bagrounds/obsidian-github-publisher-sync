// Thin foreign shims for the Screen Wake Lock API. Each export wraps a
// single browser call and surfaces every failure mode through its
// supplied callback — there is no module-level state, no decisions
// about what "auto-release" means, and no swallowed errors. The
// PureScript side (WordMeter.FFI.WakeLock + WordMeter.Capability.WakeLock)
// owns sentinel lifetime and the typed error algebra.

const describeFailure = (error) => {
  if (error == null) return "unknown error"
  if (typeof error === "string") return error
  if (error.name) return String(error.name)
  if (error.message) return String(error.message)
  return String(error)
}

export const wakeLockApiAvailable = () =>
  typeof navigator !== "undefined"
    && !!navigator.wakeLock
    && typeof navigator.wakeLock.request === "function"

export const requestScreenWakeLock = (onSentinel) => (onError) => () => {
  navigator.wakeLock
    .request("screen")
    .then((sentinel) => { onSentinel(sentinel)() })
    .catch((reason) => { onError(describeFailure(reason))() })
}

export const attachSentinelReleaseListener = (sentinel) => (handler) => () => {
  sentinel.addEventListener("release", () => { handler() })
}

export const releaseSentinel = (sentinel) => (onReleased) => (onError) => () => {
  try {
    const result = sentinel.release()
    if (result && typeof result.then === "function") {
      result.then(() => { onReleased() })
            .catch((reason) => { onError(describeFailure(reason))() })
    } else {
      onReleased()
    }
  } catch (error) {
    onError(describeFailure(error))()
  }
}

export const sentinelsEqual = (left) => (right) => left === right
