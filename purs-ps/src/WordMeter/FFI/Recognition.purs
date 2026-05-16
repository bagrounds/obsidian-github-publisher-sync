module WordMeter.FFI.Recognition
  ( RecognitionInstance
  , RecognitionConstructError(..)
  , RecognitionStartError(..)
  , RecognitionStopError(..)
  , OnDeviceAvailable(..)
  , OnDeviceUnavailable(..)
  , renderRecognitionConstructError
  , renderRecognitionStartError
  , renderRecognitionStopError
  , renderOnDeviceUnavailable
  , recognitionApiAvailable
  , constructRecognitionInstance
  , onDeviceLanguagePackApiAvailable
  , ensureOnDeviceLanguagePack
  , attachOnResult
  , attachOnError
  , attachOnEnd
  , detachHandlers
  , startRecognitionInstance
  , stopRecognitionInstance
  ) where

import Prelude

import Data.Either (Either(..))
import Effect (Effect)

-- | Opaque PureScript handle for a browser `SpeechRecognition`
-- | instance. The JS side never inspects this value: it is produced by
-- | `constructRecognitionInstance` and consumed by the attach /
-- | detach / start / stop functions. Lifetime management — including
-- | the question of whether the program currently owns a recognition
-- | instance — lives entirely in `WordMeter.Capability.Recognition`.
foreign import data RecognitionInstance :: Type

-- | Why constructing a `SpeechRecognition` instance failed. The
-- | detail string carries the underlying browser error name
-- | (`NotSupportedError`, `SecurityError`, etc.) — or
-- | `"no SpeechRecognition constructor"` when the API itself is
-- | absent.
newtype RecognitionConstructError = RecognitionConstructError String

derive instance eqRecognitionConstructError :: Eq RecognitionConstructError

instance showRecognitionConstructError :: Show RecognitionConstructError where
  show (RecognitionConstructError detail) =
    "RecognitionConstructError " <> show detail

renderRecognitionConstructError :: RecognitionConstructError -> String
renderRecognitionConstructError (RecognitionConstructError detail) = detail

-- | Why `recognition.start()` threw synchronously. Asynchronous error
-- | events come through `attachOnError`, not this type.
newtype RecognitionStartError = RecognitionStartError String

derive instance eqRecognitionStartError :: Eq RecognitionStartError

instance showRecognitionStartError :: Show RecognitionStartError where
  show (RecognitionStartError detail) =
    "RecognitionStartError " <> show detail

renderRecognitionStartError :: RecognitionStartError -> String
renderRecognitionStartError (RecognitionStartError detail) = detail

-- | Why `recognition.stop()` threw synchronously. The browser
-- | sometimes throws `InvalidStateError` when called on an instance
-- | that is not currently started; the capability layer surfaces that
-- | here rather than silently swallowing it.
newtype RecognitionStopError = RecognitionStopError String

derive instance eqRecognitionStopError :: Eq RecognitionStopError

instance showRecognitionStopError :: Show RecognitionStopError where
  show (RecognitionStopError detail) =
    "RecognitionStopError " <> show detail

renderRecognitionStopError :: RecognitionStopError -> String
renderRecognitionStopError (RecognitionStopError detail) = detail

-- | True iff `window.SpeechRecognition` or
-- | `window.webkitSpeechRecognition` is a callable constructor. The
-- | capability layer queries this before every
-- | `constructRecognitionInstance` so the "unsupported" case is
-- | detected in PureScript rather than via a sentinel string from
-- | JavaScript.
foreign import recognitionApiAvailable :: Effect Boolean

