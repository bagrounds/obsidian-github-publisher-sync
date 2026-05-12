module WordMeter.FFI.Environment
  ( captureEnvironmentSnapshot
  ) where

import Effect (Effect)
import WordMeter.Diagnostics (EnvironmentSnapshot)

foreign import captureEnvironmentSnapshot :: String -> Effect EnvironmentSnapshot
