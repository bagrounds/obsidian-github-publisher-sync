-- | Thin FFI over `window.confirm` so the slice-6 reset button can
-- | ask the user to acknowledge a destructive action before the
-- | reducer fires. Returns `true` when the user accepts and `false`
-- | when they decline or when the confirm dialog is unavailable
-- | (server-side rendering, headless contexts without a window).
module WordMeter.FFI.Confirm
  ( askForConfirmation
  ) where

import Effect (Effect)

foreign import askForConfirmation :: String -> Effect Boolean
