-- | Pure value identifying which `SpeechRecognition` configuration is
-- | currently driving a counting session. The slice-9b orchestrator
-- | picks `OnDevicePath` after a successful pre-flight and `CloudPath`
-- | everywhere else; slice 9c reads this back to decide whether a
-- | runtime `language-not-supported` deserves a one-shot cloud-path
-- | retry.
-- |
-- | This lives in its own module so both the reducer
-- | (`WordMeter.Recording.Reducer`) and the recognition capability
-- | (`WordMeter.Capability.Recognition`) can depend on it without a
-- | cycle.
module WordMeter.Recognition.Path
  ( RecognitionPath(..)
  , processLocallyFor
  ) where

import Prelude

data RecognitionPath = OnDevicePath | CloudPath

derive instance eqRecognitionPath :: Eq RecognitionPath

instance showRecognitionPath :: Show RecognitionPath where
  show OnDevicePath = "OnDevicePath"
  show CloudPath = "CloudPath"

processLocallyFor :: RecognitionPath -> Boolean
processLocallyFor OnDevicePath = true
processLocallyFor CloudPath = false
