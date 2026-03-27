# 📱 Obsidian Sync — Vault Synchronization via ob CLI

## 🎯 Overview

📋 Synchronizes the Obsidian vault between the cloud and the local filesystem using the `ob` CLI tool.
🔄 Supports warm and cold cache sync paths for fast incremental updates.
🔒 Handles lock contention with retry logic and stale lock cleanup.
📝 Provides embed appending to push social media embeds back to Obsidian notes.
🛡️ Multi-layered data loss prevention with cache clearing and pre-push circuit breakers.

## 🏗️ Architecture

### 📦 Components

| 🧩 Component | 📂 Path | 📝 Purpose |
|---|---|---|
| 📱 Sync Library (TS) | `scripts/lib/obsidian-sync.ts` | 🔧 Vault sync, push, lock management, embed appending |
| 📱 Sync Library (HS) | `haskell/src/Automation/ObsidianSync.hs` | 🔧 Haskell implementation with identical safeguards |

### 🔄 Data Flow

```
📥 syncObsidianVault(credentials)
         ↓
   ├─ 🔥 Warm cache path (vault already configured):
   │    ├─ 🧹 ensureSyncClean(vaultDir) → kill processes + remove lock
   │    ├─ 🔄 runObSyncWithRetry() → ob sync with lock retry
   │    └─ 📊 Record file count baseline
   │
   └─ ❄️ Cold cache path (first run / fallback):
        ├─ 🧹 Clear entire vault directory (data loss prevention)
        ├─ 📦 ob sync-setup → configure vault on clean directory
        ├─ 🔄 runObSyncWithRetry() → ob sync with lock retry
        └─ 📊 Record file count baseline
         ↓
📂 Returns vaultDir path
         ↓
📝 appendEmbedsToObsidianNote(notePath, sections, credentials)
         ↓
   ├─ 📥 syncObsidianVault() → ensure latest
   ├─ ✏️ Append embed sections to note file
   └─ 📤 pushObsidianVault(vaultDir, credentials)
              ├─ 📊 Count files and validate against baseline
              ├─ 🛑 Circuit breaker: abort if >30% file loss
              └─ 🔄 ob sync to push changes
```

## 🛡️ Data Loss Prevention

### 🧹 Cold Cache Directory Clearing

⚠️ **Root Cause (2026-03-27 incident):** When warm cache sync fails, the fallback to `coldCacheSync` previously ran `ob sync-setup` on the existing partial cache directory. Since `ob sync` operates in bidirectional mode by default, it interpreted remote files missing from the partial local cache as "locally deleted" and propagated mass deletions to the remote vault.

✅ **Fix:** `coldCacheSync` now completely clears the vault directory before running `sync-setup`, ensuring a clean state with no stale files that could be misinterpreted as deletions.

### 📊 File Count Baseline Tracking

📈 After every successful vault pull (warm or cold cache), the file count is recorded to a `.vault-sync-file-count` marker file inside the vault directory.
📉 This baseline is used by the pre-push circuit breaker to detect anomalous file loss.

### 🛑 Pre-Push Circuit Breaker

🔍 Before every push operation, `validatePrePushFileCount` performs two safety checks:

1. **Minimum threshold check:** If the vault has fewer than 50 files total and no baseline exists, the push is refused. A healthy vault should always have significantly more than 50 files.

2. **Percentage drop check:** If the vault has lost more than 30% of files compared to the post-pull baseline, the push is refused. This catches scenarios where the local vault directory has been corrupted, partially cleared, or incorrectly rebuilt.

🛑 When the circuit breaker triggers, it throws an error with a descriptive message and the push is aborted, preventing the deletion from propagating to the remote vault.

| 📏 Parameter | 📝 Value | 📝 Purpose |
|---|---|---|
| `MIN_SAFE_FILE_COUNT` | 50 | 🔒 Absolute minimum files for push without baseline |
| `MAX_FILE_DROP_PERCENT` | 30% | 🔒 Maximum allowed file loss relative to baseline |

## 🔥 Warm Cache Sync

⚡ When the vault directory already exists from a previous run, the warm cache path skips the `ob sync-setup` step entirely.
🔄 This path runs `ob sync` directly, which performs a fast incremental sync.
🧹 Before syncing, `ensureSyncClean` kills any lingering processes and removes stale locks.
📊 After successful sync, records file count baseline.

## ❄️ Cold Cache Sync

🧹 On first run, fallback, or when the vault directory is missing, the vault directory is completely cleared before setup.
📦 `ob sync-setup` configures the vault with authentication credentials on a clean directory.
🔄 After setup, `ob sync` performs the initial full synchronization.
📊 After successful sync, records file count baseline.

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

📊 `pushObsidianVault` counts files and validates against baseline before pushing.
🛑 Circuit breaker prevents pushes that would propagate catastrophic deletions.
📤 Pushes local changes back to the vault cloud via `ob sync`.
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
| `pushObsidianVault(vaultDir, credentials)` | 📤 Push local changes with circuit breaker validation |
| `appendEmbedsToObsidianNote(notePath, sections, credentials)` | 📝 Append embed sections and push |
| `countVaultFiles(dir)` | 📊 Count non-hidden files recursively |
| `validatePrePushFileCount(vaultDir, currentCount)` | 🛑 Circuit breaker validation |
| `vaultFileCountPath(vaultDir)` | 📂 Path to baseline file count marker |

## 🛡️ Idempotency

✅ Sync operations are safe to re-run:
- 🔒 Lock cleanup prevents deadlocks from previous failed runs
- 💀 Process cleanup prevents resource leaks
- 📥 Incremental sync only transfers changed files
- 📝 Embed appending checks for existing sections before writing
- 🧹 Cold cache fallback clears directory to prevent stale state
- 🛑 Circuit breaker prevents catastrophic deletion propagation
