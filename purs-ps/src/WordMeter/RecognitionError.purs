-- | Pure logic for the slice-8 recognition error banner: classifying
-- | the error code reported by the Web Speech API, deciding whether
-- | the program should stop listening / show a banner, and rendering
-- | the user-facing banner text.
-- |
-- | This module is intentionally pure — no `Effect`, no FFI — so the
-- | reducer + unit tests can exercise every branch without touching
-- | the browser. Slice 9 will wire the real `recognition.onerror`
-- | callback into `Main` and dispatch through `HandleRecognitionError`.
module WordMeter.RecognitionError
  ( RecognitionErrorCode(..)
  , classifyRecognitionError
  , isTransient
  , isPermissionDenied
  , recognitionErrorBannerText
  , renderRecognitionErrorDiagnosticDetail
  , permissionDeniedBanner
  , networkErrorBanner
  , languageUnavailableBanner
  , noRecognitionErrorBanner
  , genericRecognitionErrorBanner
  ) where

import Prelude

-- | The closed set of error codes the Web Speech API can emit on
-- | `recognition.onerror`. Anything we do not recognize collapses to
-- | `OtherRecognitionError` carrying the raw code so the diagnostics
-- | drawer can still surface it verbatim. The legacy build folds
-- | `(none)` into the same bucket; we keep an explicit
-- | `NoRecognitionErrorCode` constructor so the reducer can render a
-- | distinct banner.
data RecognitionErrorCode
  = NotAllowed
  | ServiceNotAllowed
  | NoSpeech
  | Aborted
  | AudioCapture
  | Network
  | LanguageNotSupported
  | NoRecognitionErrorCode
  | OtherRecognitionError String

derive instance eqRecognitionErrorCode :: Eq RecognitionErrorCode

instance showRecognitionErrorCode :: Show RecognitionErrorCode where
  show = case _ of
    NotAllowed -> "NotAllowed"
    ServiceNotAllowed -> "ServiceNotAllowed"
    NoSpeech -> "NoSpeech"
    Aborted -> "Aborted"
    AudioCapture -> "AudioCapture"
    Network -> "Network"
    LanguageNotSupported -> "LanguageNotSupported"
    NoRecognitionErrorCode -> "NoRecognitionErrorCode"
    OtherRecognitionError raw -> "OtherRecognitionError " <> show raw

-- | Map a raw browser error code to the typed ADT. An empty string is
-- | how Chromium occasionally reports an error with no code at all; we
-- | normalize that into `NoRecognitionErrorCode` rather than letting
-- | callers special-case empty strings.
classifyRecognitionError :: String -> RecognitionErrorCode
classifyRecognitionError = case _ of
  "not-allowed" -> NotAllowed
  "service-not-allowed" -> ServiceNotAllowed
  "no-speech" -> NoSpeech
  "aborted" -> Aborted
  "audio-capture" -> AudioCapture
  "network" -> Network
  "language-not-supported" -> LanguageNotSupported
  "" -> NoRecognitionErrorCode
  raw -> OtherRecognitionError raw

-- | Codes that legacy treats as silent (no banner, keep listening):
-- | brief gaps in speech, an in-flight `recognition.stop()`, or a
-- | momentary audio-capture hiccup.
isTransient :: RecognitionErrorCode -> Boolean
isTransient NoSpeech = true
isTransient Aborted = true
isTransient AudioCapture = true
isTransient _ = false

-- | Codes that indicate the user (or the browser policy) refused
-- | microphone access. These must stop the active counting session so
-- | the UI does not look like it is still listening.
isPermissionDenied :: RecognitionErrorCode -> Boolean
isPermissionDenied NotAllowed = true
isPermissionDenied ServiceNotAllowed = true
isPermissionDenied _ = false

permissionDeniedBanner :: String
permissionDeniedBanner =
  "Microphone permission denied. Allow microphone access and try again."

networkErrorBanner :: String
networkErrorBanner =
  "Network error reaching the speech service. Check your connection and try again."

languageUnavailableBanner :: String
languageUnavailableBanner =
  "Speech recognition is not available for your language in this browser."

noRecognitionErrorBanner :: String
noRecognitionErrorBanner = "Recognition error: unknown"

genericRecognitionErrorBanner :: String -> String
genericRecognitionErrorBanner code = "Recognition error: " <> code

-- | The banner text the user should see, or `""` when the error is
-- | transient and the banner must not change.
recognitionErrorBannerText :: RecognitionErrorCode -> String
recognitionErrorBannerText = case _ of
  NoSpeech -> ""
  Aborted -> ""
  AudioCapture -> ""
  NotAllowed -> permissionDeniedBanner
  ServiceNotAllowed -> permissionDeniedBanner
  Network -> networkErrorBanner
  LanguageNotSupported -> languageUnavailableBanner
  NoRecognitionErrorCode -> noRecognitionErrorBanner
  OtherRecognitionError raw -> genericRecognitionErrorBanner raw

-- | The detail string we append to the `recognition.onerror`
-- | diagnostic entry, mirroring the legacy `code=… message=…` shape so
-- | bug reports across both builds are byte-comparable.
renderRecognitionErrorDiagnosticDetail :: String -> String -> String
renderRecognitionErrorDiagnosticDetail code message =
  "code=" <> renderCode code <> " message=" <> message
  where
  renderCode :: String -> String
  renderCode "" = "(none)"
  renderCode raw = raw
