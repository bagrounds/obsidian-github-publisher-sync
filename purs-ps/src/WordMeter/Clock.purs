module WordMeter.Clock
  ( nowMs
  , formatClockTime
  ) where

import Effect (Effect)

foreign import nowMsImpl :: Effect Number
foreign import formatClockTimeImpl :: Number -> String

-- | Current wall-clock time in milliseconds since the Unix epoch.
nowMs :: Effect Number
nowMs = nowMsImpl

-- | Format a millisecond timestamp as a locale clock time (e.g. `3:14:07 PM`).
-- |
-- | This is a deterministic function of the host runtime's clock formatter,
-- | so the rendered string can vary by environment. Tests should rely on the
-- | numeric accessors exposed by the test hook rather than scraping this text.
formatClockTime :: Number -> String
formatClockTime = formatClockTimeImpl
