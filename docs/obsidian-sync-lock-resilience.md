# Obsidian Sync Lock Resilience

## Overview

This document covers the investigation and fix for intermittent "Another sync
instance is already running" errors in the Obsidian Headless Sync integration.
The error occurred when the auto-post pipeline processed multiple items
sequentially, causing lock contention between consecutive vault sync operations.

## The Problem

When the `auto-post.ts` orchestrator discovers multiple items to post (one per
platform), it calls `main()` sequentially for each. Each `main()` call runs:

1. `syncObsidianVault()` — pull latest vault content
2. Gemini post generation + social media posting
3. `pushObsidianVault()` — push embed sections back to vault

The `ob sync` command (from `obsidian-headless`) uses a `.sync.lock` directory
inside `.obsidian/` to prevent concurrent sync operations. When post N's push
finishes and post N+1's pull starts immediately, lingering processes or lock
artifacts from the push can cause "Another sync instance is already running"
on the pull.

## Root Cause Analysis — 5 Whys (4th Investigation, 2026-03-09)

### 1. Why does "Another sync instance" occur immediately after sync-setup?

Analysis of the `obsidian-headless` source code revealed that **`sync-setup`
does NOT create locks or spawn daemons**. It only writes configuration files
(vault ID, encryption keys, etc.) to a system config directory. The lock error
comes from `ob sync`'s own `acquire()` method failing internally.

### 2. Why does `ob sync`'s own acquire() fail?

The lock class (`Ce` in the minified source) creates a `.sync.lock` directory
via `mkdirSync`, then sets its mtime via `utimesSync`, reads it back with
`statSync`, and compares (`verify()`). If the round-trip mtime doesn't match,
it throws the lock error. **Critically, the lock directory is NOT cleaned up
when `acquire()` fails** — `release()` is only in the inner try-finally, but
acquire failure is caught by the outer catch which just exits.

### 3. Why does the mtime round-trip fail?

On warm cache vaults restored from GitHub Actions cache (tar extraction),
filesystem metadata state may affect `utimesSync` → `statSync` precision.
The lock class has a 5-second staleness window: any lock with mtime < 5s old
is considered "held", blocking new syncs even from the same process.

### 4. Why do retries keep failing after removing the lock?

Each `ob sync` attempt creates a fresh lock dir, fails `verify()`, and exits
without releasing it. The retry's `ensureSyncClean` removes the lock dir, but
the next `ob sync` attempt recreates it and fails the same way — a repeating
cycle of create-fail-remove-create-fail.

### 5. What is the root fix?

Skip `sync-setup` for warm caches. The vault configuration persists in the
GitHub Actions cache, so `ob sync` can run directly without setup. This
avoids whatever interaction between `sync-setup`'s config writes and the
subsequent `ob sync` lock acquisition that triggers the verify failure.

## Lock Mechanism Details (from source analysis)

The `obsidian-headless` lock class works as follows:

```javascript
acquire() {
  mkdirSync(lockPath)               // Create .sync.lock directory
  if (EEXIST && age < 5s) throw Q   // Lock held by another process
  lockTime = Date.now()
  utimesSync(lockPath, lockTime)     // Set mtime
  // If mtime reads back as exact seconds (ms=0), filesystem lacks ms precision
  if (get() % 1000 === 0) isMs = false
  lockTime = Date.now()              // Update to current time
  utimesSync(lockPath, lockTime)     // Set mtime again
  if (lockTime !== statSync().mtime) throw Q  // verify() fails!
}

release() {                          // Only in inner try-finally
  rmdirSync(lockPath)               // Remove lock dir
}
```

**Key insight:** When `acquire()` throws Q, `release()` is never called because
it's in a different try-finally scope. The lock directory persists, causing the
"Already running" error on the next attempt.

## Timeline of Fixes

