module WordMeter.Recording.Reducer
  ( Action(..)
  , Dispatch
  , Handlers
  , reduce
  , toPersistedData
  ) where

import Prelude

import Data.Array (filter, takeEnd, unsnoc)
import Data.Maybe (Maybe(..))
import Effect (Effect)
import WordMeter.Diagnostics (EnvironmentSnapshot, recordEntry)
import WordMeter.Recognition.Delta
  ( TranscriptIntegration(..)
  , classifyFinalizedTranscript
  )
import WordMeter.Recognition.Path (RecognitionPath)
import WordMeter.RecognitionError
  ( RecognitionErrorCode
  , classifyRecognitionError
  , isPermissionDenied
  , isTransient
  , recognitionErrorBannerText
  , renderRecognitionErrorDiagnosticDetail
  )
import WordMeter.Recording.Math (formatDurationMs)
import WordMeter.Recording.Session
  ( Caption
  , LoggedInterval
  , PersistedData
  , Session
  , WakeLockState(..)
  , WordEvent
  , captionWindowMs
  , eventLogLimit
  , idleErrorBanner
  , idleRecognitionStatusOverride
  , initialSession
  , longWindowMs
  )
import WordMeter.Words (countWords)

data Action
  = Toggle Number
  | InjectFinalTranscript String Number
  | IntegrateFinalizedTranscript Number String
  | ResetRecognitionDedupState
  | Tick Number
  | RecordDiagnostic Number String String
  | SetEnvironment EnvironmentSnapshot
  | SetCopyStatus String
  | Reset Number
  | LoadSession PersistedData
  | SetKeepAwake Boolean
  | SetWakeLockState WakeLockState
  | HandleRecognitionError Number String String
  | ClearErrorBanner
  | SetRecognitionStatusOverride String
  | SetCloudFallbackAttempted Boolean
  | SetActiveRecognitionPath (Maybe RecognitionPath)
  | SetDiagnosticsDrawerOpen Boolean

type Dispatch = Action -> Effect Unit

type Handlers =
  { requestToggle :: Effect Unit
  , requestCopyDiagnostics :: Effect Unit
  , requestReset :: Effect Unit
  , requestSetKeepAwake :: Boolean -> Effect Unit
  , requestToggleDiagnosticsDrawer :: Effect Unit
  }

reduce :: Action -> Session -> Session
reduce (Toggle timestamp) session
  | session.listening = stopListeningAt timestamp "stop counting" "" session
  | otherwise =
      let
        startEntry =
          { timestamp, label: "start counting", detail: "" }
      in
        session
          { listening = true
          , currentIntervalStart = Just timestamp
          , currentIntervalWords = 0
          , firstStartedAt = case session.firstStartedAt of
              Just t -> Just t
              Nothing -> Just timestamp
          , wordEvents = pruneWordEvents timestamp session.wordEvents
          , captions = pruneCaptions timestamp session.captions
          , now = timestamp
          , diagnostics = recordEntry startEntry session.diagnostics
          , errorBanner = idleErrorBanner
          , lastRawFinalizedTranscript = ""
          , recognitionStatusOverride = idleRecognitionStatusOverride
          , cloudFallbackAttempted = false
          , activeRecognitionPath = Nothing
          }
reduce (InjectFinalTranscript transcript timestamp) session
  | session.listening =
      let
        wordCount = countWords transcript
        prunedEvents = pruneWordEvents timestamp session.wordEvents
        prunedCaptions = pruneCaptions timestamp session.captions
      in
        if wordCount == 0 then session
          { now = timestamp
          , wordEvents = prunedEvents
          , captions = prunedCaptions
          }
        else
          let
            transcriptEntry =
              { timestamp
              , label: "final transcript"
              , detail: "words=" <> show wordCount
              }
          in
            session
              { totalWords = session.totalWords + wordCount
              , currentIntervalWords = session.currentIntervalWords + wordCount
              , captions = prunedCaptions <> [ { transcript, wordCount, timestamp } ]
              , wordEvents = prunedEvents <> [ { timestamp, wordCount } ]
              , now = timestamp
              , diagnostics = recordEntry transcriptEntry session.diagnostics
              }
  | otherwise = session
      { now = timestamp
      , captions = pruneCaptions timestamp session.captions
      }
