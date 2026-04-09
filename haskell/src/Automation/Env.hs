module Automation.Env
  ( EnvironmentConfig (..)
  , isPlatformDisabled
  , isPlatformDisabledValue
  , getYesterdayDate
  , yesterdayDate
  , validateEnvironment
  ) where

import Control.Monad (filterM)
import Data.List (intercalate)
import Data.Maybe (fromMaybe, isJust)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Data.Time (Day, UTCTime (..), addDays, defaultTimeLocale, formatTime, getCurrentTime)
import System.Environment (lookupEnv)

import qualified Automation.Gemini as Gemini
import Automation.ObsidianSync (ObsidianCredentials (..))
import qualified Automation.Platforms.Bluesky as Bluesky
import qualified Automation.Platforms.Mastodon as Mastodon
import qualified Automation.Platforms.Twitter as Twitter
import Automation.Secret (Secret (..))
import Automation.Url (mkUrl)

data EnvironmentConfig = EnvironmentConfig
  { ecTwitter :: Maybe Twitter.Credentials
  , ecBluesky :: Maybe Bluesky.Credentials
  , ecMastodon :: Maybe Mastodon.Credentials
  , ecGemini :: Gemini.Config
  , ecObsidian :: ObsidianCredentials
  } deriving (Show, Eq)

isPlatformDisabled :: String -> IO Bool
isPlatformDisabled envVar = do
  mValue <- lookupEnv envVar
  pure $ isPlatformDisabledValue (fmap T.pack mValue)

isPlatformDisabledValue :: Maybe Text -> Bool
isPlatformDisabledValue mValue =
  fmap (T.strip . T.toLower) mValue `elem` [Just "true", Just "1", Just "yes"]

yesterdayDate :: UTCTime -> Day
yesterdayDate (UTCTime day _) = addDays (-1) day

getYesterdayDate :: IO Text
getYesterdayDate = do
  now <- getCurrentTime
  pure $ T.pack $ formatTime defaultTimeLocale "%Y-%m-%d" (yesterdayDate now)

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
    (Twitter.Credentials
      <$> fmap Secret (requireEnv "TWITTER_API_KEY")
      <*> fmap Secret (requireEnv "TWITTER_API_SECRET")
      <*> fmap Secret (requireEnv "TWITTER_ACCESS_TOKEN")
      <*> fmap Secret (requireEnv "TWITTER_ACCESS_SECRET"))

  bluesky <- whenPlatformEnabled "Bluesky" "DISABLE_BLUESKY"
    ["BLUESKY_IDENTIFIER", "BLUESKY_APP_PASSWORD"]
    (Bluesky.Credentials
      <$> requireEnv "BLUESKY_IDENTIFIER"
      <*> fmap Secret (requireEnv "BLUESKY_APP_PASSWORD"))

  mastodon <- whenPlatformEnabled "Mastodon" "DISABLE_MASTODON"
    ["MASTODON_INSTANCE_URL", "MASTODON_ACCESS_TOKEN"]
    (Mastodon.Credentials
      <$> (requireEnv "MASTODON_INSTANCE_URL" >>= either (fail . T.unpack) pure . mkUrl)
      <*> fmap Secret (requireEnv "MASTODON_ACCESS_TOKEN"))

  gemini <- Gemini.Config
    <$> fmap Secret (requireEnv "GEMINI_API_KEY")
    <*> fmap (fromMaybe Gemini.defaultModel) (lookupEnvText "GEMINI_MODEL")
    <*> fmap (fromMaybe Gemini.defaultQuestionModel) (lookupEnvText "GEMINI_QUESTION_MODEL")

  obsidian <- ObsidianCredentials
    <$> fmap Secret (requireEnv "OBSIDIAN_AUTH_TOKEN")
    <*> requireEnv "OBSIDIAN_VAULT_NAME"
    <*> fmap (fmap Secret) (lookupEnvText "OBSIDIAN_VAULT_PASSWORD")

  pure EnvironmentConfig
    { ecTwitter = twitter
    , ecBluesky = bluesky
    , ecMastodon = mastodon
    , ecGemini = gemini
    , ecObsidian = obsidian
    }
