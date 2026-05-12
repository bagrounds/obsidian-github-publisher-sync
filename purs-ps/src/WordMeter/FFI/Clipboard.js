export const writeText = (text) => (onSuccess) => (onError) => () => {
  try {
    if (typeof navigator === "undefined" || !navigator.clipboard
      || typeof navigator.clipboard.writeText !== "function") {
      onError("Clipboard API unavailable")()
      return
    }
    navigator.clipboard.writeText(text)
      .then(() => { onSuccess() })
      .catch((reason) => {
        const message = (reason && reason.message) ? String(reason.message) : String(reason)
        onError(message)()
      })
  } catch (error) {
    const message = (error && error.message) ? String(error.message) : String(error)
    onError(message)()
  }
}