reduce (IntegrateFinalizedTranscript timestamp transcript) session
  | not session.listening = session { now = timestamp }
  | otherwise =
      let
        decision = classifyFinalizedTranscript
          { previous: session.lastRawFinalizedTranscript
          , incoming: transcript
          }
        prunedEvents = pruneWordEvents timestamp session.wordEvents
        prunedCaptions = pruneCaptions timestamp session.captions
        base = session
          { now = timestamp
          , wordEvents = prunedEvents
          , captions = prunedCaptions
          }
      in case decision of
        IgnoreDuplicate -> base
          { captions = refreshLastCaptionTimestamp timestamp prunedCaptions
          }
        IgnoreEarlierSnapshot -> base
        ExtendUtterance fields ->
          let
            extendedCaptions = appendOrExtendCaption fields.caption fields.wordDelta
              timestamp prunedCaptions
            transcriptEntry =
              { timestamp
              , label: "final transcript"
              , detail: "extend wordDelta=" <> show fields.wordDelta
              }
          in
            base
              { totalWords = session.totalWords + fields.wordDelta
              , currentIntervalWords =
                  session.currentIntervalWords + fields.wordDelta
              , captions = extendedCaptions
              , wordEvents = prunedEvents
                  <> [ { timestamp, wordCount: fields.wordDelta } ]
              , lastRawFinalizedTranscript = transcript
              , diagnostics = recordEntry transcriptEntry session.diagnostics
              }
        StartNewUtterance fields ->
          let
            transcriptEntry =
              { timestamp
              , label: "final transcript"
              , detail: "words=" <> show fields.wordCount
              }
          in
            base
              { totalWords = session.totalWords + fields.wordCount
              , currentIntervalWords =
                  session.currentIntervalWords + fields.wordCount
              , captions = prunedCaptions
                  <>
                    [ { transcript: fields.caption
                      , wordCount: fields.wordCount
                      , timestamp
                      }
                    ]
              , wordEvents = prunedEvents
                  <> [ { timestamp, wordCount: fields.wordCount } ]
              , lastRawFinalizedTranscript = transcript
              , diagnostics = recordEntry transcriptEntry session.diagnostics
              }
reduce ResetRecognitionDedupState session = session
  { lastRawFinalizedTranscript = ""
  }
reduce (Tick timestamp) session = session
  { now = timestamp
  , wordEvents = pruneWordEvents timestamp session.wordEvents
  , captions = pruneCaptions timestamp session.captions
  }
reduce (RecordDiagnostic timestamp label detail) session = session
  { diagnostics = recordEntry { timestamp, label, detail } session.diagnostics
  }
reduce (SetEnvironment snapshot) session = session
  { environment = Just snapshot
  }
reduce (SetCopyStatus message) session = session
  { copyStatus = message
  }
reduce (Reset timestamp) session =
  let
    resetEntry =
      { timestamp, label: "reset", detail: "stats cleared" }
  in
    initialSession
      { now = timestamp
      , diagnostics = recordEntry resetEntry session.diagnostics
      , environment = session.environment
      , keepAwake = session.keepAwake
      }
reduce (LoadSession persisted) session = session
  { totalWords = max 0 persisted.totalWords
  , firstStartedAt = persisted.firstStartedAt
  , wordEvents = persisted.wordEvents
  , eventLog = takeEnd eventLogLimit persisted.eventLog
  , currentIntervalWords = 0
  , currentIntervalStart = Nothing
  , listening = false
  }
reduce (SetKeepAwake enabled) session = session
  { keepAwake = enabled
  , wakeLockState = if enabled then session.wakeLockState else WakeLockIdle
  }
reduce (SetWakeLockState state) session = session
  { wakeLockState = state
  }
reduce (HandleRecognitionError timestamp code message) session =
  let
    classified :: RecognitionErrorCode
    classified = classifyRecognitionError code
    errorEntry =
      { timestamp
      , label: "recognition.onerror"
      , detail: renderRecognitionErrorDiagnosticDetail code message
      }
    sessionWithDiagnostic = session
      { diagnostics = recordEntry errorEntry session.diagnostics
      , now = timestamp
      }
    bannerText = recognitionErrorBannerText classified
  in
    if isTransient classified then sessionWithDiagnostic
    else if isPermissionDenied classified && sessionWithDiagnostic.listening then
      let
        stopped = stopListeningAt timestamp "session ended"
          "reason=permission denied" sessionWithDiagnostic
      in
        stopped { errorBanner = bannerText }
    else
      sessionWithDiagnostic { errorBanner = bannerText }
