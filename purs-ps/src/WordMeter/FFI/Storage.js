const tryStorage = () => {
  if (typeof localStorage === "undefined") {
    return { available: false, detail: "localStorage is undefined" }
  }
  try {
    return { available: true, storage: localStorage }
  } catch (error) {
    return { available: false, detail: error == null ? "" : String(error) }
  }
}

const describeError = (error) => (error == null ? "" : String(error))

export const readPersistedStringImpl = (key) => () => {
  const probe = tryStorage()
  if (!probe.available) {
    return { tag: "unavailable", detail: probe.detail, value: "" }
  }
  try {
    const raw = probe.storage.getItem(key)
    if (raw == null) {
      return { tag: "missing", detail: "", value: "" }
    }
    return { tag: "ok", detail: "", value: raw }
  } catch (error) {
    return { tag: "exception", detail: describeError(error), value: "" }
  }
}

export const writePersistedStringImpl = (key) => (payload) => () => {
  const probe = tryStorage()
  if (!probe.available) {
    return { tag: "unavailable", detail: probe.detail, value: undefined }
  }
  try {
    probe.storage.setItem(key, payload)
    return { tag: "ok", detail: "", value: undefined }
  } catch (error) {
    return { tag: "exception", detail: describeError(error), value: undefined }
  }
}

export const clearPersistedStringImpl = (key) => () => {
  const probe = tryStorage()
  if (!probe.available) {
    return { tag: "unavailable", detail: probe.detail, value: undefined }
  }
  try {
    probe.storage.removeItem(key)
    return { tag: "ok", detail: "", value: undefined }
  } catch (error) {
    return { tag: "exception", detail: describeError(error), value: undefined }
  }
}
