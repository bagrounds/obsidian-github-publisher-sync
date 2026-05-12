module WordMeter.Recording
  ( Session
  , Caption
  , WordEvent
  , LoggedInterval
  , Action(..)
  , Dispatch
  , Handlers
  , initialSession
  , reduce
  , view
  , captionWindowMs
  , minimumCaptionOpacity
  , eventLogLimit
  , shortWindowMs
  , longWindowMs
  , activeListeningMs
  , wallSpanMs
  , wordsInTrailingWindow
  , ratePerMinute
  , intervalRate
  , intervalDurationMs
  , captionOpacity
  , shortRate
  , longRate
  , overallRate
  , formatRate
  , formatDurationMs
  ) where

import Prelude

import Data.Array (filter, foldl, takeEnd)
import Data.Array (length) as Array
import Data.Int as Int
import Data.Maybe (Maybe(..))
import Data.Number (isFinite)
import Effect (Effect)
import WordMeter.Clock (formatClockTime)
import WordMeter.Vdom (Node, button, buttonType, div_, onClick, span_, style, testId, text)
import WordMeter.Version (version)
import WordMeter.Words (countWords)

type Session =
  { listening :: Boolean
  , totalWords :: Int
  , captions :: Array Caption
  , wordEvents :: Array WordEvent
  , eventLog :: Array LoggedInterval
  , currentIntervalWords :: Int
  , firstStartedAt :: Maybe Number
  , currentIntervalStart :: Maybe Number
  , completedActiveMs :: Number
  , now :: Number
  , lastError :: Maybe String
  }

type Caption =
  { transcript :: String
  , wordCount :: Int
  , timestamp :: Number
  }

type WordEvent =
  { timestamp :: Number
  , wordCount :: Int
  }

-- | One completed counting session: a single start-to-stop listening
-- | interval, with the word count accumulated while listening. WPM is
-- | derived on demand from `intervalRate`, not stored.
type LoggedInterval =
  { startedAt :: Number
  , endedAt :: Number
  , wordCount :: Int
  }

captionWindowMs :: Number
captionWindowMs = 30000.0

minimumCaptionOpacity :: Number
minimumCaptionOpacity = 0.15

eventLogLimit :: Int
eventLogLimit = 200

shortWindowMs :: Number
shortWindowMs = 60000.0

longWindowMs :: Number
longWindowMs = 600000.0

millisecondsPerMinute :: Number
millisecondsPerMinute = 60000.0

millisecondsPerSecond :: Number
millisecondsPerSecond = 1000.0

data Action
  = Toggle Number
  | InjectFinalTranscript String Number
  | Tick Number

type Dispatch = Action -> Effect Unit

type Handlers =
  { requestToggle :: Effect Unit
  }

initialSession :: Session
initialSession =
  { listening: false
  , totalWords: 0
  , captions: []
  , wordEvents: []
  , eventLog: []
  , currentIntervalWords: 0
  , firstStartedAt: Nothing
  , currentIntervalStart: Nothing
  , completedActiveMs: 0.0
  , now: 0.0
  , lastError: Nothing
  }

reduce :: Action -> Session -> Session
reduce (Toggle timestamp) session
  | session.listening =
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
      in
        session
          { listening = false
          , currentIntervalStart = Nothing
          , currentIntervalWords = 0
          , completedActiveMs = session.completedActiveMs + closedInterval
          , wordEvents = pruneEvents timestamp session.wordEvents
          , captions = pruneCaptions timestamp session.captions
          , eventLog = takeEnd eventLogLimit (session.eventLog <> [ completed ])
          , now = timestamp
          }
  | otherwise =
      session
        { listening = true
        , currentIntervalStart = Just timestamp
        , currentIntervalWords = 0
        , firstStartedAt = case session.firstStartedAt of
            Just t -> Just t
            Nothing -> Just timestamp
        , wordEvents = pruneEvents timestamp session.wordEvents
        , captions = pruneCaptions timestamp session.captions
        , now = timestamp
        }
