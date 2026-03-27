# 📱 Obsidian Sync — Vault Synchronization via ob CLI

## 🎯 Overview

📋 Synchronizes the Obsidian vault between the cloud and the local filesystem using the `ob` CLI tool.
🔄 Supports warm and cold cache sync paths for fast incremental updates.
🔒 Handles lock contention with retry logic and stale lock cleanup.
📝 Provides embed appending to push social media embeds back to Obsidian notes.

## 🏗️ Architecture

### 📦 Components

| 🧩 Component | 📂 Path | 📝 Purpose |
|---|---|---|
| 📱 Sync Library | `scripts/lib/obsidian-sync.ts` | 🔧 Vault sync, push, lock management, embed appending |

### 🔄 Data Flow

```
📥 syncObsidianVault(credentials)
         ↓
   ├─ 🔥 Warm cache path (vault already configured):
   │    ├─ 🧹 ensureSyncClean(vaultDir) → kill processes + remove lock
   │    └─ 🔄 runObSyncWithRetry() → ob sync with lock retry
   │
   └─ ❄️ Cold cache path (first run):
        ├─ 📦 ob sync-setup → configure vault
        └─ 🔄 runObSyncWithRetry() → ob sync with lock retry
         ↓
📂 Returns vaultDir path
         ↓
📝 appendEmbedsToObsidianNote(notePath, sections, credentials)
         ↓
   ├─ 📥 syncObsidianVault() → ensure latest
   ├─ ✏️ Append embed sections to note file
   └─ 📤 pushObsidianVault(vaultDir, credentials)
```

## 🔥 Warm Cache Sync

⚡ When the vault directory already exists from a previous run, the warm cache path skips the `ob sync-setup` step entirely.
🔄 This path runs `ob sync` directly, which performs a fast incremental sync.
🧹 Before syncing, `ensureSyncClean` kills any lingering processes and removes stale locks.

## ❄️ Cold Cache Sync

📦 On first run or when the vault directory is missing, `ob sync-setup` configures the vault with authentication credentials.
🔄 After setup, `ob sync` performs the initial full synchronization.

## 🔒 Lock Contention Retry

🔄 The `runObSyncWithRetry` function detects "Another sync instance" errors and retries with exponential backoff.
⏱️ Backoff follows a 2-second base multiplied by 2 raised to the attempt number.
🔁 Retries up to a configurable maximum number of attempts before giving up.
🧹 Between retries, lock cleanup is attempted to clear stale locks.

## 🧹 Lock and Process Management

🔒 `removeSyncLock` deletes the `.sync.lock` directory from the vault.
🔍 `logSyncDiagnostics` reports lock age and related running processes for troubleshooting.
💀 `killObProcesses` terminates lingering `obsidian-headless` processes with SIGTERM escalating to SIGKILL after 2 seconds.
🧹 `ensureSyncClean` combines process killing and lock removal into a single cleanup operation.

## 📤 Push Operations

📤 `pushObsidianVault` pushes local changes back to the vault cloud.
⏳ Includes a 1-second settling delay after push to ensure child processes exit cleanly.
🧹 Post-push cleanup kills any remaining processes.

## 📝 Embed Appending

📝 `appendEmbedsToObsidianNote` syncs the vault, appends embed sections to a note file, and pushes the changes.
🔄 This is the primary mechanism for persisting social media embeds back to Obsidian notes.

## 🔧 Key Functions

### 💾 I/O Functions

| 🔧 Function | 📝 Purpose |
|---|---|
| `runObCommand(args, options)` | 🔧 Execute `ob` CLI command with error wrapping |
| `removeSyncLock(vaultDir)` | 🔒 Remove stale `.sync.lock` directory |
| `logSyncDiagnostics(vaultDir)` | 🔍 Log lock state and related processes |
| `killObProcesses(vaultDir?)` | 💀 Kill lingering obsidian-headless processes |
| `ensureSyncClean(vaultDir)` | 🧹 Kill processes and remove lock for clean state |
| `runObSyncWithRetry(args, options, vaultDir, maxRetries)` | 🔄 Run ob sync with lock contention retry |
| `syncObsidianVault(credentials)` | 📥 Full vault sync with warm/cold cache paths |
| `pushObsidianVault(vaultDir, credentials)` | 📤 Push local changes to vault cloud |
| `appendEmbedsToObsidianNote(notePath, sections, credentials)` | 📝 Append embed sections and push |

## 🛡️ Idempotency

✅ Sync operations are safe to re-run:
- 🔒 Lock cleanup prevents deadlocks from previous failed runs
- 💀 Process cleanup prevents resource leaks
- 📥 Incremental sync only transfers changed files
- 📝 Embed appending checks for existing sections before writing
