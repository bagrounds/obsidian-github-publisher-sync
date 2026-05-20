module WordMeter.FFI.DocumentPip
  ( PipWindow
  , DocumentPipError(..)
  , PipContent
  , renderDocumentPipError
  , checkDocumentPipAvailability
  , requestPipWindow
  , attachPipCloseListener
  , closePipWindow
  , writePipContent
  ) where

import Prelude

import Effect (Effect)

-- | Opaque handle on a `documentPictureInPicture` window. The JS shim
-- | never inspects this; the PureScript side stores it in
-- | `ApplicationEnvironment.pipWindowRef` and hands it back to the
-- | other FFI calls for content updates and close.
foreign import data PipWindow :: Type

-- | Why a Document Picture-in-Picture operation failed.
-- |
-- | * `DocumentPipUnsupported` — the browser does not expose a usable
-- |   `documentPictureInPicture` object. Carries a platform-aware
-- |   diagnostic detail (e.g. "Document PiP is desktop-only on
-- |   Chromium; this device reports Chrome on Android") so the user
-- |   can tell *why* the API is missing rather than just *that* it is.
-- | * `DocumentPipRequestRejected` — `requestWindow` returned a
-- |   promise that rejected (most often because the call did not
-- |   originate in a user gesture, or the user dismissed a permission
-- |   prompt). Carries the browser's error name for diagnostics.
data DocumentPipError
  = DocumentPipUnsupported String
  | DocumentPipRequestRejected String

derive instance eqDocumentPipError :: Eq DocumentPipError

instance showDocumentPipError :: Show DocumentPipError where
  show (DocumentPipUnsupported detail) =
    "DocumentPipUnsupported " <> show detail
  show (DocumentPipRequestRejected detail) =
    "DocumentPipRequestRejected " <> show detail

renderDocumentPipError :: DocumentPipError -> String
renderDocumentPipError = case _ of
  DocumentPipUnsupported detail ->
    "picture-in-picture not supported on this browser — " <> detail
  DocumentPipRequestRejected detail ->
    "pop-out unavailable: " <> detail

-- | The snapshot the PiP document renders. Kept minimal for Slice 1 —
-- | just the big number and the listening / idle status. Extending the
-- | record (rate, duration, …) is the contract for future slices.
type PipContent =
  { wordsToday :: Int
  , status :: String
  }

-- | Probe the browser for Document Picture-in-Picture support. Returns
-- | the empty string when the API is callable; otherwise returns a
-- | human-readable, platform-aware diagnostic string describing
-- | exactly which check failed (no `window`, missing
-- | `documentPictureInPicture` object, missing `requestWindow` method,
-- | or a mobile/unsupported platform with the user-agent appended).
-- | The capability layer wraps the non-empty case into
-- | `DocumentPipUnsupported detail`.
foreign import checkDocumentPipAvailability :: Effect String

-- | Thin wrapper over `documentPictureInPicture.requestWindow`.
-- | Invokes exactly one of the two continuations: the window callback
-- | on success, the error callback (carrying the browser's error name)
-- | on rejection. Must only be called from a user gesture and only
-- | when `documentPipApiAvailable` returned true.
foreign import requestPipWindow
  :: (PipWindow -> Effect Unit)
  -> (String -> Effect Unit)
  -> Effect Unit

-- | Subscribe to the PiP window's `pagehide` event, which fires both
-- | when the user closes the floating window from the OS chrome and
-- | when the program calls `closePipWindow`. The capability layer
-- | uses this to keep `session.pipOpen` in sync.
foreign import attachPipCloseListener
  :: PipWindow -> Effect Unit -> Effect Unit

-- | Thin wrapper over `pipWindow.close()`. Synchronous and total: the
-- | underlying call cannot reject, so there is no error continuation.
foreign import closePipWindow :: PipWindow -> Effect Unit

-- | Render the PiP body for the supplied snapshot. The shim owns the
-- | inner DOM layout of the floating window; the PureScript side only
-- | passes the data values.
foreign import writePipContent :: PipWindow -> PipContent -> Effect Unit
