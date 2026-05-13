const safeStorage = () => {
  try {
    if (typeof localStorage === "undefined") return null
    return localStorage
  } catch (_unused) {
    return null
  }
}

export const readPersistedStringImpl = (nothing) => (just) => (key) => () => {
  const storage = safeStorage()
  if (!storage) return nothing
  try {
    const raw = storage.getItem(key)
    return raw == null ? nothing : just(raw)
  } catch (_unused) {
    return nothing
  }
}

export const writePersistedString = (key) => (payload) => () => {
  const storage = safeStorage()
  if (!storage) return
  try {
    storage.setItem(key, payload)
  } catch (_unused) {
    /* quota exceeded or serialization failure — drop silently */
  }
}

export const clearPersistedString = (key) => () => {
  const storage = safeStorage()
  if (!storage) return
  try {
    storage.removeItem(key)
  } catch (_unused) {
    /* noop */
  }
}

const sanitizeNumber = (value, fallback) => {
  const numeric = Number(value)
  return Number.isFinite(numeric) ? numeric : fallback
}

const sanitizeFirstStartedAt = (value) => {
  // NaN sentinel mirrors `Maybe Number` with `Nothing == NaN`. `null` /
  // `undefined` are the wire form of `Nothing`; anything else that
  // fails to coerce to a finite number is also treated as "never
  // started" so a corrupted payload never bleeds into time math.
  if (value == null) return Number.NaN
  const numeric = Number(value)
  return Number.isFinite(numeric) ? numeric : Number.NaN
}

const sanitizeWordEvents = (raw) => {
  if (!Array.isArray(raw)) return []
  const events = []
  for (const event of raw) {
    if (event == null) continue
    const timestamp = sanitizeNumber(event.timestamp, Number.NaN)
    const wordCount = Math.max(0, Math.floor(sanitizeNumber(event.wordCount, 0)))
    if (!Number.isFinite(timestamp) || wordCount <= 0) continue
    events.push({ timestamp, wordCount })
  }
  return events
}

const sanitizeEventLog = (raw) => {
  if (!Array.isArray(raw)) return []
  const intervals = []
  for (const interval of raw) {
    if (interval == null) continue
    const startedAt = sanitizeNumber(interval.startedAt, Number.NaN)
    const endedAt = sanitizeNumber(interval.endedAt, Number.NaN)
    const wordCount = Math.max(0, Math.floor(sanitizeNumber(interval.wordCount, 0)))
    if (!Number.isFinite(startedAt) || !Number.isFinite(endedAt)) continue
    if (endedAt < startedAt) continue
    intervals.push({ startedAt, endedAt, wordCount })
  }
  return intervals
}

export const decodePersistedPayloadImpl =
  (nothing) => (just) => (expectedVersion) => (raw) => {
    if (typeof raw !== "string" || raw.length === 0) return nothing
    let data
    try {
      data = JSON.parse(raw)
    } catch (_unused) {
      return nothing
    }
    if (data == null || typeof data !== "object") return nothing
    if (data.version !== expectedVersion) return nothing
    return just({
      totalWords: Math.max(0, Math.floor(sanitizeNumber(data.totalWords, 0))),
      firstStartedAt: sanitizeFirstStartedAt(data.firstStartedAt),
      wordEvents: sanitizeWordEvents(data.wordEvents),
      eventLog: sanitizeEventLog(data.eventLog),
    })
  }
