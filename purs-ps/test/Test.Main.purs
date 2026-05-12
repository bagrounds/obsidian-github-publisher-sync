-- | Spago test entry point. Empty for the hello-world slice; slice 3
-- | will start filling this in with `countWords`, dedup, and rate-math
-- | property tests.
module Test.Main where

import Prelude

import Effect (Effect)
import Effect.Console (log)

main :: Effect Unit
main = log "word-meter: no PureScript unit tests yet (see specs/word-meter-purescript-port.md)"
