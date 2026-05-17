module WordMeter.Clock
  ( formatClockTime
  ) where

import Data.DateTime.Instant (Instant, unInstant)
import Data.Newtype (unwrap)

foreign import formatClockTimeMillis :: Number -> String

formatClockTime :: Instant -> String
formatClockTime inst = formatClockTimeMillis (unwrap (unInstant inst))