reduce (InjectFinalTranscript transcript timestamp) session
  | session.listening =
      let
        wordCount = countWords transcript
        prunedEvents = pruneEvents timestamp session.wordEvents
        prunedCaptions = pruneCaptions timestamp session.captions
      in
        if wordCount == 0 then session
          { now = timestamp
          , wordEvents = prunedEvents
          , captions = prunedCaptions
          }
        else session
          { totalWords = session.totalWords + wordCount
          , currentIntervalWords = session.currentIntervalWords + wordCount
          , captions = prunedCaptions <> [ { transcript, wordCount, timestamp } ]
          , wordEvents = prunedEvents <> [ { timestamp, wordCount } ]
          , now = timestamp
          }
  | otherwise = session
      { now = timestamp
      , captions = pruneCaptions timestamp session.captions
      }
reduce (Tick timestamp) session = session
  { now = timestamp
  , wordEvents = pruneEvents timestamp session.wordEvents
  , captions = pruneCaptions timestamp session.captions
  }

pruneEvents :: Number -> Array WordEvent -> Array WordEvent
pruneEvents nowMs = filter (\event -> event.timestamp >= nowMs - longWindowMs)

pruneCaptions :: Number -> Array Caption -> Array Caption
pruneCaptions nowMs = filter (\caption -> caption.timestamp >= nowMs - captionWindowMs)

activeListeningMs :: Session -> Number
activeListeningMs session =
  session.completedActiveMs + case session.currentIntervalStart of
    Just start -> max 0.0 (session.now - start)
    Nothing -> 0.0

wallSpanMs :: Session -> Number
wallSpanMs session = case session.firstStartedAt of
  Nothing -> 0.0
  Just first -> max 0.0 (session.now - first)

wordsInTrailingWindow :: Number -> Session -> Int
wordsInTrailingWindow windowMs session =
  let
    cutoff = session.now - windowMs
    inWindow event = event.timestamp >= cutoff
  in
    foldl (\acc event -> acc + event.wordCount) 0
      (filter inWindow session.wordEvents)

ratePerMinute :: Int -> Number -> Number
ratePerMinute wordCount elapsedMs
  | elapsedMs <= 0.0 = 0.0
  | otherwise = Int.toNumber wordCount * millisecondsPerMinute / elapsedMs

intervalDurationMs :: LoggedInterval -> Number
intervalDurationMs interval = max 0.0 (interval.endedAt - interval.startedAt)

intervalRate :: LoggedInterval -> Number
intervalRate interval =
  ratePerMinute interval.wordCount (max 1.0 (intervalDurationMs interval))

captionOpacity :: Number -> Number -> Number
captionOpacity nowMs captionTimestamp =
  let
    ageFraction = max 0.0 (nowMs - captionTimestamp) / captionWindowMs
  in
    max minimumCaptionOpacity (1.0 - ageFraction)

shortRate :: Session -> Number
shortRate session =
  let
    elapsed = min shortWindowMs (max 1.0 (wallSpanMs session))
  in
    ratePerMinute (wordsInTrailingWindow shortWindowMs session) elapsed

longRate :: Session -> Number
longRate session =
  let
    elapsed = min longWindowMs (max 1.0 (wallSpanMs session))
  in
    ratePerMinute (wordsInTrailingWindow longWindowMs session) elapsed

overallRate :: Session -> Number
overallRate session =
  ratePerMinute session.totalWords (max 1.0 (activeListeningMs session))

formatRate :: Number -> String
formatRate rate
  | not (isFinite rate) = "0"
  | rate <= 0.0 = "0"
  | rate >= 100.0 = show (Int.round rate)
  | otherwise =
      let
        scaled = Int.round (rate * 10.0)
        wholePart = scaled `div` 10
        fracPart = scaled `mod` 10
      in
        show wholePart <> "." <> show fracPart

formatDurationMs :: Number -> String
formatDurationMs ms =
  let
    totalSeconds = max 0 (Int.floor (ms / millisecondsPerSecond))
  in
    if totalSeconds < 60 then show totalSeconds <> "s"
    else
      let
        totalMinutes = totalSeconds `div` 60
        seconds = totalSeconds `mod` 60
      in
        if totalMinutes < 60 then show totalMinutes <> "m " <> show seconds <> "s"
        else
          let
            hours = totalMinutes `div` 60
            minutes = totalMinutes `mod` 60
          in
            show hours <> "h " <> show minutes <> "m"

view :: Handlers -> Session -> Node
view handlers session =
  div_
    [ testId "wm-root" ]
    [ style "font-family" "system-ui, -apple-system, sans-serif"
    , style "padding" "16px"
    , style "border-radius" "12px"
    , style "background" "#0b1220"
    , style "color" "#e6edf3"
    , style "max-width" "420px"
    ]
    [ buildTag
    , buildStatus session
    , buildCount session
    , buildCountLabel
    , buildToggle handlers session
    , buildStats session
    , buildCaptions session
    , buildEventLog session
    , buildVersion
    ]

