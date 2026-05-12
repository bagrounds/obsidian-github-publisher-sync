declare global {
  interface Window {
    __WM_TEST_HOOK__?: boolean
    __wordMeter: {
      simulateFinalTranscript: (transcript: string) => void
      start: () => void
      stop: () => void
      getTotalWords: () => number
      getListening: () => boolean
      getVersion: () => string
    }
  }
}

export {}
