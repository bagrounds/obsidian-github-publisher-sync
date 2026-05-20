// Thin foreign shims for the Document Picture-in-Picture API. Each
// export wraps a single browser call and surfaces every failure mode
// through its supplied callback — there is no module-level state, no
// decisions about lifecycle, and no swallowed errors. The PureScript
// side (WordMeter.FFI.DocumentPip + WordMeter.Capability.DocumentPip)
// owns window lifetime and the typed error algebra.

const pipWindowWidth = 320
const pipWindowHeight = 220

const describeUserAgent = () => {
  if (typeof navigator === "undefined") return "no navigator"
  // Prefer the structured User-Agent Client Hints API where available
  // (Chromium-based browsers expose `userAgentData`). It distinguishes
  // mobile from desktop without UA-string sniffing.
  const data = navigator.userAgentData
  if (data && typeof data === "object") {
    const brandList = Array.isArray(data.brands)
      ? data.brands
          .map((entry) => (entry && entry.brand ? String(entry.brand) : ""))
          .filter((brand) => brand && !/Not.A.Brand/i.test(brand))
          .join(", ")
      : ""
    const platform = data.platform ? String(data.platform) : "unknown platform"
    const form = data.mobile ? "mobile" : "desktop"
    const brands = brandList || "unknown browser"
    return brands + " on " + platform + " (" + form + ")"
  }
  // Fall back to the legacy UA string, which is good enough for the
  // diagnostic detail even though it's lossy.
  return navigator.userAgent ? String(navigator.userAgent) : "unknown UA"
}

const looksMobile = () => {
  if (typeof navigator === "undefined") return false
  const data = navigator.userAgentData
  if (data && typeof data.mobile === "boolean") return data.mobile
  // UA-string fallback: Chromium on Android always advertises "Android"
  // and "Mobile"; iOS Safari advertises "iPhone"/"iPad".
  const ua = navigator.userAgent || ""
  return /Android|iPhone|iPad|iPod|Mobile/i.test(ua)
}

export const checkDocumentPipAvailability = () => {
  if (typeof window === "undefined") return "no window object available"
  const api = window.documentPictureInPicture
  if (!api) {
    // The most likely cause of a missing API on a sane install. We call
    // out Chromium on mobile explicitly because the user can see the
    // platform's PiP permission toggle and reasonably expect this API
    // to follow — but Chromium ships Document Picture-in-Picture only
    // on desktop (Windows, macOS, Linux, ChromeOS) as of 2026. The
    // mobile PiP toggle governs the legacy HTMLVideoElement PiP API
    // instead, which is unrelated.
    if (looksMobile()) {
      return "Document Picture-in-Picture is desktop-only on Chromium" +
        " (no Android/iOS support as of 2026); user-agent=" +
        describeUserAgent()
    }
    return "window.documentPictureInPicture is undefined; user-agent=" +
      describeUserAgent()
  }
  if (typeof api.requestWindow !== "function") {
    return "documentPictureInPicture.requestWindow is not a function" +
      "; user-agent=" + describeUserAgent()
  }
  return ""
}

const describeFailure = (error) => {
  if (error == null) return "unknown error"
  if (typeof error === "string") return error
  if (error.name) return String(error.name)
  if (error.message) return String(error.message)
  return String(error)
}

export const requestPipWindow = (onWindow) => (onError) => () => {
  try {
    window.documentPictureInPicture
      .requestWindow({ width: pipWindowWidth, height: pipWindowHeight })
      .then((pipWindow) => {
        seedPipDocument(pipWindow)
        onWindow(pipWindow)()
      })
      .catch((reason) => { onError(describeFailure(reason))() })
  } catch (error) {
    onError(describeFailure(error))()
  }
}

export const attachPipCloseListener = (pipWindow) => (handler) => () => {
  pipWindow.addEventListener("pagehide", () => { handler() })
}

export const closePipWindow = (pipWindow) => () => {
  try {
    pipWindow.close()
  } catch {
    // close() throws when the window has already been closed (e.g. the
    // user dismissed it via the OS chrome a moment ago). The close
    // listener fires for both paths, so swallowing this synchronous
    // exception cannot hide an unobserved failure.
  }
}

export const writePipContent = (pipWindow) => (content) => () => {
  const doc = pipWindow.document
  if (!doc) return
  let countEl = doc.getElementById("wm-pip-count")
  let statusEl = doc.getElementById("wm-pip-status")
  if (!countEl || !statusEl) {
    seedPipDocument(pipWindow)
    countEl = doc.getElementById("wm-pip-count")
    statusEl = doc.getElementById("wm-pip-status")
  }
  if (countEl) countEl.textContent = String(content.wordsToday)
  if (statusEl) statusEl.textContent = String(content.status)
}

const seedPipDocument = (pipWindow) => {
  const doc = pipWindow.document
  if (!doc) return
  doc.title = "Word Meter"
  const style = doc.createElement("style")
  style.textContent = pipStylesheet
  doc.head.appendChild(style)
  const root = doc.createElement("div")
  root.className = "wm-pip-root"
  root.setAttribute("data-testid", "wm-pip-root")
  const count = doc.createElement("div")
  count.id = "wm-pip-count"
  count.className = "wm-pip-count"
  count.setAttribute("data-testid", "wm-pip-count")
  count.textContent = "0"
  const label = doc.createElement("div")
  label.className = "wm-pip-count-label"
  label.textContent = "words today"
  const status = doc.createElement("div")
  status.id = "wm-pip-status"
  status.className = "wm-pip-status"
  status.setAttribute("data-testid", "wm-pip-window-status")
  status.textContent = "Idle"
  root.appendChild(count)
  root.appendChild(label)
  root.appendChild(status)
  doc.body.appendChild(root)
}

const pipStylesheet = `
  html, body { margin: 0; padding: 0; height: 100%; background: #0b0d10; color: #f3f4f6; font-family: system-ui, sans-serif; }
  .wm-pip-root { box-sizing: border-box; height: 100%; padding: 16px; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 4px; }
  .wm-pip-count { font-size: 96px; font-weight: 700; line-height: 1; font-variant-numeric: tabular-nums; }
  .wm-pip-count-label { font-size: 14px; opacity: 0.7; letter-spacing: 0.04em; text-transform: uppercase; }
  .wm-pip-status { margin-top: 12px; font-size: 16px; opacity: 0.85; }
`
