-- | Thin FFI wrapper around `navigator.clipboard.writeText` so the
-- | diagnostics drawer's copy button can hand the formatted text off to
-- | the user with success / failure callbacks instead of dealing in
-- | raw JS Promises.
module WordMeter.Clipboard
  ( writeText
  ) where

import Prelude

import Effect (Effect)

foreign import writeText
  :: String
  -> Effect Unit
  -> (String -> Effect Unit)
  -> Effect Unit
