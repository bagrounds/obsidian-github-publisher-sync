module WordMeter.Recording.View
  ( view
  , diagnosticsText
  ) where

import Prelude

import Data.DateTime.Instant (Instant)
import Data.Array (head, length, null) as Array
import Data.Int as Int
import Data.Maybe (Maybe(..))
import Data.String (length) as String
import WordMeter.Clock (formatClockTime)
import WordMeter.Diagnostics (formatDiagnostics)
import WordMeter.Recording.Math
  ( activeListeningMs
  , captionOpacity
  , formatDurationMs
  , formatPercent
  , formatRate
  , intervalDurationMs
  , intervalRate
  , longRate
  , overallRate
  , sampleFraction
  , shortRate
  , wordsPerDay
  )
import WordMeter.Recording.Reducer (Handlers)
import WordMeter.Recording.Session
  ( Caption
  , LoggedInterval
  , Session
  , renderWakeLockStatus
  )
import WordMeter.WordStats (WordFrequency, longestWord, mostFrequentWord, topWords)
import WordMeter.Version (version)
import WordMeter.Vdom
  ( Node
  , attribute
  , button
  , buttonType
  , className
  , details_
  , div_
  , input
  , label_
  , onCheckboxChange
  , onClick
  , pre_
  , span_
  , summary_
  , testId
  , text
  )

-- | Per-caption fade is bucketed into discrete classes so the application
-- | only ever applies a class — never sets a style. The buckets approximate
-- | the continuous fade computed by `captionOpacity`.
captionFadeBucketCount :: Int
captionFadeBucketCount = 5

captionFadeClass :: Instant -> Instant -> String
captionFadeClass nowInstant timestamp =
  let
    opacity = captionOpacity nowInstant timestamp
    fraction = 1.0 - opacity
    rawBucket = Int.floor (fraction * Int.toNumber captionFadeBucketCount)
    bucket =
      if rawBucket < 0 then 0
      else if rawBucket >= captionFadeBucketCount then captionFadeBucketCount - 1
      else rawBucket
  in
    "wm-caption wm-caption-fade-" <> show bucket

view :: Handlers -> Session -> Node
view handlers session =
  div_
    [ testId "wm-root", className "wm-panel" ]
    []
    [ buildTag
    , buildStatus session
    , buildCount session
    , buildCountLabel
    , buildToggle handlers session
    , buildReset handlers
    , buildKeepAwake handlers session
    , buildErrorBanner session
    , buildStats session
    , buildWordCloud session
    , buildCaptions session
    , buildEventLog session
    , buildDiagnostics handlers session
    , buildVersion
    ]

diagnosticsText :: Session -> String
diagnosticsText session = formatDiagnostics session.environment session.diagnostics

buildTag :: Node
buildTag =
  div_ [ testId "wm-build", className "wm-build-badge" ] []
    [ text "PureScript build" ]

buildStatus :: Session -> Node
buildStatus session =
  div_ [ testId "wm-status", className "wm-status" ] []
    [ text (renderStatus session) ]

renderStatus :: Session -> String
renderStatus session
  | session.recognitionStatusOverride /= "" = session.recognitionStatusOverride
  | session.listening = "Listening"
  | otherwise = "Idle"

buildCount :: Session -> Node
buildCount session =
  div_ [ testId "wm-count", className "wm-count" ] []
    [ text (show session.wordsToday) ]

buildCountLabel :: Node
buildCountLabel =
  div_ [ testId "wm-count-label", className "wm-count-label" ] []
    [ text "words today" ]

buildToggle :: Handlers -> Session -> Node
buildToggle handlers session =
  button
    [ testId "wm-toggle"
    , buttonType "button"
    , className
        ( "wm-button-pill "
            <> (if session.listening then "wm-button-pill-stop" else "wm-button-pill-start")
        )
    ]
    []
    [ onClick handlers.requestToggle ]
    [ text (if session.listening then "Stop counting" else "Start counting") ]

