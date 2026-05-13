module WordMeter.FFI.Clipboard
  ( writeText
  ) where

import Prelude

import Effect (Effect)

foreign import writeText
  :: String
  -> Effect Unit
  -> (String -> Effect Unit)
  -> Effect Unit
