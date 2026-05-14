const describeError = (error) => (error == null ? "" : String(error))

export const askForConfirmationImpl = (prompt) => () => {
  if (typeof window === "undefined" || typeof window.confirm !== "function") {
    return { tag: "unavailable", detail: "", accepted: false }
  }
  try {
    return { tag: "ok", detail: "", accepted: Boolean(window.confirm(prompt)) }
  } catch (error) {
    return { tag: "exception", detail: describeError(error), accepted: false }
  }
}