buildTag :: Node
buildTag =
  div_ [ testId "wm-build" ]
    [ style "font-size" "12px"
    , style "letter-spacing" "0.08em"
    , style "text-transform" "uppercase"
    , style "color" "#7aa2f7"
    ]
    [ text "PureScript build" ]

buildStatus :: Session -> Node
buildStatus session =
  div_ [ testId "wm-status" ]
    [ style "font-size" "13px"
    , style "color" "#9aa5b1"
    , style "margin" "6px 0 4px"
    ]
    [ text (if session.listening then "Listening" else "Idle") ]

buildCount :: Session -> Node
buildCount session =
  div_ [ testId "wm-count" ]
    [ style "font-size" "48px"
    , style "font-variant-numeric" "tabular-nums"
    , style "margin" "4px 0"
    ]
    [ text (show session.totalWords) ]

buildCountLabel :: Node
buildCountLabel =
  div_ [ testId "wm-count-label" ]
    [ style "font-size" "14px"
    , style "color" "#9aa5b1"
    ]
    [ text "words counted" ]

buildToggle :: Handlers -> Session -> Node
buildToggle handlers session =
  button
    [ testId "wm-toggle", buttonType "button" ]
    [ style "margin-top" "12px"
    , style "padding" "10px 18px"
    , style "border" "0"
    , style "border-radius" "999px"
    , style "background" (if session.listening then "#a85f5f" else "#1f6feb")
    , style "color" "white"
    , style "cursor" "pointer"
    , style "font" "inherit"
    ]
    [ onClick handlers.requestToggle ]
    [ text (if session.listening then "Stop counting" else "Start counting") ]

buildStats :: Session -> Node
buildStats session =
  div_ [ testId "wm-stats" ]
    [ style "display" "grid"
    , style "grid-template-columns" "repeat(auto-fit,minmax(120px,1fr))"
    , style "gap" "10px"
    , style "margin-top" "14px"
    , style "padding-top" "10px"
    , style "border-top" "1px solid rgba(255,255,255,0.08)"
    ]
    [ buildStatTile "wm-rate-short" "Last 1 min" (formatRate (shortRate session)) (Just "words / minute")
    , buildStatTile "wm-rate-long" "Last 10 min" (formatRate (longRate session)) (Just "words / minute")
    , buildStatTile "wm-rate-overall" "Overall" (formatRate (overallRate session)) (Just "words / minute")
    , buildStatTile "wm-duration" "Duration" (formatDurationMs (activeListeningMs session)) (Just "listening time")
    , buildStatTile "wm-started" "Started" (startedLabel session) Nothing
    ]

buildStatTile :: String -> String -> String -> Maybe String -> Node
buildStatTile valueTestId label valueText maybeSublabel =
  div_ []
    [ style "background" "rgba(255,255,255,0.04)"
    , style "border-radius" "10px"
    , style "padding" "10px"
    , style "text-align" "center"
    ]
    ([ statTileLabel label
     , statTileValue valueTestId valueText
     ] <> case maybeSublabel of
        Just sublabel -> [ statTileSublabel sublabel ]
        Nothing -> [])

statTileLabel :: String -> Node
statTileLabel label =
  div_ []
    [ style "font-size" "11px"
    , style "letter-spacing" "0.08em"
    , style "text-transform" "uppercase"
    , style "color" "#9aa5b1"
    ]
    [ text label ]

statTileValue :: String -> String -> Node
statTileValue valueTestId valueText =
  div_ [ testId valueTestId ]
    [ style "font-size" "20px"
    , style "font-weight" "600"
    , style "margin-top" "2px"
    , style "font-variant-numeric" "tabular-nums"
    , style "color" "#e6edf3"
    ]
    [ text valueText ]

statTileSublabel :: String -> Node
statTileSublabel sublabel =
  div_ []
    [ style "font-size" "11px"
    , style "color" "#9aa5b1"
    ]
    [ text sublabel ]

startedLabel :: Session -> String
startedLabel session = case session.firstStartedAt of
  Nothing -> "—"
  Just timestamp -> formatClockTime timestamp