buildReset :: Handlers -> Node
buildReset handlers =
  button
    [ testId "wm-reset"
    , buttonType "button"
    , className "wm-button-pill-secondary"
    ]
    []
    [ onClick handlers.requestReset ]
    [ text "Reset" ]

buildKeepAwake :: Handlers -> Session -> Node
buildKeepAwake handlers session =
  div_ [ className "wm-keep-awake-row" ] []
    [ label_
        [ testId "wm-keep-awake-label"
        , className
            ( "wm-keep-awake-label"
                <> (if session.listening then " wm-keep-awake-label-disabled" else "")
            )
        ]
        []
        [ input
            (keepAwakeAttributes session)
            []
            [ onCheckboxChange handlers.requestSetKeepAwake ]
        , span_ [ className "wm-keep-awake-caption" ] []
            [ text "🔋 Keep counting with screen on (recommended)" ]
        ]
    , span_ [ testId "wm-keep-awake-status", className "wm-keep-awake-status" ] []
        [ text (renderWakeLockStatus session.wakeLockState) ]
    ]

keepAwakeAttributes :: Session -> Array { name :: String, value :: String }
keepAwakeAttributes session =
  let
    base =
      [ testId "wm-keep-awake"
      , className "wm-keep-awake-checkbox"
      , attribute "type" "checkbox"
      ]
    withChecked =
      if session.keepAwake then base <> [ attribute "checked" "checked" ]
      else base
  in
    if session.listening then
      withChecked <> [ attribute "disabled" "disabled" ]
    else withChecked

buildStats :: Session -> Node
buildStats session =
  div_ [ testId "wm-stats", className "wm-metrics-grid" ] []
    [ buildStatTile "wm-stat-total" "Total" (show session.totalWords) (Just "words all time")
    , buildStatTile "wm-stat-per-day" "Per day" (formatRate (wordsPerDay session)) (Just "words / day")
    , buildStatTile "wm-stat-sample" "Sample" (formatPercent (sampleFraction session)) (Just "of wall time")
    , buildStatTile "wm-rate-short" "Last 1 min" (formatRate (shortRate session)) (Just "words / minute")
    , buildStatTile "wm-rate-long" "Last 10 min" (formatRate (longRate session)) (Just "words / minute")
    , buildStatTile "wm-rate-overall" "Overall" (formatRate (overallRate session)) (Just "words / minute")
    , buildStatTile "wm-duration" "Duration" (formatDurationMs (activeListeningMs session)) (Just "listening time")
    , buildStartedTile session
    , buildStatTile "wm-top-word" "Top word"
        (renderTopWordValue (mostFrequentWord session.currentIntervalWordStats))
        (renderTopWordSublabel (mostFrequentWord session.currentIntervalWordStats))
    , buildStatTile "wm-longest-word" "Longest word"
        (renderLongestWordValue (longestWord session.currentIntervalWordStats))
        (renderLongestWordSublabel (longestWord session.currentIntervalWordStats))
    ]

renderTopWordValue :: Maybe { word :: String, count :: Int } -> String
renderTopWordValue Nothing = "—"
renderTopWordValue (Just top) = top.word

renderTopWordSublabel :: Maybe { word :: String, count :: Int } -> Maybe String
renderTopWordSublabel Nothing = Just "this period"
renderTopWordSublabel (Just top) =
  Just (show top.count <> "× this period")

renderLongestWordValue :: Maybe String -> String
renderLongestWordValue Nothing = "—"
renderLongestWordValue (Just word) = word

renderLongestWordSublabel :: Maybe String -> Maybe String
renderLongestWordSublabel Nothing = Just "this period"
renderLongestWordSublabel (Just word) =
  Just (show (String.length word) <> " letters")

buildStatTile :: String -> String -> String -> Maybe String -> Node
buildStatTile valueTestId label valueText maybeSublabel =
  div_ [ className "wm-metric-tile" ] []
    ([ statTileLabel label
     , statTileValue valueTestId valueText
     ] <> case maybeSublabel of
        Just sublabel -> [ statTileSublabel sublabel ]
        Nothing -> [])

