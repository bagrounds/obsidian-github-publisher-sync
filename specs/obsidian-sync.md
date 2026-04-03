# 📱 Obsidian Sync — Vault Synchronization via ob CLI

## 🎯 Overview

📋 Synchronizes the Obsidian vault between the cloud and the local filesystem using the `ob` CLI tool.
🔄 Uses a simple pull-edit-push flow: one pull at the start, local edits, one push at the end.
🔒 Handles lock contention with retry logic and stale lock cleanup.
📝 Provides embed appending to write social media embeds to Obsidian notes.
🛡️ Pre-push circuit breaker prevents catastrophic data loss from anomalous file deletions.

## 🏗️ Architecture

### 📦 Components

| 🧩 Component | 📂 Path | 📝 Purpose |
|---|---|---|
| 📱 Sync Library | `haskell/src/Automation/ObsidianSync.hs` | 🔧 Vault sync, push, lock management, embed appending |

### 🔄 Data Flow — Scheduled Run

```
main()
  ├─ 📥 syncObsidianVault(credentials)     ← ONE pull at the start
  │       ├─ 📂 Create fresh vault directory (ephemeral CI — nothing exists yet)
  │       ├─ 📦 ob sync-setup → configure vault
  │       ├─ 🔄 ob sync → download all files
  │       └─ 📊 Record file count baseline
  │
  ├─ 🔧 Task 1: operates on vaultDir       ← Tasks receive vault dir
  ├─ 🔧 Task 2: operates on vaultDir
  ├─ 🔧 Task N: operates on vaultDir
  │
  └─ 📤 pushObsidianVault(vaultDir)        ← ONE push at the end
          ├─ 📊 Count files and validate against baseline
          ├─ 🛑 Circuit breaker: abort if any files lost
          └─ 🔄 ob sync to push changes
```

### 🔄 Data Flow — Standalone Scripts

```
📥 syncObsidianVault(credentials)      ← Pull
     ↓
📝 Edit files locally
     ↓
📤 pushObsidianVault(vaultDir)         ← Push
```

## 🛡️ Data Loss Prevention

### 📂 Ephemeral Vault Directory

🏗️ Every scheduled run executes in a fresh ephemeral CI container with no pre-existing vault directory.
📂 `syncObsidianVault` creates a new directory via `ob sync-setup` and populates it with `ob sync`.
🚫 No files are ever deleted — this system only creates and edits files.
⚠️ **Root Cause (2026-03-27 incident):** Bidirectional `ob sync` on a cached partial directory interpreted missing remote files as local deletions, propagating mass deletions to the remote vault.
✅ **Prevention:** No caching. No directory clearing. Ephemeral containers start from nothing every run.

### 📊 File Count Baseline Tracking

📈 After every successful vault pull, the file count is recorded to a `.vault-sync-file-count` marker file inside the vault directory.
📉 This baseline is used by the pre-push circuit breaker to detect anomalous file loss.

### 🛑 Pre-Push Circuit Breaker

🔍 Before every push operation, `validatePrePushFileCount` performs two safety checks:

1. **Minimum threshold check:** If the vault has fewer than 50 files total and no baseline exists, the push is refused. A healthy vault should always have significantly more than 50 files.

2. **Zero-deletion check:** If the vault has lost ANY files compared to the post-pull baseline, the push is refused. This system only ever creates new files or edits existing ones — it never deletes. Any file count decrease is anomalous and indicates corruption, accidental deletion, or a sync bug.

🛑 When the circuit breaker triggers, it throws an error with a descriptive message and the push is aborted, preventing the deletion from propagating to the remote vault.

| 📏 Parameter | 📝 Value | 📝 Purpose |
|---|---|---|
| `MIN_SAFE_FILE_COUNT` | 50 | 🔒 Absolute minimum files for push without baseline |
| Zero-deletion policy | currentCount >= baseline | 🔒 Any file loss blocks push — no tolerance for deletions |

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

## 📝 Embed Writing

✏️ `writeEmbedsToNote` writes embed sections directly to a note file in the vault directory without any sync operations.
📝 `appendEmbedsToObsidianNote` is a convenience wrapper that pulls, writes, and pushes — used only by standalone scripts.
🔄 During scheduled runs, `writeEmbedsToNote` is used directly since the vault is already pulled and will be pushed at the end.

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
| `syncObsidianVault(credentials)` | 📥 Fresh vault pull — create directory, sync-setup, sync |
| `pushObsidianVault(vaultDir, credentials)` | 📤 Push local changes with circuit breaker validation |
| `writeEmbedsToNote(filePath, sections)` | ✏️ Write embed sections to a note file (no sync) |
| `appendEmbedsToObsidianNote(notePath, sections, credentials)` | 📝 Pull, write embeds, push (standalone convenience) |
| `countVaultFiles(dir)` | 📊 Count non-hidden files recursively |
| `validatePrePushFileCount(vaultDir, currentCount)` | 🛑 Circuit breaker validation |
| `vaultFileCountPath(vaultDir)` | 📂 Path to baseline file count marker |

## 🛡️ Idempotency

✅ Sync operations are safe to re-run:
- 🔒 Lock cleanup prevents deadlocks from previous failed runs
- 💀 Process cleanup prevents resource leaks
- 📂 Every pull starts from an empty ephemeral directory — no stale state
- 📝 Embed writing checks for existing sections before appending
- 🛑 Circuit breaker prevents catastrophic deletion propagation

## 🎯 Targeted File Sync

🚫 Never use broad directory-level syncs from repo to vault. The repo's content directories contain Enveloppe-published versions of vault files, which may differ from vault originals due to wikilink conversion, dataview query expansion, or other publishing transforms.

✅ Only sync files from repo to vault that were actually modified during the current run.

📦 Modified files are tracked by:
- 🖼️ Image backfill results via `brModifiedFiles` in `BackfillResult`
- 🔗 Nav link updates via `nlrModified` in `NavLinkResult`
- 📝 Blog series posts via targeted `syncFileToVault` calls for the specific generated post, updated previous post, and AGENTS.md

⚠️ The `syncMarkdownDir` function was intentionally removed from the public API to prevent accidental broad directory syncs. Attachment syncs via `syncAttachmentsDir` use `syncIfMissing` which only copies files that are missing in the destination, making them safe for one-directional addition of newly generated images.
