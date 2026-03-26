module Main where

import System.IO (hSetBuffering, stdout, BufferMode(..))

main :: IO ()
main = do
  hSetBuffering stdout LineBuffering
  putStrLn "🔧 Haskell inject-giscus — not yet wired up"
  putStrLn "   Use the TypeScript version: npx tsx scripts/inject-static-giscus.ts"
