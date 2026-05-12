-- | Captures the small slice of host environment the diagnostics
-- | drawer reports today: `navigator.userAgent` and
-- | `navigator.language`. The full version string lives in
-- | `WordMeter.Version` and is layered in by the caller. As later
-- | slices add capabilities (wake lock, recognition), this module will
-- | grow more fields rather than scattering `navigator.*` lookups
-- | through the codebase.
module WordMeter.Environment
  ( captureEnvironmentSnapshot
  ) where

import Effect (Effect)
import WordMeter.Diagnostics (EnvironmentSnapshot)

foreign import captureEnvironmentSnapshotImpl
  :: String
  -> Effect EnvironmentSnapshot

captureEnvironmentSnapshot :: String -> Effect EnvironmentSnapshot
captureEnvironmentSnapshot = captureEnvironmentSnapshotImpl
