module WordMeter.LocalDate
  ( LocalDate
  , localDateOf
  , localDateFromString
  , renderLocalDate
  ) where

import Prelude

import Data.DateTime.Instant (Instant, unInstant)
import Data.Newtype (unwrap)

-- | A calendar date in the user's local timezone, rendered as
-- | `YYYY-MM-DD`. Used to bucket word events into days for the
-- | "words today" tile and the per-day rate.
newtype LocalDate = LocalDate String

derive instance eqLocalDate :: Eq LocalDate
derive instance ordLocalDate :: Ord LocalDate

instance showLocalDate :: Show LocalDate where
  show (LocalDate value) = "(LocalDate " <> show value <> ")"

foreign import localDateOfMillis :: Number -> String

-- | Compute the local-time calendar date for an `Instant`.
localDateOf :: Instant -> LocalDate
localDateOf inst = LocalDate (localDateOfMillis (unwrap (unInstant inst)))

-- | Wrap a previously-rendered `YYYY-MM-DD` string back into a
-- | `LocalDate`. Used when rehydrating a persisted snapshot.
localDateFromString :: String -> LocalDate
localDateFromString = LocalDate

renderLocalDate :: LocalDate -> String
renderLocalDate (LocalDate value) = value
