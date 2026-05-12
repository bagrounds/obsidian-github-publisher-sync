module WordMeter.Recording
  ( Session
  , Caption
  , Action(..)
  , Send
  , initialSession
  , reduce
  , view
  , captionHistoryLimit
  ) where

import Prelude

import Data.Array (length, takeEnd)
import Data.Maybe (Maybe(..))
import Effect (Effect)
import WordMeter.Vdom (Node, button, buttonType, div_, onClick, span_, style, testId, text)
import WordMeter.Version (version)
import WordMeter.Words (countWords)

type Session =
  { listening :: Boolean
  , totalWords :: Int
  , captions :: Array Caption
  , lastError :: Maybe String
  }

type Caption =
  { transcript :: String
  , wordCount :: Int
  }

captionHistoryLimit :: Int
captionHistoryLimit = 6

data Action
  = Toggle
  | InjectFinalTranscript String

type Send = Action -> Effect Unit

initialSession :: Session
initialSession =
  { listening: false
  , totalWords: 0
  , captions: []
  , lastError: Nothing
  }

reduce :: Action -> Session -> Session
reduce Toggle session = session { listening = not session.listening }
reduce (InjectFinalTranscript transcript) session
  | session.listening =
      let
        wordCount = countWords transcript
      in
        if wordCount == 0 then session
        else session
          { totalWords = session.totalWords + wordCount
          , captions = takeEnd captionHistoryLimit
              (session.captions <> [ { transcript, wordCount } ])
          }
  | otherwise = session

view :: Send -> Session -> Node
view send session =
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
    , buildToggle send session
    , buildCaptions session
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

buildToggle :: Send -> Session -> Node
buildToggle send session =
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
    [ onClick (send Toggle) ]
    [ text (if session.listening then "Stop counting" else "Start counting") ]

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
    (if length session.captions == 0
      then [ buildCaptionsPlaceholder ]
      else map buildCaption session.captions)

buildCaptionsPlaceholder :: Node
buildCaptionsPlaceholder =
  div_ [ testId "wm-captions-placeholder" ]
    [ style "font-size" "12px"
    , style "color" "#7d8590"
    , style "font-style" "italic"
    ]
    [ text "(nothing yet)" ]

buildCaption :: Caption -> Node
buildCaption caption =
  div_ [ testId "wm-caption" ]
    [ style "font-size" "13px"
    , style "color" "#c9d1d9"
    , style "line-height" "1.3"
    ]
    [ text caption.transcript ]

buildVersion :: Node
buildVersion =
  span_ [ testId "wm-version" ]
    [ style "display" "block"
    , style "margin-top" "12px"
    , style "font-size" "11px"
    , style "color" "#7d8590"
    ]
    [ text ("Word Meter (PureScript) v" <> version) ]
