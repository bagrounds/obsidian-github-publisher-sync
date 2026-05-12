export const installTestHookImpl = (api) => () => {
  if (typeof window === "undefined") return
  window.__wordMeter = {
    simulateFinalTranscript: (transcript) => api.simulateFinalTranscript(transcript)(),
    start: () => api.start(),
    stop: () => api.stop(),
    getTotalWords: () => api.getTotalWords(),
    getListening: () => api.getListening(),
    getVersion: () => api.getVersion(),
  }
}
