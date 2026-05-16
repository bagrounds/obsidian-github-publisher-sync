// Thin foreign shims for the Web Speech API. Each export wraps a
// single browser call and surfaces every failure mode through its
// supplied callback — no module-level state, no decisions about when
// to start / stop, no swallowed errors. The PureScript side
// (WordMeter.FFI.Recognition + WordMeter.Capability.Recognition)
// owns instance lifetime and the typed error algebra.

const describeFailure = (error) => {
  if (error == null) return "unknown error"
  if (typeof error === "string") return error
  if (error.name) return String(error.name)
  if (error.message) return String(error.message)
  return String(error)
}

const recognitionConstructor = () => {
  if (typeof window === "undefined") return null
  return window.SpeechRecognition || window.webkitSpeechRecognition || null
}

export const recognitionApiAvailable = () =>
  typeof recognitionConstructor() === "function"

export const constructRecognitionInstance =
  (locale) => (processLocally) => (onConstructed) => (onError) => () => {
    try {
      const Ctor = recognitionConstructor()
      if (!Ctor) {
        onError("no SpeechRecognition constructor")()
        return
      }
      const instance = new Ctor()
      instance.continuous = true
      instance.interimResults = true
      instance.lang = locale
      // `processLocally` is read-only on some Chromium builds; surfacing
      // the assignment failure here would be noise because the language
      // pack pre-flight is the authoritative on-device gate.
      try {
        instance.processLocally = processLocally
      } catch (_ignored) {
        /* read-only on some builds */
      }
      onConstructed(instance)()
    } catch (error) {
      onError(describeFailure(error))()
    }
  }

const supportsOnDeviceLanguagePackApi = (Ctor) =>
  !!Ctor &&
  typeof Ctor.available === "function" &&
  typeof Ctor.install === "function"

export const onDeviceLanguagePackApiAvailable = () => {
  // Calling the static `available()` / `install()` methods in headless
  // browsers without the model installed has been observed to crash
  // the renderer (no language pack -> native helper unreachable).
  // Tests opt out of the pre-flight entirely so the cloud path is
  // exercised deterministically; production browsers always run the
  // full pre-flight.
  if (typeof window !== "undefined" && window.__WM_DISABLE_ON_DEVICE_PREFLIGHT__ === true) {
    return false
  }
  return supportsOnDeviceLanguagePackApi(recognitionConstructor())
}

export const ensureOnDeviceLanguagePackImpl =
  (locale) => (onProgress) => (onAvailable) => (onUnavailable) => () => {
    const finishUnavailable = (kind, detail) =>
      onUnavailable(kind)(detail || "")()
    try {
      const Ctor = recognitionConstructor()
      if (!supportsOnDeviceLanguagePackApi(Ctor)) {
        finishUnavailable("api-absent", "")
        return
      }
      const options = { langs: [locale], processLocally: true }
      Promise.resolve()
        .then(() => Ctor.available(options))
        .then(
          (availability) => {
            if (availability === "available") {
              onAvailable()
              return
            }
            if (availability === "unavailable") {
              finishUnavailable("unsupported-language", "")
              return
            }
            // 'downloadable' or 'downloading' — start install. Fire the
            // progress callback exactly once so the UI can flip its
            // status row.
            onProgress()
            Promise.resolve()
              .then(() => Ctor.install(options))
              .then(
                (installed) => {
                  if (installed) onAvailable()
                  else finishUnavailable("install-failed", "not installed")
                },
                (installError) => {
                  finishUnavailable(
                    "install-failed",
                    describeFailure(installError),
                  )
                },
              )
          },
          (availableError) => {
            finishUnavailable(
              "availability-rejected",
              describeFailure(availableError),
            )
          },
        )
    } catch (error) {
      finishUnavailable("availability-rejected", describeFailure(error))
    }
  }

export const attachOnResult = (instance) => (callback) => () => {
  instance.onresult = (event) => {
    const now = Date.now()
    for (let i = event.resultIndex; i < event.results.length; i++) {
      const result = event.results[i]
      // Strict boolean check: some recognizer implementations have
      // surfaced truthy non-boolean values for isFinal, which would
      // silently let interim guesses leak through a !result.isFinal
      // test.
      if (result.isFinal !== true) continue
      const transcript = ((result[0] && result[0].transcript) || "").trim()
      if (!transcript) continue
      callback(transcript)(now)()
    }
  }
}

export const attachOnError = (instance) => (callback) => () => {
  instance.onerror = (event) => {
    const code = (event && event.error) || ""
    const message = (event && event.message) || ""
    callback(String(code))(String(message))()
  }
}

export const attachOnEnd = (instance) => (callback) => () => {
  instance.onend = () => {
    callback()
  }
}

export const detachHandlers = (instance) => () => {
  instance.onresult = null
  instance.onerror = null
  instance.onend = null
}

export const startRecognitionInstance =
  (instance) => (onStarted) => (onError) => () => {
    try {
      instance.start()
      onStarted()
    } catch (error) {
      onError(describeFailure(error))()
    }
  }

export const stopRecognitionInstance =
  (instance) => (onStopped) => (onError) => () => {
    try {
      instance.stop()
      onStopped()
    } catch (error) {
      onError(describeFailure(error))()
    }
  }
