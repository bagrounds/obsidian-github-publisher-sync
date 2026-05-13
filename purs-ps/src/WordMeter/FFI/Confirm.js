export const askForConfirmation = (prompt) => () => {
  try {
    if (typeof window === "undefined" || typeof window.confirm !== "function") {
      return false
    }
    return Boolean(window.confirm(prompt))
  } catch (_unused) {
    return false
  }
}
