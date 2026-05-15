module WordMeter.FFI.Visibility
  ( subscribeVisibilityVisible
  ) where

import Prelude

import Effect (Effect)

-- | Register a callback that fires every time the document transitions
-- | to `visibilityState === "visible"`. Used so the program can
-- | re-acquire a screen wake lock the browser auto-released when the
-- | tab was hidden. The handler is fire-and-forget: there is no
-- | unsubscribe path because the visibility lifetime is the page
-- | lifetime.
foreign import subscribeVisibilityVisibleImpl :: Effect Unit -> Effect Unit

subscribeVisibilityVisible :: Effect Unit -> Effect Unit
subscribeVisibilityVisible = subscribeVisibilityVisibleImpl
