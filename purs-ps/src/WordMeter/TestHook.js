export const installTestHook = (api) => () => {
  if (typeof window === "undefined") return
  window.__wordMeter = {
    simulateFinalTranscript: (transcript) =>
      api.simulateFinalTranscript(transcript)(),
    simulateFinalTranscriptAt: (transcript, timestamp) =>
      api.simulateFinalTranscriptAt(transcript)(timestamp)(),
    start: () => api.start(),
    stop: () => api.stop(),
    startAt: (timestamp) => api.startAt(timestamp)(),
    stopAt: (timestamp) => api.stopAt(timestamp)(),
    tick: (timestamp) => api.tick(timestamp)(),
    getTotalWords: () => api.getTotalWords(),
    getListening: () => api.getListening(),
    getVersion: () => api.getVersion(),
    getRateShort: () => api.getRateShort(),
    getRateLong: () => api.getRateLong(),
    getRateOverall: () => api.getRateOverall(),
    getDurationMs: () => api.getDurationMs(),
    getFirstStartedAt: () => api.getFirstStartedAt(),
    getEventLogLength: () => api.getEventLogLength(),
    getEventLogLimit: () => api.getEventLogLimit(),
    getDiagnosticsText: () => api.getDiagnosticsText(),
    getDiagnosticsLength: () => api.getDiagnosticsLength(),
    getDiagnosticsLimit: () => api.getDiagnosticsLimit(),
    getCopyStatus: () => api.getCopyStatus(),
    requestCopyDiagnostics: () => api.requestCopyDiagnostics(),
    reset: () => api.reset(),
    resetAt: (timestamp) => api.resetAt(timestamp)(),
    persistNow: () => api.persistNow(),
    getKeepAwake: () => api.getKeepAwake(),
    setKeepAwake: (enabled) => api.setKeepAwake(!!enabled)(),
    getKeepAwakeStatus: () => api.getKeepAwakeStatus(),
    getWakeLockHeld: () => api.getWakeLockHeld(),
    simulateVisibilityVisible: () => api.simulateVisibilityVisible(),
    simulateRecognitionError: (code, message) =>
      api.simulateRecognitionError(String(code == null ? "" : code))(
        String(message == null ? "" : message),
      )(),
    getErrorBanner: () => api.getErrorBanner(),
  }
}
