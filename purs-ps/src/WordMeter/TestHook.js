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
  }
}
