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

## Fix: Check the Vault Before Posting

### Change Summary

Moved the vault pull await from **after posting** to **before posting**. After the vault
pull completes, re-read the note from the vault and merge section flags with the repo data
using OR logic. If EITHER source has a section, treat it as already posted.

### Before (Buggy)

```
read note from repo → generate post → POST → await vault pull → write to vault
                                        ↑
                               Uses stale repo data
```

### After (Fixed)

```
read note from repo → generate post → await vault pull → RE-CHECK vault → POST → write to vault
                                                           ↑
                                                  Uses authoritative vault data
```

### Code Change

Extracted `mergeVaultSectionFlags()` for clean testability:

```typescript
export function mergeVaultSectionFlags(
  reflection: ReflectionData,
  vaultContent: string,
): ReflectionData {
  return {
    ...reflection,
    hasTweetSection: reflection.hasTweetSection || vaultContent.includes(TWEET_SECTION_HEADER),
    hasBlueskySection: reflection.hasBlueskySection || vaultContent.includes(BLUESKY_SECTION_HEADER),
    hasMastodonSection: reflection.hasMastodonSection || vaultContent.includes(MASTODON_SECTION_HEADER),
  };
}
```

In `main()`, the vault pull is now awaited before posting:

```typescript
// Step 5: Await vault pull and re-check for existing sections
if (vaultPullPromise) {
  vaultDir = await vaultPullPromise;
  const vaultContent = fs.readFileSync(vaultFilePath, "utf-8");
  reflection = mergeVaultSectionFlags(reflection, vaultContent);

  if (reflection.hasTweetSection && reflection.hasBlueskySection && reflection.hasMastodonSection) {
    console.log(`ℹ️  Vault already has all social platform sections, skipping posting`);
    return;
  }
}

// Step 6: Post to social platforms (now uses merged flags)
```

### Performance Impact

The vault pull is still started in the background during Gemini generation (step 4).
The only change is that we now await it before posting instead of after. With a warm
cache (incremental sync), this adds negligible latency. With a cold cache (~7 min),
posting waits for the pull — but correctness is more important than speed.

## Hypotheses Considered

### Hypothesis 1: Read from Obsidian vault instead of GitHub repo for BFS discovery

Move the vault pull to before BFS discovery and read content from the vault instead
of the GitHub repo.

**Pros:** Single source of truth for all decisions.
**Cons:** Adds vault pull latency before discovery; complex restructuring of the
pipeline; BFS currently runs in `auto-post.ts` before `main()` is called.

**Verdict:** Too invasive. The vault pull happens inside `main()`, so moving it
before BFS would require restructuring the entire pipeline.

### Hypothesis 2: Commit embed sections to the GitHub repo after posting

After writing embed sections to the Obsidian vault, also commit them to the
GitHub repo via `git commit && git push`.

**Pros:** Both sources stay in sync.
**Cons:** Requires git credentials in the workflow; may cause merge conflicts
with user commits; changes the publication flow.

**Verdict:** Viable but introduces new complexity and changes the workflow
semantics (the pipeline would modify the repo it runs from).

### Hypothesis 3: Check the vault before posting (CHOSEN)

Await the vault pull before posting, re-read the note from the vault, and merge
section flags before making posting decisions.

**Pros:** Minimal change; uses the existing vault pull; OR-merge is safe
(never loses information); extracted function is testable.
**Cons:** Minor performance trade-off (await before posting instead of after).

**Verdict:** Cleanest fix. Smallest change surface. Correctness preserved.

## Testing

11 new tests added:

- 8 unit tests for `mergeVaultSectionFlags()` — all combinations of repo/vault flags
- 3 integration tests for the vault-repo divergence scenario:
  - Demonstrates the pre-fix bug (readNote from repo misses vault sections)
  - Demonstrates the fix (mergeVaultSectionFlags detects vault sections)
  - Partial vault sections (only posted platforms are detected)

All 201 tests pass (190 existing + 11 new).

## Recommendations for Future Prevention

1. **Single source of truth:** The pipeline should ideally use one authoritative copy
   of each note. Consider reading from the vault throughout the pipeline, not just for
   the write step.

2. **Idempotency tokens:** Instead of relying on section header presence to detect
   prior posts, consider maintaining a separate posting log (e.g., a JSON file in the
   vault) that records which notes have been posted to which platforms.

3. **Pre-posting validation:** Before posting to any platform, check the vault content
   as a final gate. This is what the fix implements — but it should be a documented
   invariant, not just an implementation detail.

4. **Integration tests with time progression:** Create tests that simulate multiple
   pipeline runs with divergent sources, to catch "stale read" bugs before they reach
   production.

5. **CI log analysis:** The "already exists in Obsidian note, skipping" messages in
   runs 44 and 45 were a clear signal. Consider adding alerting for this pattern —
   if we're skipping vault writes but still making social posts, something is wrong.
