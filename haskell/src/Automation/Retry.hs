{-# LANGUAGE ScopedTypeVariables #-}

module Automation.Retry
  ( RetryOptions (..)
  , HttpCodeException (..)
  , transientHttpCodes
  , extractHttpCode
  , isTransientError
  , withRetry
  , defaultRetryOptions
  ) where

import Control.Concurrent (threadDelay)
import Control.Exception (Exception, SomeException, catch, throwIO, fromException)
import Data.Set (Set)
import qualified Data.Set as Set

transientHttpCodes :: Set Int
transientHttpCodes = Set.fromList [429, 502, 503, 504]

data HttpCodeException = HttpCodeException
  { code :: Int
  , message :: String
  } deriving (Show)

instance Exception HttpCodeException

data RetryOptions = RetryOptions
  { maxRetries            :: Int
  , baseDelayMilliseconds :: Int
  , onRetry               :: SomeException -> Int -> Int -> IO ()
  }

defaultRetryOptions :: RetryOptions
defaultRetryOptions = RetryOptions
  { maxRetries            = 3
  , baseDelayMilliseconds = 1000
  , onRetry               = \_ _ _ -> pure ()
  }

extractHttpCode :: SomeException -> Maybe Int
extractHttpCode exception = code <$> fromException @HttpCodeException exception

isTransientError :: SomeException -> Bool
isTransientError exception =
  case extractHttpCode exception of
    Just httpCode -> Set.member httpCode transientHttpCodes
    Nothing       -> False

withRetry :: RetryOptions -> IO a -> IO a
withRetry options action = go 0
  where
    go attempt =
      action `catch` \(err :: SomeException) ->
        if attempt < maxRetries options && isTransientError err
        then do
          let delayMilliseconds = baseDelayMilliseconds options * (2 ^ attempt)
          onRetry options err (attempt + 1) delayMilliseconds
          threadDelay (delayMilliseconds * 1000)
          go (attempt + 1)
        else throwIO err
