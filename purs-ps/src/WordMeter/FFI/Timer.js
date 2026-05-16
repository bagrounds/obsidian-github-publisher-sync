// Thin foreign shims for window.setTimeout / window.clearTimeout. The
// PureScript side owns the timer-handle ref; this module only wraps
// the two browser calls.

export const scheduleAfter = (delayMilliseconds) => (callback) => () => {
  const handle = setTimeout(() => { callback() }, delayMilliseconds)
  return handle
}

export const cancelScheduled = (handle) => () => {
  clearTimeout(handle)
}