-- The Started tile uses a smaller, lighter value than the other tiles;
-- give it the "started" variant class so the look matches the JS build.
buildStartedTile :: Session -> Node
buildStartedTile session =
  div_ [ className "wm-metric-tile" ] []
    [ statTileLabel "Started"
    , div_
        [ testId "wm-started"
        , className "wm-metric-tile-value wm-metric-tile-value-started"
        ]
        []
        [ text (startedLabel session) ]
    ]

statTileLabel :: String -> Node
statTileLabel label =
  div_ [ className "wm-metric-tile-label" ] []
    [ text label ]

statTileValue :: String -> String -> Node
statTileValue valueTestId valueText =
  div_ [ testId valueTestId, className "wm-metric-tile-value" ] []
    [ text valueText ]

statTileSublabel :: String -> Node
statTileSublabel sublabel =
  div_ [ className "wm-metric-tile-sublabel" ] []
    [ text sublabel ]

startedLabel :: Session -> String
startedLabel session = case session.firstStartedAt of
  Nothing -> "—"
  Just timestamp -> formatClockTime timestamp

-- | Number of discrete size buckets for the word cloud. Higher
-- | numbered buckets get a larger font via the corresponding
-- | `wm-word-cloud-size-N` CSS class.
wordCloudSizeBucketCount :: Int
wordCloudSizeBucketCount = 5

wordCloudSizeClass :: Int -> Int -> String
wordCloudSizeClass maxCount count =
  let
    fraction = Int.toNumber count / Int.toNumber (max 1 maxCount)
    rawBucket = Int.floor (fraction * Int.toNumber wordCloudSizeBucketCount)
    bucket =
      if rawBucket < 1 then 1
      else if rawBucket >= wordCloudSizeBucketCount then wordCloudSizeBucketCount
      else rawBucket
  in
    "wm-word-cloud-word wm-word-cloud-size-" <> show bucket

buildWordCloud :: Session -> Node
buildWordCloud session =
  let
    words = topWords session.currentIntervalWordStats
    maxCount = case Array.head words of
      Just top -> top.count
      Nothing -> 1
  in
    div_ [ testId "wm-word-cloud", className "wm-section wm-word-cloud" ] []
      (map (buildWordCloudEntry maxCount) words)

buildWordCloudEntry :: Int -> WordFrequency -> Node
buildWordCloudEntry maxCount entry =
  span_ [ testId "wm-word-cloud-word", className (wordCloudSizeClass maxCount entry.count) ] []
    [ text entry.word
    , span_ [ className "wm-word-cloud-count" ] [] [ text (" x" <> show entry.count) ]
    ]

buildCaptions :: Session -> Node
buildCaptions session =
  div_ [ testId "wm-captions", className "wm-section wm-captions-panel" ] []
    (if Array.length session.captions == 0
      then [ buildCaptionsPlaceholder ]
      else map (buildCaption session.now) session.captions)

buildCaptionsPlaceholder :: Node
buildCaptionsPlaceholder =
  div_ [ testId "wm-captions-placeholder", className "wm-captions-placeholder" ] []
    [ text "Waiting for speech…" ]

buildCaption :: Instant -> Caption -> Node
buildCaption nowInstant caption =
  div_ [ testId "wm-caption", className (captionFadeClass nowInstant caption.timestamp) ] []
    [ text caption.transcript ]

buildEventLog :: Session -> Node
buildEventLog session =
  div_ [ testId "wm-event-log", className "wm-section wm-timeline" ] []
    (if Array.length session.eventLog == 0
      then [ buildEventLogPlaceholder ]
      else map buildEventLogEntry session.eventLog)

buildEventLogPlaceholder :: Node
buildEventLogPlaceholder =
  div_ [ testId "wm-event-log-placeholder", className "wm-timeline-empty" ] []
    [ text "(no counting sessions yet — press Start counting to begin)" ]

