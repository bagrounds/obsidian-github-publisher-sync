module WordMeter.Capability.Clipboard
  ( class Clipboard
  , writeClipboardText
  , RecordingClipboardM(..)
  , ClipboardRecording
  , runRecordingClipboardM
  ) where

import Prelude

import Control.Monad.Reader.Trans (runReaderT)
import Control.Monad.State.Trans (StateT, modify_, runStateT)
import Data.Identity (Identity(..))
import Data.Tuple (Tuple(..))
import Effect.Class (liftEffect)
import Control.Monad.Reader.Class (ask)
import WordMeter.AppM (AppM(..))
import WordMeter.FFI.Clipboard as FFI

-- | A clipboard capability whose `writeClipboardText` takes explicit
-- | success and error continuations because the underlying browser API
-- | is asynchronous. The continuations execute in the same monad as
-- | the call site, so callers compose them without leaving the
-- | capability stack.
class Monad m <= Clipboard m where
  writeClipboardText :: String -> m Unit -> (String -> m Unit) -> m Unit

instance clipboardAppM :: Clipboard AppM where
  writeClipboardText payload (AppM onSuccess) onError = AppM do
    applicationEnvironment <- ask
    liftEffect
      ( FFI.writeText payload
          (runReaderT onSuccess applicationEnvironment)
          ( \reason ->
              case onError reason of
                AppM continuation -> runReaderT continuation applicationEnvironment
          )
      )

-- | Test newtype that records every clipboard payload into an in-memory
-- | log. The success branch fires synchronously; the error branch is
-- | never taken — production code is responsible for triggering its
-- | own error paths in tests that need them.
type ClipboardRecording = Array String

newtype RecordingClipboardM a =
  RecordingClipboardM (StateT ClipboardRecording Identity a)

derive newtype instance functorRecordingClipboardM :: Functor RecordingClipboardM
derive newtype instance applyRecordingClipboardM :: Apply RecordingClipboardM
derive newtype instance applicativeRecordingClipboardM :: Applicative RecordingClipboardM
derive newtype instance bindRecordingClipboardM :: Bind RecordingClipboardM
derive newtype instance monadRecordingClipboardM :: Monad RecordingClipboardM

instance clipboardRecordingClipboardM :: Clipboard RecordingClipboardM where
  writeClipboardText payload onSuccess _onError = do
    RecordingClipboardM (modify_ (\writes -> writes <> [ payload ]))
    onSuccess

runRecordingClipboardM
  :: forall a
   . RecordingClipboardM a
  -> { result :: a, writes :: ClipboardRecording }
runRecordingClipboardM (RecordingClipboardM stateful) =
  case runStateT stateful [] of
    Identity (Tuple result writes) -> { result, writes }
