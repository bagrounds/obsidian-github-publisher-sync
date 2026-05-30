-- | Live-API smoke test for the AI fiction model rotation pool.
--
-- Iterates over every model in 'Automation.AiFiction.fictionModelPool',
-- sends a tiny fiction prompt through the same 'Gemini.generateContent'
-- code path the production scheduler uses, prints the result, and exits
-- non-zero if any model fails. Designed to surface decommissioned models
-- and request-shape regressions before they hit the daily rotation.
--
-- Run from CI via the test-fiction-models GitHub Actions workflow
-- (workflow_dispatch — triggerable from the GitHub mobile web UI), or
-- locally with @GEMINI_API_KEY=… cabal run test-fiction-models@.
--
-- Authoritative model documentation:
--   * https://ai.google.dev/gemini-api/docs/models
--   * https://ai.google.dev/gemini-api/docs/deprecations
--   * https://ai.google.dev/gemma/docs/core/gemma_on_gemini_api
module Main where

import Control.Monad (forM)
import Data.Foldable (for_)
import qualified Data.List.NonEmpty as NE
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Network.HTTP.Client (newManager)
import Network.HTTP.Client.TLS (tlsManagerSettings)
import System.Environment (lookupEnv)
import System.Exit (exitFailure, exitSuccess)
import System.IO (hSetBuffering, stdout, BufferMode(..))

import Automation.Secret (Secret (..))
import qualified Automation.AiFiction as AiFiction
import qualified Automation.Gemini as Gemini

prompt :: Text
prompt =
  "In one short sentence, describe a curious dragon discovering a library."

modelsUnderTest :: [Gemini.Model]
modelsUnderTest = NE.toList AiFiction.fictionModelPool

main :: IO ()
main = do
  hSetBuffering stdout LineBuffering
  apiKey <- lookupEnv "GEMINI_API_KEY"
  case apiKey of
    Nothing -> do
      TIO.putStrLn "❌ GEMINI_API_KEY is not set; cannot test fiction models against the live Gemini API."
      exitFailure
    Just key -> do
      manager <- newManager tlsManagerSettings
      results <- forM modelsUnderTest $ \model -> do
        TIO.putStrLn $ "🐉 Testing " <> Gemini.modelToText model <> " against the live Gemini API..."
        result <- Gemini.generateContent manager Gemini.Request
          { Gemini.requestPrompt            = prompt
          , Gemini.requestSystemInstruction = Nothing
          , Gemini.requestModel             = model
          , Gemini.requestApiKey            = Secret (T.pack key)
          , Gemini.requestGenerationConfig  = Gemini.defaultGenerationConfig
          }
        case result of
          Right response -> do
            TIO.putStrLn $ "✅ " <> Gemini.modelToText model <> " responded: " <> Gemini.responseText response
            pure True
          Left failure -> do
            TIO.putStrLn $ "❌ " <> Gemini.modelToText model <> " failed: " <> T.pack (show failure)
            pure False
      TIO.putStrLn ""
      TIO.putStrLn "📋 Summary:"
      for_ (zip modelsUnderTest results) $ \(model, ok) ->
        TIO.putStrLn $ (if ok then "  ✅ " else "  ❌ ") <> Gemini.modelToText model
      let allPassed = and results
      if allPassed then exitSuccess else exitFailure
