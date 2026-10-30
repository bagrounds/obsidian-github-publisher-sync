# 📱 Obsidian Sync — Vault Synchronization via ob CLI

## 🎯 Overview

📋 Synchronizes the Obsidian vault between the cloud and the local filesystem using the `ob` CLI tool.
🔄 Uses a simple pull-edit-push flow: one pull at the start, local edits, one push at the end.
🔒 Handles lock contention and dropped sync connections with retry logic and stale lock cleanup.
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

## 🔁 Sync Failure Retry

🧭 The pure `classifySyncFailure` function turns the text of a failed `ob` command into a `SyncFailure`: either `Retryable` with a `RetryableSyncFailure` reason, or `Unrecoverable`.

| 🏷️ Classification | 🔎 Signature in `ob` output | 🔧 Response |
|---|---|---|
| `Retryable LockContention` | `Another sync instance` | 🔁 Clean up and retry |
| `Retryable ConnectionLost` | `Error: Disconnected`, `Unable to connect to server`, `The connection to the server has encountered an error` | 🔁 Clean up and resume |
| `Unrecoverable` | ➖ anything else, such as an expired subscription or a missing vault | 🛑 Rethrow immediately |

🧭 Classification lives in the `Automation.ObsidianSync.Retry` module, next to the retry policy that consumes it.

### 📈 Progress-Aware Retry Policy

🔄 `runObSyncWithRetry` records every attempt (its outcome, the vault files on disk before and after, and its duration) and asks the pure `decide` function what to do next.
📂 An attempt made progress when the number of non-hidden files on disk grew while it ran.
🔁 Retryable failures keep being retried for as long as attempts keep making progress, because a resumed pull continues where the last one stopped.
🛑 The loop gives up with `NoProgress` once more than 5 consecutive failed attempts brought no new files, which preserves the old limit of 5 retries for lock contention and for pushes, where the file count does not change.
⏰ The loop gives up with `DeadlineReached` when the next retry would start more than 45 minutes after the sync began, which bounds a run that keeps making only tiny progress.
🛑 An `Unrecoverable` failure stops the loop immediately, and a successful attempt stops it with `SyncCompleted`.
⏱️ The backoff before retry number N is 2 seconds doubled for each earlier retry, capped at 60 seconds, then scaled by a random equal jitter between one half and the full value.
🎲 The jitter is drawn in the imperative shell and passed into the pure `backoffDelay` and `decide` functions, so the policy is deterministic under test.
🧹 Between retries, `ensureSyncClean` kills lingering processes and removes the stale `.sync.lock` a crashed `ob` process leaves behind.
📊 Each retry logs the failure, the attempt number and duration, the files gained, the files on disk, the total elapsed time, and the next delay.
🔎 Connection signatures are matched on the error text written by `ob` (such as `Error: Disconnected`), not on progress lines like `Disconnected from server`, so a vault file with a similar name cannot trigger a retry.

| 📏 Parameter | 📝 Value | 📝 Purpose |
|---|---|---|
| `baseDelay` | 2 seconds | ⏱️ Delay before the first retry, before jitter |
| `maximumDelay` | 60 seconds | 🧢 Ceiling on any single backoff |
| `maximumStalledRetries` | 5 | 🛑 Consecutive retries allowed without new files |
| `deadline` | 45 minutes | ⏰ Latest time after the sync starts at which a retry may begin |

### 📈 Why Progress Decides (2026-10-29 analysis)

📉 After the connection-loss retry shipped, failures fell from 12.4 percent to 3.5 percent of scheduled runs, and the two remaining failures both ran out of a fixed budget of 5 retries while every attempt was still downloading files.
📂 One run grew from 7,733 to 9,992 files across its retries and stopped about 140 files short; another grew from 875 to about 3,500.
🔁 A fixed count treats a nearly finished pull the same as a stuck one, while counting attempts without progress lets a resumable pull finish and still stops quickly when nothing moves.

### 📝 Sync Report in the Job Summary

