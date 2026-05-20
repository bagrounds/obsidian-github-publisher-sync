// Thin foreign shims for Picture-in-Picture. Each export wraps one
// browser-side concern and surfaces every failure mode through its
// supplied callback — no swallowed errors. The PureScript side
// (WordMeter.FFI.DocumentPip + WordMeter.Capability.DocumentPip) owns
// the opaque PipWindow handle, the typed error algebra, and lifecycle.
//
// Two underlying browser APIs are bridged here:
//
// 1. Document Picture-in-Picture (window.documentPictureInPicture):
//    desktop Chromium only. When available the shim renders the count
//    into a real HTML document inside the floating window.
//
// 2. Element-level Video Picture-in-Picture
//    (HTMLVideoElement.requestPictureInPicture): widely supported on
//    Android Chrome and other mobile Chromium browsers. The shim
//    draws the count onto an offscreen canvas, captures the canvas
//    into a hidden <video> via captureStream, and requests PiP on
//    that video. From PureScript's perspective both paths return a
//    single opaque PipWindow handle.
//
// The opaque handle is an internal record { kind, ... } that all
// other exports dispatch on. PureScript never inspects it.

const pipWindowWidth = 320
const pipWindowHeight = 220
// Video-PiP redraws are driven by writePipContent, so the captured
// stream only needs enough frames to keep the OS happy that the video
// is "live". Two frames per second is gentle on battery and avoids
// dropping the PiP window on idle on some Chromium builds.
const videoPipFramesPerSecond = 2

const getUserAgentContext = () => {
  if (typeof navigator === "undefined") {
    return { mobile: false, description: "no navigator" }
  }
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
    const mobile = typeof data.mobile === "boolean" ? data.mobile : false
    const form = mobile ? "mobile" : "desktop"
    const brands = brandList || "unknown browser"
    return {
      mobile,
      description: brands + " on " + platform + " (" + form + ")",
    }
  }
  // Fall back to the legacy UA string. The string sniff covers iOS
  // Safari and older Chromium builds that pre-date Client Hints.
  const ua = navigator.userAgent ? String(navigator.userAgent) : "unknown UA"
  const mobile = /Android|iPhone|iPad|iPod|Mobile/i.test(ua)
  return { mobile, description: ua }
}

const documentPipAvailable = () =>
  typeof window !== "undefined"
    && !!window.documentPictureInPicture
    && typeof window.documentPictureInPicture.requestWindow === "function"

const videoPipAvailable = () => {
  if (typeof window === "undefined") return false
  if (typeof document === "undefined") return false
  // `pictureInPictureEnabled` is the spec-defined gate. We also
  // require the request method and canvas captureStream — both are
  // present on every UA that supports the API.
  if (!document.pictureInPictureEnabled) return false
  const videoProto = window.HTMLVideoElement && window.HTMLVideoElement.prototype
  if (!videoProto || typeof videoProto.requestPictureInPicture !== "function") {
    return false
  }
  const canvasProto = window.HTMLCanvasElement && window.HTMLCanvasElement.prototype
  if (!canvasProto || typeof canvasProto.captureStream !== "function") {
    return false
  }
  return true
}

export const checkDocumentPipAvailability = () => {
  if (typeof window === "undefined") return "no window object available"
  if (documentPipAvailable()) return ""
  if (videoPipAvailable()) return ""
  const { mobile, description } = getUserAgentContext()
  if (mobile) {
    return "no Picture-in-Picture path available on this device" +
      " (HTMLVideoElement.requestPictureInPicture is missing or" +
      " pictureInPictureEnabled is false); user-agent=" + description
  }
  return "Document Picture-in-Picture API is absent and" +
    " HTMLVideoElement.requestPictureInPicture is not callable;" +
    " user-agent=" + description
}

const describeFailure = (error) => {
  if (error == null) return "unknown error"
  if (typeof error === "string") return error
  if (error.name) return String(error.name)
  if (error.message) return String(error.message)
  return String(error)
}

export const requestPipWindow = (onWindow) => (onError) => () => {
  if (documentPipAvailable()) {
    requestDocumentPipWindow(onWindow, onError)
    return
  }
  if (videoPipAvailable()) {
    requestVideoPipWindow(onWindow, onError)
    return
  }
  onError("no Picture-in-Picture path available at request time")()
}

const requestDocumentPipWindow = (onWindow, onError) => {
  try {
    window.documentPictureInPicture
      .requestWindow({ width: pipWindowWidth, height: pipWindowHeight })
      .then((pipWindow) => {
        seedPipDocument(pipWindow)
        onWindow({ kind: "document", pipWindow })()
      })
      .catch((reason) => { onError(describeFailure(reason))() })
  } catch (error) {
    onError(describeFailure(error))()
  }
}

