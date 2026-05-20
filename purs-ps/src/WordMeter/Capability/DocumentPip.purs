module WordMeter.Capability.DocumentPip
  ( class DocumentPip
  , requestPipWindow
  , closePipWindow
  , syncPipContent
  , DocumentPipEvent(..)
  , RecordingDocumentPipM(..)
  , DocumentPipRecording
  , runRecordingDocumentPipM
  ) where

import Prelude

import Control.Monad.Reader.Class (ask)
import Control.Monad.State.Trans (StateT, modify_, runStateT)
import Data.Identity (Identity(..))
import Data.Maybe (Maybe(..))
import Data.Tuple (Tuple(..))
import Effect (Effect)
import Effect.Class (liftEffect)
import Effect.Ref as Ref
import WordMeter.AppM (AppM(..), ApplicationEnvironment, runAppM)
import WordMeter.FFI.DocumentPip
  ( DocumentPipError(..)
  , PipContent
  , PipWindow
  )
import WordMeter.FFI.DocumentPip as FFI

-- | Capability for the Document Picture-in-Picture pop-out. All three
-- | methods are continuation-passing so production code never blocks
-- | on the underlying browser promise, and every failure surfaces
-- | through a typed `DocumentPipError` continuation: the "never
-- | silently swallow errors" rule applies here just as it does to
-- | wake locks.
class Monad m <= DocumentPip m where
  requestPipWindow
    :: m Unit                              -- onOpened
    -> (DocumentPipError -> m Unit)        -- onError
    -> m Unit                              -- onClosedByUser
    -> m Unit
  closePipWindow
    :: m Unit                              -- onClosed
    -> m Unit
  syncPipContent :: PipContent -> m Unit

instance documentPipAppM :: DocumentPip AppM where
  requestPipWindow onOpened onError onClosedByUser =
    AppM do
      environment <- ask
      liftEffect (openPipWindow environment onOpened onError onClosedByUser)
  closePipWindow onClosed =
    AppM do
      environment <- ask
      liftEffect (closeHeldPipWindow environment onClosed)
  syncPipContent content =
    AppM do
      environment <- ask
      liftEffect (writeIfHeld environment content)

openPipWindow
  :: ApplicationEnvironment
  -> AppM Unit
  -> (DocumentPipError -> AppM Unit)
  -> AppM Unit
  -> Effect Unit
openPipWindow environment onOpened onError onClosedByUser = do
  let runHere :: forall a. AppM a -> Effect a
      runHere act = runAppM environment act
  available <- FFI.documentPipApiAvailable
  if not available then runHere (onError DocumentPipUnsupported)
  else FFI.requestPipWindow
    ( \pipWindow -> do
        Ref.write (Just pipWindow) environment.pipWindowRef
        FFI.attachPipCloseListener pipWindow
          (handlePipWindowClosed environment pipWindow onClosedByUser)
        runHere onOpened
    )
    (\reason -> runHere (onError (DocumentPipRequestRejected reason)))

handlePipWindowClosed
  :: ApplicationEnvironment
  -> PipWindow
  -> AppM Unit
  -> Effect Unit
handlePipWindowClosed environment _pipWindow onClosedByUser = do
  -- A close event from a window we no longer track means the program
  -- already cleared the ref via `closeHeldPipWindow`, so we have
  -- nothing further to do. Otherwise the user dismissed the window
  -- from the OS chrome and we surface the close to the orchestrator.
  currentlyHeld <- Ref.read environment.pipWindowRef
  case currentlyHeld of
    Just _ -> do
      Ref.write Nothing environment.pipWindowRef
      runAppM environment onClosedByUser
    Nothing -> pure unit

closeHeldPipWindow
  :: ApplicationEnvironment -> AppM Unit -> Effect Unit
closeHeldPipWindow environment onClosed = do
  let runHere :: forall a. AppM a -> Effect a
      runHere act = runAppM environment act
  held <- Ref.read environment.pipWindowRef
  case held of
    Nothing -> runHere onClosed
    Just pipWindow -> do
      Ref.write Nothing environment.pipWindowRef
      FFI.closePipWindow pipWindow
      runHere onClosed

writeIfHeld
  :: ApplicationEnvironment -> PipContent -> Effect Unit
writeIfHeld environment content = do
  held <- Ref.read environment.pipWindowRef
  case held of
    Nothing -> pure unit
    Just pipWindow -> FFI.writePipContent pipWindow content

-- | One entry recorded by `RecordingDocumentPipM`: every request and
-- | close call is logged in order so reducer-wiring tests can assert
-- | the orchestrator opened / closed / re-synced the PiP window at
-- | the right times.
data DocumentPipEvent
  = RequestedPipWindow
  | ClosedPipWindow
  | SyncedPipContent PipContent

derive instance eqDocumentPipEvent :: Eq DocumentPipEvent

instance showDocumentPipEvent :: Show DocumentPipEvent where
  show RequestedPipWindow = "RequestedPipWindow"
  show ClosedPipWindow = "ClosedPipWindow"
  show (SyncedPipContent content) =
    "SyncedPipContent " <> show content.wordsToday <> " " <> content.status

type DocumentPipRecording = Array DocumentPipEvent

newtype RecordingDocumentPipM a =
  RecordingDocumentPipM (StateT DocumentPipRecording Identity a)

derive newtype instance functorRecordingDocumentPipM
  :: Functor RecordingDocumentPipM
derive newtype instance applyRecordingDocumentPipM
  :: Apply RecordingDocumentPipM
derive newtype instance applicativeRecordingDocumentPipM
  :: Applicative RecordingDocumentPipM
derive newtype instance bindRecordingDocumentPipM
  :: Bind RecordingDocumentPipM
derive newtype instance monadRecordingDocumentPipM
  :: Monad RecordingDocumentPipM

instance documentPipRecordingDocumentPipM
  :: DocumentPip RecordingDocumentPipM where
  requestPipWindow onOpened _onError _onClosedByUser = do
    RecordingDocumentPipM
      (modify_ (\events -> events <> [ RequestedPipWindow ]))
    onOpened
  closePipWindow onClosed = do
    RecordingDocumentPipM
      (modify_ (\events -> events <> [ ClosedPipWindow ]))
    onClosed
  syncPipContent content =
    RecordingDocumentPipM
      (modify_ (\events -> events <> [ SyncedPipContent content ]))

runRecordingDocumentPipM
  :: forall a
   . RecordingDocumentPipM a
  -> { result :: a, events :: DocumentPipRecording }
runRecordingDocumentPipM (RecordingDocumentPipM stateful) =
  case runStateT stateful [] of
    Identity (Tuple result events) -> { result, events }