🧾 Each pull and push produces a `Report` from the `Automation.ObsidianSync.Report` module: the direction, every attempt, the stop reason, and the elapsed time.
🖨️ The report headline is printed to the run log, and the pure `render` function turns the report into a markdown section with one table row per attempt.
📌 The section is appended to the file named by `GITHUB_STEP_SUMMARY` through the `Automation.GitHubStepSummary` module, so sync reliability is visible on the run page without reading logs.
🛑 The report is published before a failed sync rethrows its last error, so abandoned syncs are summarized too.
🔇 Outside GitHub Actions, or when the summary file cannot be written, the typed `StepSummaryError` is logged and the sync continues; a missing summary never fails a run.

### 🔌 Why Connection Loss Is Retried (2026-10-22 incident)

⚠️ About one in five scheduled runs failed in October because the Obsidian Sync WebSocket closed in the middle of the cold vault pull, which downloads about 10,700 files over 10 to 15 minutes.
📉 Failures happened at random points, from 44 seconds to 51 minutes in, with no rate limit or quota messages, which suggests transient connection drops rather than a fixed limit.
🔁 The `ob` client already treats disconnects as routine in continuous mode by reconnecting and requesting another sync; the one-shot `ob sync` used here exits instead, so the retry loop supplies the reconnect.

### 🛡️ Why Resuming a Partial Pull Is Safe

📂 A retry reuses the same vault directory and the same `ob` state database (`~/.config/obsidian-headless/sync/<vault>/state.db`) that the interrupted attempt wrote.
✅ `ob` records a server file only after the matching local file has been written, and keeps unprocessed server changes in a pending queue, so files that were not yet downloaded remain pending downloads, not apparent local deletions.
🆚 This differs from the 2026-03-27 incident, where a stale cached directory from an earlier run was paired with fresh state; within a single run, the directory and state database stay consistent.
🛑 The pre-push circuit breaker still compares the pushed file count against the post-pull baseline as a final guard.

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
| `classifySyncFailure(message)` | 🧭 Pure classification of `ob` failure output into retryable or unrecoverable |
| `runObSyncWithRetry(direction, args, options, vaultDir)` | 🔄 Run ob sync under the progress-aware retry policy and return the attempt report |
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
- 🔌 Dropped connections resume from the state `ob` already recorded instead of failing the run
- 💀 Process cleanup prevents resource leaks
- 📂 Every pull starts from an empty ephemeral directory — no stale state
- 📝 Embed writing checks for existing sections before appending
- 🛑 Circuit breaker prevents catastrophic deletion propagation

## 🎯 Vault-Direct Editing

🚫 Never copy existing files from the git repo to the vault. The repo's content directories contain Enveloppe-published versions of vault files, which may differ from vault originals due to wikilink conversion, dataview query expansion, or other publishing transforms. Copying these back would silently corrupt vault content and resurrect files that have been renamed or deleted in the vault.

✅ Edit vault files directly. When a task needs to modify vault content (image backfill, nav links, forward links), operate on the vault directory, not on repo copies.

📤 The only files that should go from git repo to vault are:
- 🆕 New ai-blog posts written during PRs (these don't exist in the vault yet)
- 🆕 Initial posts in new auto blog series
- 📝 Modified AGENTS.md files for blog series (these live in git)
- 🖼️ New attachment images via `syncAttachmentsDir` (uses `syncIfMissing` — never overwrites)

🔧 Backfill task (`runBackfillImages`):
- 🖼️ Image backfill operates directly on vault files via `bfcRepoRoot = vaultDir`
- 🔗 Nav link updates operate directly on vault's ai-blog directory
- 🚫 No files are copied from repo to vault

🔧 Blog series task (`runBlogSeries`):
- 📝 New posts are generated in the repo directory, then synced to vault (new file)
- 🔗 Previous post forward links are added directly in the vault directory
- 📝 AGENTS.md is synced from repo to vault (it lives in git)
- 🖼️ New attachment images are synced via `syncAttachmentsDir` (copy-if-missing)

⚠️ The `syncMarkdownDir` function was intentionally removed from the public API to prevent accidental broad directory syncs.