-- | Thin wrapper over `new SpeechRecognition()` with the legacy
-- | configuration knobs (`continuous = true`, `interimResults = true`,
-- | `lang = locale`). The `processLocally` flag is the standardized
-- | Chromium hint for on-device recognition: set `true` after a
-- | successful `ensureOnDeviceLanguagePack`, set `false` for the
-- | cloud path. The constructor invokes exactly one of the two
-- | continuations: the instance callback on success, the error
-- | callback (carrying the browser's error name) on synchronous
-- | failure.
foreign import constructRecognitionInstance
  :: String
  -> Boolean
  -> (RecognitionInstance -> Effect Unit)
  -> (String -> Effect Unit)
  -> Effect Unit

-- | True iff the constructor exposes the standardized static
-- | `available()` and `install()` methods used to pre-flight an
-- | on-device language pack. Older Chromium builds, Samsung Internet,
-- | Safari, and Firefox all answer `false`; the capability layer takes
-- | this as the unambiguous signal to skip the pre-flight and go
-- | straight to the cloud path.
foreign import onDeviceLanguagePackApiAvailable :: Effect Boolean

-- | Witness that the on-device language pack for a given locale is
-- | currently installed and the recognizer is safe to start with
-- | `processLocally = true`. The constructor is uninhabited from
-- | PureScript code: only the FFI shim is allowed to mint one, after
-- | the static `available()` / `install()` round trip resolves
-- | successfully.
data OnDeviceAvailable = OnDeviceAvailable

derive instance eqOnDeviceAvailable :: Eq OnDeviceAvailable

instance showOnDeviceAvailable :: Show OnDeviceAvailable where
  show OnDeviceAvailable = "OnDeviceAvailable"

-- | Why the on-device pre-flight refused to certify the language
-- | pack. Each variant maps to a single failure mode the JS shim can
-- | observe so the capability layer can decide whether to fall back
-- | silently (every case here) and how to render the diagnostic.
data OnDeviceUnavailable
  = OnDeviceApiAbsent
  | OnDeviceUnsupportedLanguage
  | OnDeviceInstallFailed String
  | OnDeviceAvailabilityRejected String

derive instance eqOnDeviceUnavailable :: Eq OnDeviceUnavailable

instance showOnDeviceUnavailable :: Show OnDeviceUnavailable where
  show OnDeviceApiAbsent = "OnDeviceApiAbsent"
  show OnDeviceUnsupportedLanguage = "OnDeviceUnsupportedLanguage"
  show (OnDeviceInstallFailed detail) =
    "OnDeviceInstallFailed " <> show detail
  show (OnDeviceAvailabilityRejected detail) =
    "OnDeviceAvailabilityRejected " <> show detail

renderOnDeviceUnavailable :: OnDeviceUnavailable -> String
renderOnDeviceUnavailable OnDeviceApiAbsent = "api-absent"
renderOnDeviceUnavailable OnDeviceUnsupportedLanguage = "unsupported-language"
renderOnDeviceUnavailable (OnDeviceInstallFailed detail) =
  "install-failed: " <> detail
renderOnDeviceUnavailable (OnDeviceAvailabilityRejected detail) =
  "availability-rejected: " <> detail

-- | Pre-flight the on-device language pack for the given locale.
-- | Invokes exactly one terminal continuation: `onDone` with `Right
-- | OnDeviceAvailable` once the recognizer is safe to start with
-- | `processLocally = true`, or `Left OnDeviceUnavailable` carrying
-- | the classified failure. The `onProgress` continuation fires zero
-- | or one times before the terminal one, exactly when `install()`
-- | needs to run; UI code uses it to flip the status row to
-- | "downloading on-device language pack…".
ensureOnDeviceLanguagePack
  :: String
  -> Effect Unit
  -> (Either OnDeviceUnavailable OnDeviceAvailable -> Effect Unit)
  -> Effect Unit
ensureOnDeviceLanguagePack locale onProgress onDone =
  ensureOnDeviceLanguagePackImpl locale onProgress
    (onDone (Right OnDeviceAvailable))
    ( \kind detail -> onDone (Left (classifyOnDeviceUnavailable kind detail))
    )

foreign import ensureOnDeviceLanguagePackImpl
  :: String
  -> Effect Unit
  -> Effect Unit
  -> (String -> String -> Effect Unit)
  -> Effect Unit

classifyOnDeviceUnavailable :: String -> String -> OnDeviceUnavailable
classifyOnDeviceUnavailable kind detail = case kind of
  "api-absent" -> OnDeviceApiAbsent
  "unsupported-language" -> OnDeviceUnsupportedLanguage
  "install-failed" -> OnDeviceInstallFailed detail
  "availability-rejected" -> OnDeviceAvailabilityRejected detail
  other -> OnDeviceAvailabilityRejected (other <> ": " <> detail)

-- | Subscribe to `recognition.onresult`. The JS shim iterates
-- | `event.results` from `event.resultIndex`, filters out non-final
-- | results, trims each transcript, and invokes the supplied callback
-- | once per non-empty finalized transcript with a wall-clock
-- | timestamp (`Date.now()`).
foreign import attachOnResult
  :: RecognitionInstance
  -> (String -> Number -> Effect Unit)
  -> Effect Unit

-- | Subscribe to `recognition.onerror`. The JS shim normalizes the
-- | event into `(code, message)` with `""` for either missing field
-- | so PureScript never has to special-case `undefined`.
foreign import attachOnError
  :: RecognitionInstance
  -> (String -> String -> Effect Unit)
  -> Effect Unit

-- | Subscribe to `recognition.onend`. Fires when the recognizer
-- | naturally ends (silence timeout, browser auto-stop, etc.) or when
-- | the program calls `stopRecognitionInstance`.
foreign import attachOnEnd
  :: RecognitionInstance
  -> Effect Unit
  -> Effect Unit

-- | Clear `onresult`, `onerror`, and `onend` on the instance. Used by
-- | the capability before discarding an instance so a late event from
-- | the browser cannot reach a logically-dead program path.
foreign import detachHandlers :: RecognitionInstance -> Effect Unit

-- | Thin wrapper over `recognition.start()`. Invokes exactly one of
-- | the two continuations: the success callback when `start()`
-- | returns, the error callback (carrying the browser's error name)
-- | when the synchronous call throws.
foreign import startRecognitionInstance
  :: RecognitionInstance
  -> Effect Unit
  -> (String -> Effect Unit)
  -> Effect Unit

-- | Thin wrapper over `recognition.stop()`. Invokes exactly one of
-- | the two continuations: the success callback when `stop()`
-- | returns, the error callback (carrying the browser's error name)
-- | when the synchronous call throws (e.g. `InvalidStateError` on a
-- | not-yet-started instance).
foreign import stopRecognitionInstance
  :: RecognitionInstance
  -> Effect Unit
  -> (String -> Effect Unit)
  -> Effect Unit
