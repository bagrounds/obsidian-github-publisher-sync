# Duplicate Post Prevention: Vault-Repo Divergence Fix

## Problem

The social media auto-posting pipeline posted **duplicate content** across 3 consecutive
scheduled runs (runs 43, 44, 45 on 2026-03-09). The same note
(`ai-blog/2026-03-09-platform-disable-env-vars.md`) was posted to Bluesky and Mastodon
three times, creating duplicate posts on both platforms.

The pipeline *did* correctly detect and skip the duplicate when writing embed sections to
the Obsidian vault (the `## 🦋 Bluesky already exists in Obsidian note, skipping` message
appeared in CI logs). But it detected too late — after the social media posts were already made.

## Root Cause Analysis (5 Whys)

1. **Why were there duplicate posts?**
   → The same content was discovered as "needing posting" on every scheduled run.

2. **Why was the same content re-discovered?**
   → `detectPostedPlatforms()` in `find-content-to-post.ts` and `readNote()` in
   `tweet-reflection.ts` check for social media section headers (`## 🐦 Tweet`,
   `## 🦋 Bluesky`, `## 🐘 Mastodon`) in the note content. Neither found them.

3. **Why didn't the note content have the section headers?**
   → Both functions read from the GitHub repo's `content/` directory, which hadn't been
   updated. The embed sections were only written to the **Obsidian vault** (a separate
   directory synced via `ob`), not the GitHub repo.

4. **Why wasn't the GitHub repo updated?**
   → The pipeline writes embed sections to the Obsidian vault, then syncs the vault back
   to Obsidian's cloud. The user must then manually publish from Obsidian to GitHub via
   the Enveloppe plugin. Between runs, the GitHub repo content stays stale.

5. **Why wasn't the vault checked before posting?**
   → The vault pull was started in the background (for performance) but only awaited
   **after** social posting. The "already posted" check happened before the vault was
   available, using the stale GitHub repo content as the source of truth.

## Two Sources of Truth

The pipeline had two copies of each note, and they could diverge:

| Source | Updated When | Used For |
|--------|-------------|----------|
| GitHub repo (`content/`) | User publishes from Obsidian (manual) | BFS discovery + posting decision |
| Obsidian vault (via `ob sync`) | After each pipeline run (automatic) | Writing embed sections |

The **vault** was the authoritative source, but the **repo** was used for the critical
"should we post?" decision.

## Timeline

```
Run 43 (12:11 UTC) — FIRST POST
├─ BFS reads content/ (GitHub repo) → no sections found
├─ Posts to Bluesky + Mastodon ✅
├─ Writes sections to Obsidian vault ✅
└─ Vault now has sections; GitHub repo does NOT

Run 44 (14:20 UTC) — DUPLICATE
├─ BFS reads content/ (GitHub repo) → STILL no sections (stale)
├─ Posts to Bluesky + Mastodon AGAIN ❌ (duplicate!)
├─ Attempts vault write → "already exists, skipping"
└─ Vault already had sections from run 43

Run 45 (16:21 UTC) — DUPLICATE
├─ BFS reads content/ (GitHub repo) → STILL no sections (stale)
├─ Posts to Bluesky + Mastodon AGAIN ❌ (duplicate!)
├─ Attempts vault write → "already exists, skipping"
└─ Vault already had sections from run 43
```

## Fix: Read from the Vault, Not the Repo

### Change Summary

Eliminated the stale repo read entirely. `main()` now reads note content exclusively
from the Obsidian vault (the single source of truth). The GitHub repo's `content/`
directory is no longer used for posting decisions.

### Before (Buggy)

```
read note from repo → generate post → POST → await vault pull → write to vault
                                        ↑
                               Uses stale repo data
```

### After (Fixed)

```
await vault pull → read note from vault → generate post → POST → write to vault + push
                            ↑
                   Single source of truth
```

### Code Change

In `main()`, the vault is now pulled first, and the note is read directly from it:

```typescript
// Step 2: Pull the Obsidian vault — the single source of truth.
vaultDir = await timer.time("obsidian-pull", () =>
  syncObsidianVault(env.obsidian),
);

// Step 3: Read the note from the vault (authoritative source)
reflection = readNote(obsidianNotePath, vaultDir);

// Idempotency check uses vault data — no merge needed
if (reflection.hasTweetSection && reflection.hasBlueskySection && reflection.hasMastodonSection) {
  console.log(`ℹ️  Note already has all social platform sections, skipping`);
  return;
}
```

The `mergeVaultSectionFlags()` function was removed — it's unnecessary when there's
only one source of truth. Dry runs fall back to reading from the repo since the vault
pull is skipped.

### Performance Impact

The vault pull now runs sequentially before Gemini generation (previously it ran in
parallel). With a warm cache (incremental sync), this adds negligible latency. With
a cold cache (~7 min), this increases wall-clock time slightly — but correctness is
more important than speed, and the vault pull was already the pipeline bottleneck.

## Hypotheses Considered

### Hypothesis 1: Read from Obsidian vault instead of GitHub repo (CHOSEN)

Read note content exclusively from the Obsidian vault — the single source of truth.
Pull the vault before any posting decisions.

**Pros:** Single source of truth. No merge logic needed. Simplest conceptual model.
**Cons:** Vault pull adds latency before Gemini generation (can't parallelize).

**Verdict:** Cleanest fix. Eliminates the two-source-of-truth problem entirely.
Correctness is more important than speed.

### Hypothesis 2: Commit embed sections to the GitHub repo after posting

After writing embed sections to the Obsidian vault, also commit them to the
GitHub repo via `git commit && git push`.

**Pros:** Both sources stay in sync.
**Cons:** Requires git credentials in the workflow; may cause merge conflicts
with user commits; changes the publication flow.

**Verdict:** Viable but introduces new complexity and changes the workflow
semantics (the pipeline would modify the repo it runs from).

### Hypothesis 3: Merge repo and vault flags before posting

Await the vault pull before posting, read the vault note, and OR-merge
section flags from both sources before making posting decisions.

**Pros:** Minimal code change; uses existing vault pull; OR-merge is safe.
**Cons:** Still reads from two sources; more complex than necessary; leaves
stale repo reads in the pipeline.

**Verdict:** Works but unnecessarily complex. If the vault is the source of
truth, just read from it directly.

## Testing

8 new tests added:

- 6 unit tests for vault-only reading via `readNote()` — section detection,
  arbitrary content paths, missing files, field preservation
- 1 integration test demonstrating the pre-fix bug (stale repo misses vault sections)
- 1 integration test for partial vault sections (only posted platforms detected)

All 198 tests pass (190 existing + 8 new).

## Recommendations for Future Prevention

1. **Single source of truth:** The pipeline now reads from the vault exclusively for
   posting decisions. This principle should be maintained for any future changes.

2. **Idempotency tokens:** Instead of relying on section header presence to detect
   prior posts, consider maintaining a separate posting log (e.g., a JSON file in the
   vault) that records which notes have been posted to which platforms.

3. **Integration tests with time progression:** Create tests that simulate multiple
   pipeline runs with divergent sources, to catch "stale read" bugs before they reach
   production.

4. **CI log analysis:** The "already exists in Obsidian note, skipping" messages in
   runs 44 and 45 were a clear signal. Consider adding alerting for this pattern —
   if we're skipping vault writes but still making social posts, something is wrong.
