module WordMeter.FFI.Confirm
  ( ConfirmError(..)
  , renderConfirmError
  , askForConfirmation
  ) where

import Prelude

import Data.Either (Either(..))
import Effect (Effect)

data ConfirmError
  = ConfirmUnavailable
  | ConfirmException String

derive instance eqConfirmError :: Eq ConfirmError

instance showConfirmError :: Show ConfirmError where
  show ConfirmUnavailable = "ConfirmUnavailable"
  show (ConfirmException detail) = "ConfirmException " <> show detail

renderConfirmError :: ConfirmError -> String
renderConfirmError = case _ of
  ConfirmUnavailable -> "window.confirm is unavailable in this environment"
  ConfirmException detail -> "window.confirm threw: " <> detail

type ConfirmOutcome =
  { tag :: String
  , detail :: String
  , accepted :: Boolean
  }

foreign import askForConfirmationImpl :: String -> Effect ConfirmOutcome

askForConfirmation :: String -> Effect (Either ConfirmError Boolean)
askForConfirmation prompt = interpretConfirm <$> askForConfirmationImpl prompt

interpretConfirm :: ConfirmOutcome -> Either ConfirmError Boolean
interpretConfirm outcome = case outcome.tag of
  "ok" -> Right outcome.accepted
  "unavailable" -> Left ConfirmUnavailable
  _ -> Left (ConfirmException outcome.detail)
