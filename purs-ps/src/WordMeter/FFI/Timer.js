// Thin foreign shims for window.setTimeout / window.clearTimeout and
// window.setInterval / window.clearInterval. The PureScript side owns
// the timer-handle ref; this module only wraps the four browser calls.

export const scheduleAfter = (delayMilliseconds) => (callback) => () => {
  const handle = setTimeout(() => { callback() }, delayMilliseconds)
  return handle
}

export const cancelScheduled = (handle) => () => {
  clearTimeout(handle)
}

export const scheduleAtIntervals = (intervalMilliseconds) => (callback) => () => {
  const handle = setInterval(() => { callback() }, intervalMilliseconds)
  return handle
}

export const cancelInterval = (handle) => () => {
  clearInterval(handle)
}
