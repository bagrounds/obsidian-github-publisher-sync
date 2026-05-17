module WordMeter.Recording.View
  ( view
  , diagnosticsText
  ) where

import Prelude

import Data.DateTime.Instant (Instant)
import Data.Array (length) as Array
import Data.Int as Int
import Data.Maybe (Maybe(..))
import WordMeter.Clock (formatClockTime)
import WordMeter.Diagnostics (formatDiagnostics)
import WordMeter.Recording.Math
  ( activeListeningMs
  , captionOpacity
  , formatDurationMs
  , formatRate
  , intervalDurationMs
  , intervalRate
  , longRate
  , overallRate
  , shortRate
  )
import WordMeter.Recording.Reducer (Handlers)
import WordMeter.Recording.Session
  ( Caption
  , LoggedInterval
  , Session
  , renderWakeLockStatus
  )
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
    [ text (show session.totalWords) ]

buildCountLabel :: Node
buildCountLabel =
  div_ [ testId "wm-count-label", className "wm-count-label" ] []
    [ text "words counted" ]

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
    [ buildStatTile "wm-rate-short" "Last 1 min" (formatRate (shortRate session)) (Just "words / minute")
    , buildStatTile "wm-rate-long" "Last 10 min" (formatRate (longRate session)) (Just "words / minute")
    , buildStatTile "wm-rate-overall" "Overall" (formatRate (overallRate session)) (Just "words / minute")
    , buildStatTile "wm-duration" "Duration" (formatDurationMs (activeListeningMs session)) (Just "listening time")
    , buildStartedTile session
    ]

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
    ]

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
