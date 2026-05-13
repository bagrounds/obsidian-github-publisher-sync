module WordMeter.FFI.Confirm
  ( requestConfirmation
  ) where

import Effect (Effect)

-- | Shows a native browser confirmation dialog and returns the user's choice.
-- | Returns `false` when `window.confirm` is unavailable (e.g. server-side
-- | rendering or sandboxed iframes).
foreign import requestConfirmation :: String -> Effect Boolean
