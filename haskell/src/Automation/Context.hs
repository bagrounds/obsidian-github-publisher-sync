module Automation.Context
  ( AppContext (..)
  , mkAppContext
  ) where

import Network.HTTP.Client (Manager)

import Automation.Secret (Secret)

data AppContext = AppContext
  { appManager      :: Manager
  , appVaultDir     :: FilePath
  , appRepoRoot     :: FilePath
  , appGeminiApiKey :: Secret
  }

instance Show AppContext where
  show context = "AppContext { vaultDir = " <> show (appVaultDir context)
    <> ", repoRoot = " <> show (appRepoRoot context)
    <> ", geminiApiKey = " <> show (appGeminiApiKey context)
    <> " }"

mkAppContext :: Manager -> FilePath -> FilePath -> Secret -> Either String AppContext
mkAppContext manager vaultDir repoRoot geminiApiKey
  | null vaultDir = Left "Vault directory path cannot be empty"
  | null repoRoot = Left "Repository root path cannot be empty"
  | otherwise = Right AppContext
      { appManager = manager
      , appVaultDir = vaultDir
      , appRepoRoot = repoRoot
      , appGeminiApiKey = geminiApiKey
      }
