module Automation.Pipeline
  ( Pipeline (..)
  , PipelineStep
  , runPipeline
  , emptyPipeline
  , addStep
  ) where

import Data.Text (Text)
import qualified Data.Text as T

type PipelineStep = FilePath -> IO ()

data Pipeline = Pipeline
  { plName  :: Text
  , plSteps :: [PipelineStep]
  }

emptyPipeline :: Text -> Pipeline
emptyPipeline name = Pipeline name []

addStep :: PipelineStep -> Pipeline -> Pipeline
addStep step pipeline = pipeline { plSteps = plSteps pipeline <> [step] }

runPipeline :: Pipeline -> FilePath -> IO ()
runPipeline pipeline dir = traverse_ (\step -> step dir) (plSteps pipeline)
  where
    traverse_ f = foldr (\a rest -> f a *> rest) (pure ())

_unused :: Text
_unused = T.empty
