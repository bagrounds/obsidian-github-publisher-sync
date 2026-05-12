module WordMeter.Version where

-- | Bumped whenever the served PureScript bundle behavior changes in a
-- | user-visible way. Mirrors the WORD_METER_VERSION constant in the
-- | legacy `word-meter.js`, but lives on its own track until the cutover.
version :: String
version = "0.0.1"