buildEventLogEntry :: LoggedInterval -> Node
buildEventLogEntry interval =
  div_ [ testId "wm-event-log-entry", className "wm-timeline-row" ] []
    [ eventLogEntryStarted interval.startedAt
    , eventLogEntryDuration (intervalDurationMs interval)
    , eventLogEntryWords interval.wordCount
    , eventLogEntryRate (intervalRate interval)
    , eventLogEntryTopWord interval.mostFrequentWord
    , eventLogEntryLongestWord interval.longestWord
    ]

eventLogEntryTopWord :: Maybe { word :: String, count :: Int } -> Node
eventLogEntryTopWord maybeTop =
  span_
    [ testId "wm-event-log-entry-top-word"
    , className "wm-timeline-row-top-word"
    ]
    []
    [ text (renderEventTopWord maybeTop) ]

renderEventTopWord :: Maybe { word :: String, count :: Int } -> String
renderEventTopWord Nothing = "— top"
renderEventTopWord (Just top) =
  "“" <> top.word <> "” ×" <> show top.count

eventLogEntryLongestWord :: Maybe String -> Node
eventLogEntryLongestWord maybeWord =
  span_
    [ testId "wm-event-log-entry-longest-word"
    , className "wm-timeline-row-longest-word"
    ]
    []
    [ text (renderEventLongestWord maybeWord) ]

renderEventLongestWord :: Maybe String -> String
renderEventLongestWord Nothing = "— longest"
renderEventLongestWord (Just word) =
  "“" <> word <> "” (" <> show (String.length word) <> ")"

eventLogEntryStarted :: Instant -> Node
eventLogEntryStarted startedAt =
  span_ [ testId "wm-event-log-entry-started", className "wm-timeline-row-time" ] []
    [ text (formatClockTime startedAt) ]

eventLogEntryDuration :: Number -> Node
eventLogEntryDuration durationMs =
  span_ [ testId "wm-event-log-entry-duration", className "wm-timeline-row-duration-centered" ] []
    [ text (formatDurationMs durationMs) ]

eventLogEntryWords :: Int -> Node
eventLogEntryWords wordCount =
  span_ [ testId "wm-event-log-entry-words", className "wm-timeline-row-words" ] []
    [ text (show wordCount <> " w") ]

eventLogEntryRate :: Number -> Node
eventLogEntryRate rate =
  span_ [ testId "wm-event-log-entry-rate", className "wm-timeline-row-rate" ] []
    [ text (formatRate rate <> " wpm") ]

buildVersion :: Node
buildVersion =
  span_ [ testId "wm-version", className "wm-version" ] []
    [ text ("Word Meter (PureScript) v" <> version) ]

buildErrorBanner :: Session -> Node
buildErrorBanner session =
  div_
    [ testId "wm-error"
    , className "wm-error"
    , attribute "role" "alert"
    ]
    []
    [ text session.errorBanner ]

buildDiagnostics :: Handlers -> Session -> Node
buildDiagnostics handlers session =
  details_ drawerAttributes []
    [ summary_ [ testId "wm-diagnostics-toggle", className "wm-diagnostics-summary" ] []
        [ onClick handlers.requestToggleDiagnosticsDrawer ]
        [ text "🔧 Diagnostics" ]
    , div_ [ className "wm-diagnostics-actions" ] []
        [ button
            [ testId "wm-diagnostics-copy"
            , buttonType "button"
            , className "wm-diagnostics-copy-button"
            ]
            []
            [ onClick handlers.requestCopyDiagnostics ]
            [ text "📋 Copy diagnostics" ]
        , span_ [ testId "wm-diagnostics-copy-status", className "wm-diagnostics-copy-status" ] []
            [ text session.copyStatus ]
        ]
    , pre_
        [ testId "wm-diagnostics-content", className "wm-diagnostics-content" ]
        []
        [ text (diagnosticsText session) ]
    ]
  where
  drawerAttributes =
    [ testId "wm-diagnostics", className "wm-diagnostics-drawer" ]
      <> if session.diagnosticsDrawerOpen then [ attribute "open" "" ] else []
