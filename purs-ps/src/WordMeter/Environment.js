export const captureEnvironmentSnapshotImpl = (version) => () => {
  const userAgent = (typeof navigator !== "undefined" && navigator.userAgent)
    ? String(navigator.userAgent)
    : "(unknown)"
  const navigatorLanguage = (typeof navigator !== "undefined" && navigator.language)
    ? String(navigator.language)
    : "(unknown)"
  return { version, userAgent, navigatorLanguage }
}
