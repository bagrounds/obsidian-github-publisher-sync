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
  (locale) => (onConstructed) => (onError) => () => {
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
      onConstructed(instance)()
    } catch (error) {
      onError(describeFailure(error))()
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
