module Main where

import Control.Monad (forM)
import Data.Foldable (for_)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Network.HTTP.Client (newManager)
import Network.HTTP.Client.TLS (tlsManagerSettings)
import System.Environment (lookupEnv)
import System.Exit (exitFailure, exitSuccess)
import System.IO (hSetBuffering, stdout, BufferMode(..))

import Automation.Secret (Secret (..))
import qualified Automation.Gemini as Gemini

prompt :: Text
prompt =
  "In one short sentence, describe a curious dragon discovering a library."

modelsUnderTest :: [Gemini.Model]
modelsUnderTest = [Gemini.Gemma4, Gemini.Gemma4MixtureOfExperts]

main :: IO ()
main = do
  hSetBuffering stdout LineBuffering
  apiKey <- lookupEnv "GEMINI_API_KEY"
  case apiKey of
    Nothing -> do
      TIO.putStrLn "❌ GEMINI_API_KEY is not set; cannot test Gemma 4 against the live Gemini API."
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
      let allPassed = and results
      for_ (zip modelsUnderTest results) $ \(model, ok) ->
        TIO.putStrLn $ (if ok then "✅ " else "❌ ") <> Gemini.modelToText model
      if allPassed then exitSuccess else exitFailure
