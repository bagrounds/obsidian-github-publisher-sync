// Document-level visibility subscription used by the screen wake-lock
// re-acquisition path. There is deliberately no unsubscribe path: the
// listener's lifetime is the page lifetime, so an explicit teardown
// would only complicate the API without giving the caller anything
// meaningful.
export const subscribeVisibilityVisibleImpl = (handler) => () => {
  if (typeof document === "undefined") return
  if (typeof document.addEventListener !== "function") return
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible") handler()
  })
}