| Date | Investigation | Fix | Outcome |
|------|--------------|-----|---------|
| 2026-03-07 | 1st | Remove `.sync.lock` file before push | ❌ Process still held lock |
| 2026-03-08 | 2nd | Kill processes via `ps -o args` + `obsidian-headless` grep | ❌ Daemon not matched by pattern |
| 2026-03-09 | 3rd | Move cleanup before setup + post-push cleanup + broader detection + more retries | ❌ Still fails — wrong mental model (assumed daemons) |
| 2026-03-09 | 4th | Skip sync-setup for warm caches + remove lock after setup + diagnostics | ✅ |

## Architecture (4th Fix)

```
  Warm Cache (common CI case)          Cold Cache (first run)
  ┌─────────────────────────┐          ┌─────────────────────────┐
  │ ensureSyncClean          │          │ ensureSyncClean          │
  │ ob sync (direct!)       │ ←FAST    │ sync-setup               │
  │                         │          │ removeSyncLock            │ ←NEW
  │ If config missing:      │          │ ob sync (with retry)     │
  │   ensureSyncClean       │          └─────────────────────────┘
  │   sync-setup (fallback) │
  │   ob sync (with retry)  │
  └─────────────────────────┘
```

## Changes Made (4th Investigation)

### 1. Warm cache fast path — skip sync-setup

For warm caches (vault already configured from a previous run), `ob sync` is
called directly without `sync-setup`. This avoids the interaction that causes
lock acquisition to fail. If `ob sync` reports missing configuration, it falls
back to the full `sync-setup` → `sync` flow.

### 2. Remove lock after sync-setup

When full setup is needed (cold cache or fallback), `removeSyncLock()` is
called immediately after `sync-setup` completes. This removes any lock that
might have been indirectly created. Only the lock file is removed — processes
are not killed (since sync-setup doesn't spawn daemons).

### 3. Diagnostic logging

New `logSyncDiagnostics()` function logs:
- Lock file existence, mtime, and age
- Related running processes (ps output)

This runs on each retry, providing visibility into the lock state.

### 4. Verified lock removal

`ensureSyncClean()` now verifies the lock is actually gone after removal
and removes it again if a concurrent process recreated it.

## Previous Changes (retained)

### Post-push cleanup with settling delay

After `pushObsidianVault` completes:
1. Wait 1 second for `ob` child processes to fully exit
2. Call `ensureSyncClean` to remove any lingering lock/processes

### Broadened process detection in `killObProcesses`

Matches both:
- `obsidian-headless` — the npm package name in the script path
- The vault directory path — any process operating on our vault

### Generous retry budget

| Parameter | Value |
|-----------|-------|
| Max retries | 5 |
| Backoff delays | 2s, 4s, 8s, 16s, 32s |
| SIGTERM wait | 2s |
| SIGKILL wait | 500ms |
| Total max wait | 62s |

## Testing

Tests cover:
- `removeSyncLock` — lock removal, idempotency, missing directories
- `ensureSyncClean` — combined cleanup, verified removal, nested contents
- `killObProcesses` — graceful no-op, vault path parameter
- `runObSyncWithRetry` — export verification, parameter validation
- `logSyncDiagnostics` — lock exists, lock missing, missing .obsidian dir

All sync functions are exported for testability.

## Key Insights

### Investigation 3: Don't Kill What You Just Created

`ensureSyncClean` was placed between `sync-setup` and `sync`, which could
kill processes that `sync-setup` created. The fix was to move cleanup to
boundaries (before setup or after push).

### Investigation 4: There Are No Daemons to Kill

The 3rd investigation's mental model was wrong: `sync-setup` does **not** spawn
daemons. It only writes config files. The real issue is `ob sync`'s own lock
acquisition failing due to mtime round-trip precision issues, likely triggered
by running on a warm-cache vault extracted from a tar archive.

The simplest fix: **don't run sync-setup when it's not needed** (warm cache).

## References

- [obsidian-headless issue #4 — Stale .sync.lock](https://github.com/obsidianmd/obsidian-headless/issues/4)
- [Obsidian Headless Sync docs](https://help.obsidian.md/sync/headless)
- [obsidian-headless CLI](https://github.com/obsidianmd/obsidian-headless)
