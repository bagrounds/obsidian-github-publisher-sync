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

## 🛡️ Vault Content Protection — Targeted File Sync

### ❌ Problem: Broad Directory Sync Corrupts Vault

🚨 **Incident (2026-04-02):** The `backfill-blog-images` task previously used `syncMarkdownDir` to sync ALL `.md` files from `repoRoot/<dir>/` to `vaultDir/<dir>/` for each directory in `backfillContentIds`. When the Enveloppe plugin's root folder was misconfigured (changed from `content` to empty), it published ~2986 files to the repo root instead of `content/`. These Enveloppe-published files had:
- 📝 Wikilinks converted to markdown links (Enveloppe transforms during publish)
- ⬜ Trailing whitespace added to every line
- 📊 Dataview queries rendered as static markdown lists

🔄 The `syncMarkdownDir` function blindly synced these corrupted files back to the vault, overwriting:
- 📄 Index pages with dataview queries → replaced with rendered static lists
- 📅 Reflection date files → wikilinks replaced with markdown links

📊 The corruption matched exactly the `backfillContentIds` directories: reflections, ai-blog, auto-blog-zero, chickie-loo, systems-for-public-good. Directories NOT in this list (books, videos, topics) were unaffected.

### ✅ Fix: Targeted File Sync

🎯 The backfill task now syncs ONLY files that were actually modified by the current task:
- 🖼️ Files modified by image backfill (`brModifiedFiles` from `backfillImages`)
- 🔗 Files modified by nav link updates (`nlrModified` from `ensureAllNavLinks`)

🚫 Vault-managed files like `index.md` (dataview queries), unmodified reflection files, and other user-created content are NEVER overwritten by the sync.

### 🔒 Rule: Never Blindly Sync Repo → Vault

⚠️ **Critical invariant:** The vault is the source of truth for user-created content. The scheduled task may only write to the vault:
1. ✏️ Files it generated (blog posts, images, AI fiction)
2. 📝 Files it modified (frontmatter updates, link insertions, titles)
3. 🔗 Files explicitly tracked as modified by the current run

🚫 **Never** use broad directory sync (`syncMarkdownDir`) from repo to vault. The repo may contain Enveloppe-published versions that have destructive transformations applied.

## 🛡️ Idempotency

✅ Sync operations are safe to re-run:
- 🔒 Lock cleanup prevents deadlocks from previous failed runs
- 💀 Process cleanup prevents resource leaks
- 📂 Every pull starts from an empty ephemeral directory — no stale state
- 📝 Embed writing checks for existing sections before appending
- 🛑 Circuit breaker prevents catastrophic deletion propagation
- 🎯 Only task-modified files are synced back to vault — no accidental overwrites
