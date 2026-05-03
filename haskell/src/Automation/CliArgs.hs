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
parseCliArgs = processArgs (CliArgs Nothing Nothing)
  where
    processArgs accumulator [] = accumulator
    processArgs accumulator ("--hour" : hourStr : rest) = processArgs (accumulator { cliHourOverride = readMaybe hourStr }) rest
    processArgs accumulator ("--task" : taskStr : rest) = processArgs (accumulator { cliTaskOverride = Just (T.pack taskStr) }) rest
    processArgs accumulator (_ : rest) = processArgs accumulator rest
