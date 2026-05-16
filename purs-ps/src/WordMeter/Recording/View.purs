module WordMeter.Recording.View
  ( view
  , diagnosticsText
  ) where

import Prelude

import Data.DateTime.Instant (Instant)
import Data.Array (length) as Array
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
  , details_
  , div_
  , input
  , label_
  , onCheckboxChange
  , onClick
  , pre_
  , span_
  , style
  , summary_
  , testId
  , text
  )

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
    [ text (renderStatus session) ]

renderStatus :: Session -> String
renderStatus session
  | session.recognitionStatusOverride /= "" = session.recognitionStatusOverride
  | session.listening = "Listening"
  | otherwise = "Idle"

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

buildReset :: Handlers -> Node
buildReset handlers =
  button
    [ testId "wm-reset", buttonType "button" ]
    [ style "margin-top" "8px"
    , style "margin-left" "8px"
    , style "padding" "8px 14px"
    , style "border-radius" "999px"
    , style "border" "1px solid rgba(255,255,255,0.18)"
    , style "background" "transparent"
    , style "color" "#e6edf3"
    , style "cursor" "pointer"
    , style "font" "inherit"
    , style "font-size" "13px"
    ]
    [ onClick handlers.requestReset ]
    [ text "Reset" ]

buildKeepAwake :: Handlers -> Session -> Node
buildKeepAwake handlers session =
  div_ []
    [ style "display" "flex"
    , style "flex-wrap" "wrap"
    , style "align-items" "center"
    , style "justify-content" "center"
    , style "gap" "8px"
    , style "margin-top" "10px"
    , style "font-size" "13px"
    , style "color" "#9aa5b1"
    ]
    [ label_
        [ testId "wm-keep-awake-label" ]
        [ style "display" "inline-flex"
        , style "align-items" "center"
        , style "cursor" (if session.listening then "default" else "pointer")
        , style "opacity" (if session.listening then "0.7" else "1.0")
        ]
        [ input
            (keepAwakeAttributes session)
            [ style "margin-right" "8px" ]
            [ onCheckboxChange handlers.requestSetKeepAwake ]
        , span_ []
            [ style "user-select" "none" ]
            [ text "🔋 Keep counting with screen on (recommended)" ]
        ]
    , span_ [ testId "wm-keep-awake-status" ]
        [ style "font-size" "12px"
        , style "color" "#7d8590"
        ]
        [ text (renderWakeLockStatus session.wakeLockState) ]
    ]

keepAwakeAttributes :: Session -> Array { name :: String, value :: String }
keepAwakeAttributes session =
  let
    base =
      [ testId "wm-keep-awake"
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

buildCaption :: Instant -> Caption -> Node
buildCaption nowInstant caption =
  div_ [ testId "wm-caption" ]
    [ style "font-size" "13px"
    , style "color" "#c9d1d9"
    , style "line-height" "1.3"
    , style "opacity" (show (captionOpacity nowInstant caption.timestamp))
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

eventLogEntryStarted :: Instant -> Node
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

buildErrorBanner :: Session -> Node
buildErrorBanner session =
  div_
    [ testId "wm-error"
    , attribute "role" "alert"
    ]
    [ style "margin-top" "12px"
    , style "font-size" "13px"
    , style "color" "#ff8b94"
    , style "text-align" "center"
    , style "min-height" "18px"
    ]
    [ text session.errorBanner ]

buildDiagnostics :: Handlers -> Session -> Node
buildDiagnostics handlers session =
  details_ drawerAttributes
    [ style "margin-top" "16px"
    , style "padding-top" "10px"
    , style "border-top" "1px solid rgba(255,255,255,0.08)"
    , style "font-size" "12px"
    , style "color" "#9aa5b1"
    ]
    [ summary_ [ testId "wm-diagnostics-toggle" ]
        [ style "cursor" "pointer"
        , style "user-select" "none"
        , style "padding" "4px 0"
        ]
        [ onClick handlers.requestToggleDiagnosticsDrawer ]
        [ text "🔧 Diagnostics" ]
    , div_ []
        [ style "display" "flex"
        , style "align-items" "center"
        , style "gap" "8px"
        , style "margin" "8px 0 0 0"
        ]
        [ button
            [ testId "wm-diagnostics-copy", buttonType "button" ]
            [ style "padding" "8px 12px"
            , style "border-radius" "999px"
            , style "border" "1px solid rgba(255,255,255,0.18)"
            , style "background" "transparent"
            , style "color" "#e6edf3"
            , style "cursor" "pointer"
            , style "font" "inherit"
            ]
            [ onClick handlers.requestCopyDiagnostics ]
            [ text "📋 Copy diagnostics" ]
        , span_ [ testId "wm-diagnostics-copy-status" ]
            [ style "color" "#9aa5b1"
            , style "font-size" "11.5px"
            ]
            [ text session.copyStatus ]
        ]
    , pre_
        [ testId "wm-diagnostics-content" ]
        [ style "margin" "8px 0 0 0"
        , style "padding" "10px 12px"
        , style "background" "rgba(255,255,255,0.04)"
        , style "border" "1px solid rgba(255,255,255,0.08)"
        , style "border-radius" "8px"
        , style "font-family" "ui-monospace,SFMono-Regular,Menlo,monospace"
        , style "font-size" "11.5px"
        , style "line-height" "1.45"
        , style "color" "#c9d1d9"
        , style "white-space" "pre-wrap"
        , style "word-break" "break-word"
        , style "max-height" "320px"
        , style "overflow-y" "auto"
        ]
        [ text (diagnosticsText session) ]
    ]
  where
  drawerAttributes =
    [ testId "wm-diagnostics" ]
      <> if session.diagnosticsDrawerOpen then [ attribute "open" "" ] else []
