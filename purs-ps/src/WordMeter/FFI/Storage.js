const STORAGE_KEY = "word-meter-ps:state:v1"

const safeLocalStorage = () => {
  try {
    return typeof localStorage !== "undefined" ? localStorage : null
  } catch (_unused) {
    return null
  }
}

const sanitizeNumber = (value, fallback) => {
  const numeric = Number(value)
  return isFinite(numeric) ? numeric : fallback
}

const sanitizeWordEvents = (raw) => {
  if (!Array.isArray(raw)) return []
  return raw
    .map((event) => ({
      timestamp: sanitizeNumber(event && event.timestamp, NaN),
      wordCount: sanitizeNumber(event && event.wordCount, 0),
    }))
    .filter((event) => isFinite(event.timestamp) && event.wordCount > 0)
}

const sanitizeEventLog = (raw) => {
  if (!Array.isArray(raw)) return []
  return raw
    .map((interval) => ({
      startedAt: sanitizeNumber(interval && interval.startedAt, NaN),
      endedAt: sanitizeNumber(interval && interval.endedAt, NaN),
      wordCount: Math.max(
        0,
        Math.floor(sanitizeNumber(interval && interval.wordCount, 0)),
      ),
    }))
    .filter(
      (interval) =>
        isFinite(interval.startedAt) &&
        isFinite(interval.endedAt) &&
        interval.endedAt >= interval.startedAt,
    )
}

export const loadData = (nothing) => (just) => () => {
  const storage = safeLocalStorage()
  if (!storage) return nothing
  try {
    const raw = storage.getItem(STORAGE_KEY)
    if (!raw) return nothing
    const data = JSON.parse(raw)
    if (!data || data.version !== 1) return nothing
    return just({
      totalWords: Math.max(
        0,
        Math.floor(sanitizeNumber(data.totalWords, 0)),
      ),
      firstStartedAt: isFinite(data.firstStartedAt)
        ? data.firstStartedAt
        : NaN,
      wordEvents: sanitizeWordEvents(data.wordEvents),
      eventLog: sanitizeEventLog(data.eventLog),
    })
  } catch (_unused) {
    return nothing
  }
}

export const saveData = (data) => () => {
  const storage = safeLocalStorage()
  if (!storage) return
  try {
    const snapshot = {
      version: 1,
      totalWords: data.totalWords,
      firstStartedAt: isFinite(data.firstStartedAt)
        ? data.firstStartedAt
        : null,
      wordEvents: data.wordEvents,
      eventLog: data.eventLog,
    }
    storage.setItem(STORAGE_KEY, JSON.stringify(snapshot))
  } catch (_unused) {
    // quota exceeded or serialisation failure — drop silently
  }
}

export const clearData = () => {
  const storage = safeLocalStorage()
  if (!storage) return
  try {
    storage.removeItem(STORAGE_KEY)
  } catch (_unused) {
    // noop
  }
}
