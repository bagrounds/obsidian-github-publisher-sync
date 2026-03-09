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

## Root Cause Analysis — 5 Whys (3rd Investigation)

### 1. Why does the error still occur intermittently despite the 2nd fix?

When auto-post processes multiple posts, each `main()` call runs
`sync-setup` → `sync` (pull) → post → `sync` (push). The push from
post N may leave a daemon/lock, and post N+1 starts immediately.

### 2. Why doesn't `ensureSyncClean` between sync-setup and sync help?

Because it was placed **AFTER** `sync-setup`, which spawns a daemon that
`sync` needs. Killing that daemon (or disturbing its lock state) between
setup and sync creates the very error we're trying to prevent.

### 3. Why is it intermittent (works sometimes, fails other times)?

Race condition: timing determines whether the daemon has fully started
when cleanup runs. Under CI load, timing varies per run.

### 4. Why didn't broader process detection solve it in the 2nd fix?

The daemon may use a process name that doesn't match `obsidian-headless`
(e.g., `MainThread`, bare `node`, or a detached worker). `killObProcesses`
found ZERO processes in every retry iteration shown in CI logs.

### 5. What is the root fix?

A multi-pronged approach:
- **(a)** Move cleanup to **BEFORE** sync-setup (not after) so the daemon
  sync-setup creates is preserved for sync to use.
- **(b)** Add post-push cleanup with settling delay so the next pipeline
  iteration starts with clean vault state.
- **(c)** Broaden process detection to also match vault paths.
- **(d)** Increase retry budget (5 retries, 2–32s backoff) for resilience.

## Timeline of Fixes

| Date | Fix | Outcome |
|------|-----|---------|
| 2026-03-07 | Initial: Remove `.sync.lock` file before push | ❌ Process still held lock |
| 2026-03-08 | 2nd: Kill processes via `ps -o args` + `obsidian-headless` grep | ❌ Daemon not matched by pattern |
| 2026-03-09 | 3rd: Move cleanup before setup + post-push cleanup + broader detection + more retries | ✅ |

## Architecture

```
  Post N                                Post N+1
  ┌──────────────┐                      ┌──────────────┐
  │ sync-setup   │                      │ensureSyncClean│ ← NEW: pre-setup cleanup
  │ ensureClean  │ ← OLD position       │ sync-setup   │
  │ sync (pull)  │  (killed setup's     │ sync (pull)  │
  │ [generate]   │   daemon!)           │ [generate]   │
  │ [post]       │                      │ [post]       │
  │ sync (push)  │                      │ sync (push)  │
  │ [1s settle]  │ ← NEW               │ [1s settle]  │
  │ ensureClean  │ ← NEW: post-push    │ ensureClean  │
  └──────────────┘                      └──────────────┘
```

## Changes Made

### 1. Moved `ensureSyncClean` to before `sync-setup`

**Before:**
```
sync-setup → ensureSyncClean → sync
```

**After:**
```
ensureSyncClean → sync-setup → sync
```

This ensures stale state from the previous push is cleaned up before
`sync-setup` creates a fresh daemon. The daemon sync-setup creates is
preserved for `sync` to use.

### 2. Added post-push cleanup with settling delay

After `pushObsidianVault` completes, we now:
1. Wait 1 second for `ob` child processes to fully exit
2. Call `ensureSyncClean` to remove any lingering lock/processes

This ensures the next pipeline iteration starts with a clean slate.

### 3. Broadened process detection in `killObProcesses`

Now matches both:
- `obsidian-headless` — the npm package name in the script path
- The vault directory path — any process operating on our vault

The vault path matching catches daemon children that may use
unexpected process names (e.g., `node`, `MainThread`).

### 4. Increased retry budget

| Parameter | Before | After |
|-----------|--------|-------|
| Max retries | 3 | 5 |
| Backoff delays | 1s, 2s, 4s | 2s, 4s, 8s, 16s, 32s |
| SIGTERM wait | 1s | 2s |
| SIGKILL wait | 200ms | 500ms |
| Total max wait | 7s | 62s |

The generous retry budget accounts for the intermittent nature of the
lock contention and variable CI environment timing.

## Testing

Nine new unit tests were added covering:
- `removeSyncLock` — lock removal, idempotency, missing directories
- `ensureSyncClean` — combined cleanup, no-op when clean
- `killObProcesses` — graceful no-op, vault path parameter
- `runObSyncWithRetry` — export verification, parameter validation

All functions are now exported for testability.

## Key Insight: Don't Kill What You Just Created

The most important lesson: `ensureSyncClean` was placed between `sync-setup`
and `sync`, which means it could kill the very daemon that `sync-setup` had
just created. This is a classic race condition where cleanup code interferes
with initialization code. The fix is to move cleanup to a boundary between
operations (before setup or after push), not in the middle of a setup-sync
pair.

## References

- [obsidian-headless issue #4 — Stale .sync.lock](https://github.com/obsidianmd/obsidian-headless/issues/4)
- [Obsidian Headless Sync docs](https://help.obsidian.md/sync/headless)
- [obsidian-headless CLI](https://github.com/obsidianmd/obsidian-headless)
