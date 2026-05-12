-- | Thin FFI surface over the small slice of the DOM we need for the
-- | hello-world slice. Each binding stays narrow on purpose so we can
-- | replace it with a proper capability-class instance in slice 3
-- | without rewriting callers.
module WordMeter.FFI
  ( Element
  , Maybe(..)
  , getElementById
  , setInnerHtml
  ) where

import Prelude (Unit)

import Effect (Effect)

foreign import data Element :: Type

foreign import getElementByIdImpl
  :: (Element -> Maybe Element)
  -> Maybe Element
  -> String
  -> Effect (Maybe Element)

foreign import setInnerHtml :: Element -> String -> Effect Unit

-- | We re-declare a local `Maybe` here instead of pulling in
-- | `purescript-maybe` to keep the userspace-dep footprint at the
-- | absolute minimum (prelude + effect + console). Slice 3 will
-- | replace this local definition with the capability layer's shared
-- | option type once we evaluate whether `purescript-maybe` is worth
-- | accepting as a dep alongside the rest of the core libs.
data Maybe a = Nothing | Just a

getElementById :: String -> Effect (Maybe Element)
getElementById = getElementByIdImpl Just Nothing