buildCaptions :: Session -> Node
buildCaptions session =
  div_ [ testId "wm-captions" ]
    [ style "margin-top" "14px"
    , style "padding-top" "10px"
    , style "border-top" "1px solid rgba(255,255,255,0.08)"
    , style "display" "flex"
    , style "flex-direction" "column"
    , style "gap" "4px"
    , style "min-height" "20px"
    ]
    (if Array.length session.captions == 0
      then [ buildCaptionsPlaceholder ]
      else map (buildCaption session.now) session.captions)

buildCaptionsPlaceholder :: Node
buildCaptionsPlaceholder =
  div_ [ testId "wm-captions-placeholder" ]
    [ style "font-size" "12px"
    , style "color" "#7d8590"
    , style "font-style" "italic"
    ]
    [ text "Waiting for speech…" ]

buildCaption :: Number -> Caption -> Node
buildCaption nowMs caption =
  div_ [ testId "wm-caption" ]
    [ style "font-size" "13px"
    , style "color" "#c9d1d9"
    , style "line-height" "1.3"
    , style "opacity" (show (captionOpacity nowMs caption.timestamp))
    ]
    [ text caption.transcript ]

buildEventLog :: Session -> Node
buildEventLog session =
  div_ [ testId "wm-event-log" ]
    [ style "margin-top" "14px"
    , style "padding-top" "10px"
    , style "border-top" "1px solid rgba(255,255,255,0.08)"
    , style "display" "flex"
    , style "flex-direction" "column"
    , style "gap" "4px"
    , style "max-height" "220px"
    , style "overflow-y" "auto"
    ]
    (if Array.length session.eventLog == 0
      then [ buildEventLogPlaceholder ]
      else map buildEventLogEntry session.eventLog)

buildEventLogPlaceholder :: Node
buildEventLogPlaceholder =
  div_ [ testId "wm-event-log-placeholder" ]
    [ style "font-size" "12px"
    , style "color" "#7d8590"
    , style "font-style" "italic"
    ]
    [ text "(no counting sessions yet — press Start counting to begin)" ]

buildEventLogEntry :: LoggedInterval -> Node
buildEventLogEntry interval =
  div_ [ testId "wm-event-log-entry" ]
    [ style "display" "flex"
    , style "justify-content" "space-between"
    , style "align-items" "baseline"
    , style "gap" "8px"
    , style "padding" "6px 0"
    , style "border-top" "1px solid rgba(255,255,255,0.04)"
    , style "font-size" "13px"
    ]
    [ eventLogEntryStarted interval.startedAt
    , eventLogEntryDuration (intervalDurationMs interval)
    , eventLogEntryWords interval.wordCount
    , eventLogEntryRate (intervalRate interval)
    ]

eventLogEntryStarted :: Number -> Node
eventLogEntryStarted startedAt =
  span_ [ testId "wm-event-log-entry-started" ]
    [ style "font-variant-numeric" "tabular-nums"
    , style "color" "#9aa5b1"
    , style "min-width" "72px"
    ]
    [ text (formatClockTime startedAt) ]

eventLogEntryDuration :: Number -> Node
eventLogEntryDuration durationMs =
  span_ [ testId "wm-event-log-entry-duration" ]
    [ style "font-variant-numeric" "tabular-nums"
    , style "color" "#c9d1d9"
    , style "flex" "1"
    , style "text-align" "center"
    ]
    [ text (formatDurationMs durationMs) ]

eventLogEntryWords :: Int -> Node
eventLogEntryWords wordCount =
  span_ [ testId "wm-event-log-entry-words" ]
    [ style "font-variant-numeric" "tabular-nums"
    , style "color" "#e6edf3"
    , style "min-width" "56px"
    , style "text-align" "right"
    ]
    [ text (show wordCount <> " w") ]

eventLogEntryRate :: Number -> Node
eventLogEntryRate rate =
  span_ [ testId "wm-event-log-entry-rate" ]
    [ style "font-variant-numeric" "tabular-nums"
    , style "color" "#9aa5b1"
    , style "min-width" "64px"
    , style "text-align" "right"
    ]
    [ text (formatRate rate <> " wpm") ]

buildVersion :: Node
buildVersion =
  span_ [ testId "wm-version" ]
    [ style "display" "block"
    , style "margin-top" "12px"
    , style "font-size" "11px"
    , style "color" "#7d8590"
    ]
    [ text ("Word Meter (PureScript) v" <> version) ]
