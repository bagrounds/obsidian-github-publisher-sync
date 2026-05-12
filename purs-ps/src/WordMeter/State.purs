module WordMeter.State
  ( Cell
  , new
  , read
  , write
  , modify
  ) where

import Prelude

import Effect (Effect)

foreign import data Cell :: Type -> Type

foreign import newCell :: forall a. a -> Effect (Cell a)
foreign import readCell :: forall a. Cell a -> Effect a
foreign import writeCell :: forall a. a -> Cell a -> Effect Unit

new :: forall a. a -> Effect (Cell a)
new = newCell

read :: forall a. Cell a -> Effect a
read = readCell

write :: forall a. a -> Cell a -> Effect Unit
write = writeCell

modify :: forall a. (a -> a) -> Cell a -> Effect Unit
modify f cell = do
  current <- readCell cell
  writeCell (f current) cell
