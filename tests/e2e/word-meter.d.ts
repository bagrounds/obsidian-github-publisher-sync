declare global {
  interface Window {
    __WM_TEST_HOOK__?: boolean;
    __wordMeter: {
      simulateFinalTranscript: (transcript: string) => void;
      simulateFinalTranscriptAt: (
        transcript: string,
        timestamp: number,
      ) => void;
      start: () => void;
      stop: () => void;
      startAt: (timestamp: number) => void;
      stopAt: (timestamp: number) => void;
      tick: (timestamp: number) => void;
      getTotalWords: () => number;
      getListening: () => boolean;
      getVersion: () => string;
      getRateShort: () => number;
      getRateLong: () => number;
      getRateOverall: () => number;
      getDurationMs: () => number;
      getFirstStartedAt: () => number;
    };
  }
}

export {};
