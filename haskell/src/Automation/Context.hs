module Automation.Context
  ( AppContext
      ( AppContext
      , httpManager
      , vaultDirectory
      , repoRoot
      , geminiApiKey
      , obsidianCredentials
      )
  , mkAppContext
  ) where

import Network.HTTP.Client (Manager)

import Automation.ObsidianSync (ObsidianCredentials)
import Automation.Secret (Secret)

data AppContext = AppContext
  { httpManager          :: Manager
  , vaultDirectory             :: FilePath
  , repoRoot             :: FilePath
  , geminiApiKey         :: Secret
  , obsidianCredentials  :: ObsidianCredentials
  }

instance Show AppContext where
  show context = "AppContext { vaultDirectory = " <> show (vaultDirectory context)
    <> ", repoRoot = " <> show (repoRoot context)
    <> ", geminiApiKey = " <> show (geminiApiKey context)
    <> ", obsidianCredentials = " <> show (obsidianCredentials context)
    <> " }"

mkAppContext :: Manager -> FilePath -> FilePath -> Secret -> ObsidianCredentials -> Either String AppContext
mkAppContext manager vault repo gemini obsidian
  | null vault = Left "Vault directory path cannot be empty"
  | null repo = Left "Repository root path cannot be empty"
  | otherwise = Right AppContext
      { httpManager = manager
      , vaultDirectory = vault
      , repoRoot = repo
      , geminiApiKey = gemini
      , obsidianCredentials = obsidian
      }