const requestVideoPipWindow = (onWindow, onError) => {
  try {
    const canvas = document.createElement("canvas")
    canvas.width = pipWindowWidth
    canvas.height = pipWindowHeight
    const context = canvas.getContext("2d")
    if (!context) {
      onError("canvas 2d context unavailable")()
      return
    }
    const stream = canvas.captureStream(videoPipFramesPerSecond)
    const video = document.createElement("video")
    video.muted = true
    video.playsInline = true
    video.autoplay = true
    video.srcObject = stream
    // The video element must be attached to the document for some
    // Chromium builds to grant PiP — but it should not be visible.
    video.style.position = "fixed"
    video.style.left = "-9999px"
    video.style.top = "-9999px"
    video.style.width = "1px"
    video.style.height = "1px"
    video.style.opacity = "0"
    video.setAttribute("data-testid", "wm-pip-video")
    document.body.appendChild(video)
    const handle = {
      kind: "video",
      video,
      canvas,
      context,
      stream,
      lastContent: { wordsToday: 0, status: "Idle" },
    }
    drawVideoPipFrame(handle)
    const requestPip = () => {
      try {
        video.requestPictureInPicture()
          .then(() => { onWindow(handle)() })
          .catch((reason) => {
            cleanupVideoPipHandle(handle)
            onError(describeFailure(reason))()
          })
      } catch (error) {
        cleanupVideoPipHandle(handle)
        onError(describeFailure(error))()
      }
    }
    // Some Android Chromium builds reject requestPictureInPicture if
    // the video has not produced its first frame yet. Wait for one
    // loadedmetadata / playing tick before requesting.
    const startWhenReady = () => {
      video.removeEventListener("loadedmetadata", startWhenReady)
      video.removeEventListener("playing", startWhenReady)
      requestPip()
    }
    if (video.readyState >= 1) {
      requestPip()
    } else {
      video.addEventListener("loadedmetadata", startWhenReady, { once: true })
      video.addEventListener("playing", startWhenReady, { once: true })
    }
    // Kick the playback pipeline. `.play()` returns a promise on most
    // builds; we ignore rejection because the readyState branch above
    // is the source of truth.
    try {
      const playPromise = video.play()
      if (playPromise && typeof playPromise.catch === "function") {
        playPromise.catch(() => {})
      }
    } catch {
      // Older builds throw synchronously; loadedmetadata still fires.
    }
  } catch (error) {
    onError(describeFailure(error))()
  }
}

const cleanupVideoPipHandle = (handle) => {
  try {
    if (handle.stream) {
      handle.stream.getTracks().forEach((track) => {
        try { track.stop() } catch {}
      })
    }
  } catch {}
  try {
    if (handle.video && handle.video.parentNode) {
      handle.video.parentNode.removeChild(handle.video)
    }
  } catch {}
}

export const attachPipCloseListener = (handle) => (handler) => () => {
  if (handle.kind === "document") {
    handle.pipWindow.addEventListener("pagehide", () => { handler() })
    return
  }
  if (handle.kind === "video") {
    handle.video.addEventListener("leavepictureinpicture", () => {
      handler()
    })
  }
}

export const closePipWindow = (handle) => () => {
  if (handle.kind === "document") {
    try {
      handle.pipWindow.close()
    } catch {
      // close() throws when the window has already been closed (e.g.
      // the user dismissed it via the OS chrome a moment ago). The
      // close listener fires for both paths, so swallowing this
      // synchronous exception cannot hide an unobserved failure.
    }
    return
  }
  if (handle.kind === "video") {
    try {
      if (document.pictureInPictureElement === handle.video
        && typeof document.exitPictureInPicture === "function") {
        const exitPromise = document.exitPictureInPicture()
        if (exitPromise && typeof exitPromise.catch === "function") {
          exitPromise.catch(() => {})
        }
      }
    } catch {}
    cleanupVideoPipHandle(handle)
  }
}

export const writePipContent = (handle) => (content) => () => {
  if (handle.kind === "document") {
    writeDocumentPipContent(handle.pipWindow, content)
    return
  }
  if (handle.kind === "video") {
    handle.lastContent = content
    drawVideoPipFrame(handle)
  }
}

const writeDocumentPipContent = (pipWindow, content) => {
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

const drawVideoPipFrame = (handle) => {
  const context = handle.context
  const canvas = handle.canvas
  const content = handle.lastContent
  context.fillStyle = "#0b0d10"
  context.fillRect(0, 0, canvas.width, canvas.height)
  context.fillStyle = "#f3f4f6"
  context.textAlign = "center"
  context.textBaseline = "alphabetic"
  context.font = "bold 96px system-ui, sans-serif"
  context.fillText(String(content.wordsToday), canvas.width / 2, 120)
  context.font = "14px system-ui, sans-serif"
  context.globalAlpha = 0.7
  context.fillText("WORDS TODAY", canvas.width / 2, 148)
  context.globalAlpha = 0.85
  context.font = "16px system-ui, sans-serif"
  context.fillText(String(content.status), canvas.width / 2, 190)
  context.globalAlpha = 1
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
