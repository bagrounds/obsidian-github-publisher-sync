module WordMeter.Capability.Recognition
  ( class Recognition
  , startRecognition
  , stopRecognition
  , recognitionApiAvailable
  , RecognitionEvent(..)
  , RecordingRecognitionM(..)
  , RecognitionRecording
  , runRecordingRecognitionM
  ) where

import Prelude

import Control.Monad.Reader.Class (ask)
import Control.Monad.State.Trans (StateT, modify_, runStateT)
import Data.Either (Either(..))
import Data.Identity (Identity(..))
import Data.Maybe (Maybe(..))
import Data.Tuple (Tuple(..))
import Effect (Effect)
import Effect.Class (liftEffect)
import Effect.Ref as Ref
import WordMeter.AppM (AppM(..), ApplicationEnvironment, runAppM)
import WordMeter.FFI.Recognition
  ( RecognitionError(..)
  , RecognitionInstance
  , renderRecognitionError
  )
import WordMeter.FFI.Recognition as FFI

class Monad m <= Recognition m where
  startRecognition
    :: String
    -> (String -> Number -> m Unit)
    -> (String -> String -> m Unit)
    -> m Unit
    -> m Unit
  stopRecognition
    :: m Unit
    -> (RecognitionError -> m Unit)
    -> m Unit
  recognitionApiAvailable :: m Boolean

instance recognitionAppM :: Recognition AppM where
  startRecognition locale onResult onError onEnd =
    AppM do
      environment <- ask
      liftEffect (startRecognitionInstance environment locale onResult onError onEnd)
  stopRecognition onStopped onError =
    AppM do
      environment <- ask
      liftEffect (stopRecognitionInstance environment onStopped onError)
  recognitionApiAvailable =
    AppM do
      liftEffect FFI.recognitionApiAvailable

startRecognitionInstance
  :: ApplicationEnvironment
  -> String
  -> (String -> Number -> AppM Unit)
  -> (String -> String -> AppM Unit)
  -> AppM Unit
  -> Effect Unit
startRecognitionInstance environment locale onResult onError onEnd = do
  let runHere :: forall a. AppM a -> Effect a
      runHere act = runAppM environment act
  createResult <- FFI.createRecognition
  case createResult of
    Left err -> do
      runHere (onError (renderRecognitionError err) "")
    Right instance_ -> do
      FFI.setRecognitionLocale instance_ locale
      FFI.attachResultListener instance_ \transcript timestamp -> do
        runHere (onResult transcript timestamp)
      FFI.attachErrorListener instance_ \errorCode errorMessage -> do
        runHere (onError errorCode errorMessage)
      FFI.attachEndListener instance_ do
        runHere onEnd
      Ref.write (Just instance_) environment.recognitionInstanceRef
      startResult <- FFI.startRecognition instance_
      case startResult of
        Left err -> do
          Ref.write Nothing environment.recognitionInstanceRef
          runHere (onError (renderRecognitionError err) "")
        Right _ -> pure unit

stopRecognitionInstance
  :: ApplicationEnvironment
  -> AppM Unit
  -> (RecognitionError -> AppM Unit)
  -> Effect Unit
stopRecognitionInstance environment onStopped onError = do
  let runHere :: forall a. AppM a -> Effect a
      runHere act = runAppM environment act
  currentInstance <- Ref.read environment.recognitionInstanceRef
  case currentInstance of
    Nothing -> runHere onStopped
    Just instance_ -> do
      stopResult <- FFI.stopRecognition instance_
      Ref.write Nothing environment.recognitionInstanceRef
      case stopResult of
        Left err -> runHere (onError err)
        Right _ -> runHere onStopped

data RecognitionEvent
  = StartedRecognition
  | StoppedRecognition

derive instance eqRecognitionEvent :: Eq RecognitionEvent

instance showRecognitionEvent :: Show RecognitionEvent where
  show StartedRecognition = "StartedRecognition"
  show StoppedRecognition = "StoppedRecognition"

type RecognitionRecording = Array RecognitionEvent

newtype RecordingRecognitionM a =
  RecordingRecognitionM (StateT RecognitionRecording Identity a)

derive newtype instance functorRecordingRecognitionM :: Functor RecordingRecognitionM
derive newtype instance applyRecordingRecognitionM :: Apply RecordingRecognitionM
derive newtype instance applicativeRecordingRecognitionM :: Applicative RecordingRecognitionM
derive newtype instance bindRecordingRecognitionM :: Bind RecordingRecognitionM
derive newtype instance monadRecordingRecognitionM :: Monad RecordingRecognitionM

instance recognitionRecordingRecognitionM :: Recognition RecordingRecognitionM where
  startRecognition _ _ _ _ = do
    RecordingRecognitionM (modify_ (\events -> events <> [ StartedRecognition ]))
  stopRecognition onStopped _ = do
    RecordingRecognitionM (modify_ (\events -> events <> [ StoppedRecognition ]))
    onStopped
  recognitionApiAvailable = pure true

runRecordingRecognitionM
  :: forall a
   . RecordingRecognitionM a
  -> { result :: a, events :: RecognitionRecording }
runRecordingRecognitionM (RecordingRecognitionM stateful) =
  case runStateT stateful [] of
    Identity (Tuple result events) -> { result, events }
