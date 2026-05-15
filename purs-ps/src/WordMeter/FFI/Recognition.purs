module WordMeter.FFI.Recognition
  ( RecognitionInstance
  , RecognitionError(..)
  , renderRecognitionError
  , recognitionApiAvailable
  , createRecognition
  , setRecognitionLocale
  , attachResultListener
  , attachErrorListener
  , attachEndListener
  , startRecognition
  , stopRecognition
  ) where

import Prelude

import Data.Either (Either)
import Effect (Effect)

foreign import data RecognitionInstance :: Type

data RecognitionError
  = RecognitionConstructError
  | RecognitionStartUnavailable
  | RecognitionStartException String
  | RecognitionStopException String

derive instance eqRecognitionError :: Eq RecognitionError

instance showRecognitionError :: Show RecognitionError where
  show RecognitionConstructError = "RecognitionConstructError"
  show RecognitionStartUnavailable = "RecognitionStartUnavailable"
  show (RecognitionStartException detail) = "RecognitionStartException " <> show detail
  show (RecognitionStopException detail) = "RecognitionStopException " <> show detail

renderRecognitionError :: RecognitionError -> String
renderRecognitionError = case _ of
  RecognitionConstructError ->
    "speech recognition api not found"
  RecognitionStartUnavailable ->
    "speech recognition not available"
  RecognitionStartException detail ->
    "speech recognition start failed: " <> detail
  RecognitionStopException detail ->
    "speech recognition stop failed: " <> detail

foreign import recognitionApiAvailable :: Effect Boolean

foreign import createRecognition
  :: Effect (Either RecognitionError RecognitionInstance)

foreign import setRecognitionLocale
  :: RecognitionInstance
  -> String
  -> Effect Unit

foreign import attachResultListener
  :: RecognitionInstance
  -> (String -> Number -> Effect Unit)
  -> Effect Unit

foreign import attachErrorListener
  :: RecognitionInstance
  -> (String -> String -> Effect Unit)
  -> Effect Unit

foreign import attachEndListener
  :: RecognitionInstance
  -> Effect Unit
  -> Effect Unit

foreign import startRecognition
  :: RecognitionInstance
  -> Effect (Either RecognitionError Unit)

foreign import stopRecognition
  :: RecognitionInstance
  -> Effect (Either RecognitionError Unit)
