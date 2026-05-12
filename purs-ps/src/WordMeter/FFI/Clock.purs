module WordMeter.FFI.Clock
  ( currentTimeMillis
  ) where

import Effect (Effect)

foreign import currentTimeMillis :: Effect Number
