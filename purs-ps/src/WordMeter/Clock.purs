module WordMeter.Clock
  ( nowMs
  , formatClockTime
  ) where

import Effect (Effect)

foreign import nowMs :: Effect Number
foreign import formatClockTime :: Number -> String
