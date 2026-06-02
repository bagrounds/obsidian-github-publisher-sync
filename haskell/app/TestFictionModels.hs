-- | Live-API smoke test for the AI fiction model rotation pool.
--
-- Iterates over every model in 'Automation.AiFiction.fictionModelPool',
-- sends the same fiction prompt and generation config the production
-- scheduler uses through 'Gemini.generateContent', applies the same
-- 'AiFiction.parseFictionResponse' post-processing the daily run applies,
-- prints the published result, and exits non-zero if any model fails.
-- Designed to surface decommissioned models and request-shape regressions
-- before they hit the daily rotation.
--
-- Run from CI via the test-fiction-models GitHub Actions workflow
-- (workflow_dispatch — triggerable from the GitHub mobile web UI), or
-- locally with @GEMINI_API_KEY=… cabal run test-fiction-models@.
--
-- Set @MODELS@ to a comma-separated list of model identifiers to test
-- only a subset (e.g. @MODELS=gemini-2.5-flash,gemma-4-31b-it@).
-- When unset or empty, all models in the fiction pool are tested.
--
-- Authoritative model documentation:
--   * https://ai.google.dev/gemini-api/docs/models
--   * https://ai.google.dev/gemini-api/docs/deprecations
--   * https://ai.google.dev/gemma/docs/core/gemma_on_gemini_api
module Main where

import Control.Monad (forM)
import Data.Foldable (for_)
import qualified Data.List.NonEmpty as NE
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

sampleReflection :: T.Text
sampleReflection =
  "## Topics\n\
  \- Watched a mass murmuration of starlings over the lake at dusk\n\
  \- Read an article about how fungi networks connect trees underground\n\
  \- Experimented with sourdough starter that has been alive for three years"

resolveModels :: Maybe String -> [Gemini.Model]
resolveModels Nothing = NE.toList AiFiction.fictionModelPool
resolveModels (Just raw)
  | all (`elem` (" ," :: String)) raw = NE.toList AiFiction.fictionModelPool
  | otherwise = fmap (Gemini.modelFromText . T.strip) $ filter (not . T.null) $ T.splitOn "," (T.pack raw)

main :: IO ()
main = do
  hSetBuffering stdout LineBuffering
  apiKey <- lookupEnv "GEMINI_API_KEY"
  case apiKey of
    Nothing -> do
      TIO.putStrLn "❌ GEMINI_API_KEY is not set; cannot test fiction models against the live Gemini API."
      exitFailure
    Just key -> do
      modelsEnv <- lookupEnv "MODELS"
      let modelsUnderTest = resolveModels modelsEnv
          (systemInstruction, userPrompt) = AiFiction.buildFictionPrompt sampleReflection
      manager <- newManager tlsManagerSettings
      TIO.putStrLn $ "🐉 Testing " <> T.pack (show (length modelsUnderTest)) <> " model(s)...\n"
      results <- forM modelsUnderTest $ \model -> do
        TIO.putStrLn "═══════════════════════════════════════════════════════════════"
        TIO.putStrLn $ "🔄 " <> Gemini.modelToText model
        TIO.putStrLn "═══════════════════════════════════════════════════════════════"
        result <- Gemini.generateContent manager Gemini.Request
          { Gemini.requestPrompt            = userPrompt
          , Gemini.requestSystemInstruction = Just systemInstruction
          , Gemini.requestModel             = model
          , Gemini.requestApiKey            = Secret (T.pack key)
          , Gemini.requestGenerationConfig  = AiFiction.fictionGenerationConfig
          }
        case result of
          Right response -> do
            TIO.putStrLn "───────────────────────────────────────────────────────────────"
            TIO.putStrLn $ "✅ " <> Gemini.modelToText model <> " output:"
            TIO.putStrLn "───────────────────────────────────────────────────────────────"
            TIO.putStrLn $ AiFiction.parseFictionResponse (Gemini.responseText response)
            TIO.putStrLn ""
            pure True
          Left failure -> do
            TIO.putStrLn "───────────────────────────────────────────────────────────────"
            TIO.putStrLn $ "❌ " <> Gemini.modelToText model <> " failed:"
            TIO.putStrLn "───────────────────────────────────────────────────────────────"
            TIO.putStrLn $ T.pack (show failure)
            TIO.putStrLn ""
            pure False
      TIO.putStrLn "═══════════════════════════════════════════════════════════════"
      TIO.putStrLn "📋 Summary:"
      TIO.putStrLn "═══════════════════════════════════════════════════════════════"
      for_ (zip modelsUnderTest results) $ \(model, ok) ->
        TIO.putStrLn $ (if ok then "  ✅ " else "  ❌ ") <> Gemini.modelToText model
      let allPassed = and results
      if allPassed then exitSuccess else exitFailure
