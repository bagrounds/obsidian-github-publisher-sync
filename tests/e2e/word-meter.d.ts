declare global {
  interface Window {
    __WM_TEST_HOOK__?: boolean
    __wordMeter: {
      simulateFinalTranscript: (transcript: string) => void
      simulateFinalTranscriptAt: (transcript: string, timestamp: number) => void
      start: () => void
      stop: () => void
      startAt: (timestamp: number) => void
      stopAt: (timestamp: number) => void
      tick: (timestamp: number) => void
      getTotalWords: () => number
      getListening: () => boolean
      getVersion: () => string
      getRateShort: () => number
      getRateLong: () => number
      getRateOverall: () => number
      getDurationMs: () => number
      getFirstStartedAt: () => number
      getEventLogLength: () => number
      getEventLogLimit: () => number
      getDiagnosticsText: () => string
      getDiagnosticsLength: () => number
      getDiagnosticsLimit: () => number
      getCopyStatus: () => string
      requestCopyDiagnostics: () => void
      reset: () => void
      resetAt: (timestamp: number) => void
      persistNow: () => void
      getKeepAwake: () => boolean
      setKeepAwake: (enabled: boolean) => void
      getKeepAwakeStatus: () => string
      getWakeLockHeld: () => boolean
      simulateVisibilityVisible: () => void
      simulateRecognitionError: (code: string, message?: string) => void
      getErrorBanner: () => string
      setCloudFallbackAttempted: (attempted: boolean) => void
    }
  }
}

export {}