reduce ClearErrorBanner session = session
  { errorBanner = idleErrorBanner
  }
reduce (SetRecognitionStatusOverride statusText) session = session
  { recognitionStatusOverride = statusText
  }
reduce (SetCloudFallbackAttempted attempted) session = session
  { cloudFallbackAttempted = attempted
  }
reduce (SetActiveRecognitionPath path) session = session
  { activeRecognitionPath = path
  }
reduce (SetDiagnosticsDrawerOpen open) session = session
  { diagnosticsDrawerOpen = open
  }

-- | Close the currently open counting interval, append it to the event
-- | log, prune captions/events, and record a stop-style diagnostic
-- | entry. Used by both the user-driven Toggle and the
-- | permission-denied branch of `HandleRecognitionError` so the audit
-- | trail is identical in both cases.
stopListeningAt :: Number -> String -> String -> Session -> Session
stopListeningAt timestamp label reasonDetail session =
  let
    startedAt = case session.currentIntervalStart of
      Just start -> start
      Nothing -> timestamp
    closedInterval = max 0.0 (timestamp - startedAt)
    completed =
      { startedAt
      , endedAt: max timestamp startedAt
      , wordCount: session.currentIntervalWords
      }
    statsDetail =
      "words=" <> show session.currentIntervalWords
        <> " duration=" <> formatDurationMs closedInterval
    fullDetail =
      if reasonDetail == "" then statsDetail
      else statsDetail <> " " <> reasonDetail
    stopEntry = { timestamp, label, detail: fullDetail }
  in
    session
      { listening = false
      , currentIntervalStart = Nothing
      , currentIntervalWords = 0
      , completedActiveMs = session.completedActiveMs + closedInterval
      , wordEvents = pruneWordEvents timestamp session.wordEvents
      , captions = pruneCaptions timestamp session.captions
      , eventLog = takeEnd eventLogLimit (session.eventLog <> [ completed ])
      , now = timestamp
      , diagnostics = recordEntry stopEntry session.diagnostics
      , recognitionStatusOverride = idleRecognitionStatusOverride
      , activeRecognitionPath = Nothing
      }

toPersistedData :: Session -> PersistedData
toPersistedData session =
  { totalWords: session.totalWords
  , firstStartedAt: session.firstStartedAt
  , wordEvents: session.wordEvents
  , eventLog: session.eventLog
  }

pruneWordEvents :: Number -> Array WordEvent -> Array WordEvent
pruneWordEvents nowMs = filter (\event -> event.timestamp >= nowMs - longWindowMs)

pruneCaptions :: Number -> Array Caption -> Array Caption
pruneCaptions nowMs = filter (\caption -> caption.timestamp >= nowMs - captionWindowMs)

-- | Refresh the timestamp of the most recent caption (if any) so the
-- | live captions panel keeps a duplicate-finalized utterance from
-- | aging out while the recognizer keeps re-emitting it.
refreshLastCaptionTimestamp :: Number -> Array Caption -> Array Caption
refreshLastCaptionTimestamp nowMs captions = case unsnoc captions of
  Nothing -> captions
  Just { init, last } -> init <> [ last { timestamp = nowMs } ]

-- | Replace the most recent caption with the refined transcript when
-- | the recognizer extends an in-flight utterance, or append a new
-- | one when no captions remain in the window. Mirrors the legacy
-- | `session.captionEntries[session.captionEntries.length - 1] = …`
-- | branch.
appendOrExtendCaption
  :: String -> Int -> Number -> Array Caption -> Array Caption
appendOrExtendCaption caption wordDelta nowMs captions = case unsnoc captions of
  Nothing ->
    captions <> [ { transcript: caption, wordCount: wordDelta, timestamp: nowMs } ]
  Just { init, last } ->
    init <>
      [ { transcript: caption
        , wordCount: last.wordCount + wordDelta
        , timestamp: nowMs
        }
      ]
