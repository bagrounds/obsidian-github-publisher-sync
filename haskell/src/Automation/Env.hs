module Automation.Env
  ( isPlatformDisabled
  , getYesterdayDate
  , validateEnvironment
  ) where

import Control.Monad (filterM)
import Data.List (intercalate)
import Data.Maybe (fromMaybe, isJust)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Data.Time (UTCTime (..), addDays, defaultTimeLocale, formatTime, getCurrentTime)
import System.Environment (lookupEnv)

import Automation.Types
  ( BlueskyCredentials (..)
  , EnvironmentConfig (..)
  , GeminiConfig (..)
  , MastodonCredentials (..)
  , ObsidianCredentials (..)
  , TwitterCredentials (..)
  , defaultGeminiModel
  , defaultQuestionModel
  )

isPlatformDisabled :: String -> IO Bool
isPlatformDisabled envVar = do
  mValue <- lookupEnv envVar
  pure $ fmap (T.strip . T.toLower . T.pack) mValue `elem` [Just "true", Just "1", Just "yes"]

getYesterdayDate :: IO Text
getYesterdayDate = do
  UTCTime day _ <- getCurrentTime
  pure $ T.pack $ formatTime defaultTimeLocale "%Y-%m-%d" (addDays (-1) day)

allPresent :: [String] -> IO Bool
allPresent = fmap and . traverse (fmap isJust . lookupEnv)

logDisabled :: Text -> String -> IO ()
logDisabled platform envVar = do
  disabled <- isPlatformDisabled envVar
  case disabled of
    True  -> TIO.putStrLn $ "🚫 " <> platform <> " disabled via " <> T.pack envVar <> " env var"
    False -> pure ()

requireEnv :: String -> IO Text
requireEnv key =
  lookupEnv key >>= \case
    Just value -> pure (T.pack value)
    Nothing    -> error $ "Missing required environment variable: " <> key

lookupEnvText :: String -> IO (Maybe Text)
lookupEnvText = fmap (fmap T.pack) . lookupEnv

whenPlatformEnabled :: Text -> String -> [String] -> IO a -> IO (Maybe a)
whenPlatformEnabled platform disableVar keys action = do
  logDisabled platform disableVar
  disabled <- isPlatformDisabled disableVar
  present <- allPresent keys
  case (disabled, present) of
    (False, True) -> Just <$> action
    _             -> pure Nothing

validateEnvironment :: IO EnvironmentConfig
validateEnvironment = do
  let required = ["GEMINI_API_KEY", "OBSIDIAN_AUTH_TOKEN", "OBSIDIAN_VAULT_NAME"]
  missing <- filterM (fmap (not . isJust) . lookupEnv) required
  case missing of
    [] -> pure ()
    _  -> error $ "Missing required environment variables: " <> intercalate ", " missing

  twitter <- whenPlatformEnabled "Twitter" "DISABLE_TWITTER"
    ["TWITTER_API_KEY", "TWITTER_API_SECRET", "TWITTER_ACCESS_TOKEN", "TWITTER_ACCESS_SECRET"]
    (TwitterCredentials
      <$> requireEnv "TWITTER_API_KEY"
      <*> requireEnv "TWITTER_API_SECRET"
      <*> requireEnv "TWITTER_ACCESS_TOKEN"
      <*> requireEnv "TWITTER_ACCESS_SECRET")

  bluesky <- whenPlatformEnabled "Bluesky" "DISABLE_BLUESKY"
    ["BLUESKY_IDENTIFIER", "BLUESKY_APP_PASSWORD"]
    (BlueskyCredentials
      <$> requireEnv "BLUESKY_IDENTIFIER"
      <*> requireEnv "BLUESKY_APP_PASSWORD")

  mastodon <- whenPlatformEnabled "Mastodon" "DISABLE_MASTODON"
    ["MASTODON_INSTANCE_URL", "MASTODON_ACCESS_TOKEN"]
    (MastodonCredentials
      <$> requireEnv "MASTODON_INSTANCE_URL"
      <*> requireEnv "MASTODON_ACCESS_TOKEN")

  gemini <- GeminiConfig
    <$> requireEnv "GEMINI_API_KEY"
    <*> fmap (fromMaybe defaultGeminiModel) (lookupEnvText "GEMINI_MODEL")
    <*> fmap (fromMaybe defaultQuestionModel) (lookupEnvText "GEMINI_QUESTION_MODEL")

  obsidian <- ObsidianCredentials
    <$> requireEnv "OBSIDIAN_AUTH_TOKEN"
    <*> requireEnv "OBSIDIAN_VAULT_NAME"
    <*> lookupEnvText "OBSIDIAN_VAULT_PASSWORD"

  pure EnvironmentConfig
    { ecTwitter = twitter
    , ecBluesky = bluesky
    , ecMastodon = mastodon
    , ecGemini = gemini
    , ecObsidian = obsidian
    }
