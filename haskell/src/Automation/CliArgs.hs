module Automation.CliArgs
  ( CliArgs (..)
  , parseCliArgs
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Text.Read (readMaybe)

data CliArgs = CliArgs
  { cliHourOverride :: Maybe Int
  , cliTaskOverride :: Maybe Text
  } deriving (Show, Eq)

parseCliArgs :: [String] -> CliArgs
parseCliArgs = go (CliArgs Nothing Nothing)
  where
    go accumulator [] = accumulator
    go accumulator ("--hour" : hourStr : rest) = go (accumulator { cliHourOverride = readMaybe hourStr }) rest
    go accumulator ("--task" : taskStr : rest) = go (accumulator { cliTaskOverride = Just (T.pack taskStr) }) rest
    go accumulator (_ : rest) = go accumulator rest
