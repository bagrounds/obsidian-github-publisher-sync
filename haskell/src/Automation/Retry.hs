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
import Data.Typeable (Typeable)

transientHttpCodes :: Set Int
transientHttpCodes = Set.fromList [429, 502, 503, 504]

data HttpCodeException = HttpCodeException
  { hceCode :: Int
  , hceMessage :: String
  } deriving (Show, Typeable)

instance Exception HttpCodeException

data RetryOptions = RetryOptions
  { roMaxRetries  :: Int
  , roBaseDelayMs :: Int
  , roOnRetry     :: SomeException -> Int -> Int -> IO ()
  }

defaultRetryOptions :: RetryOptions
defaultRetryOptions = RetryOptions
  { roMaxRetries  = 3
  , roBaseDelayMs = 1000
  , roOnRetry     = \_ _ _ -> pure ()
  }

extractHttpCode :: SomeException -> Maybe Int
extractHttpCode e = hceCode <$> fromException @HttpCodeException e

isTransientError :: SomeException -> Bool
isTransientError e =
  case extractHttpCode e of
    Just code -> Set.member code transientHttpCodes
    Nothing   -> False

withRetry :: RetryOptions -> IO a -> IO a
withRetry opts action = go 0
  where
    go attempt =
      action `catch` \(err :: SomeException) ->
        if attempt < roMaxRetries opts && isTransientError err
        then do
          let delayMs = roBaseDelayMs opts * (2 ^ attempt)
          roOnRetry opts err (attempt + 1) delayMs
          threadDelay (delayMs * 1000)
          go (attempt + 1)
        else throwIO err
