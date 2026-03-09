# Duplicate Post Prevention: Vault-Only Architecture

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

## Fix: Use the Vault for Everything

### Change Summary

Eliminated all stale repo reads. The entire pipeline now reads from the Obsidian vault:

- **`auto-post.ts`** pulls the vault once and passes it to BFS discovery (`find-content-to-post.ts`)
  and to the posting pipeline (`tweet-reflection.ts`).
- **`main()` in `tweet-reflection.ts`** accepts a `vaultDir` parameter. If provided (from auto-post),
  it reuses the pre-pulled vault. If not (direct invocation), it pulls fresh.
- **`find-content-to-post.ts`** now receives the vault dir instead of `content/`.
  It extracts both standard markdown links AND Obsidian wiki links.
- The GitHub repo's `content/` directory is **never read** for posting decisions.
- Dry-run mode has been removed — the pipeline always posts.

### Before (Buggy)

```
BFS reads repo (single reflection) → read repo → generate post → POST → write to vault
       ↑              ↑                                                       ↑
    Stale data   markdown links only                                    Wiki links ignored
```

### After (Fixed)

```
vault pull → BFS from ALL reflections → read note from vault → generate → POST → write + push
                  ↑                            ↑
        wiki + markdown links       Single source of truth
```

### BFS Improvements

The BFS was visiting only 1 note because:

1. **Single-reflection seed:** It started from only the most recent reflection.
   If that reflection was too recent to post (time guard) and had no resolvable
   outgoing links, the BFS terminated immediately — missing hundreds of unposted notes
   reachable from older reflections.

2. **No wiki link support:** The vault (Obsidian's native format) uses `[[path]]` wiki links.
   The Enveloppe plugin converts these to `[text](path.md)` when publishing to the repo.
   The BFS regex only matched markdown links, so it couldn't follow links in vault content.

**Fixes:**
- Seed the BFS queue with **all reflections** (sorted most recent first).
  Each reflection links to different content, so multiple entry points
  ensure thorough coverage of the content graph.
- Extract both `[text](path.md)` markdown links AND `[[path]]`, `[[path|text]]`,
  `[[path#heading]]` Obsidian wiki links.

### Performance

The vault pull is done once in `auto-post.ts` and shared with `main()` via the
`vaultDir` parameter. This avoids redundant pulls when processing multiple notes.
When `tweet-reflection.ts` is invoked directly, it pulls the vault itself.

The BFS stops as soon as one unposted note is found per platform, so seeding from
all reflections has minimal performance impact — the BFS terminates early.

## Hypotheses Considered

### Hypothesis 1: Use the vault for everything (CHOSEN)

Pull the vault once, use it for BFS discovery *and* posting decisions. The repo's
`content/` directory is never read.

**Pros:** Single source of truth everywhere. No merge logic. Vault pull is shared.
**Cons:** Vault pull adds latency before BFS discovery.

**Verdict:** Cleanest fix. Eliminates the two-source-of-truth problem entirely.

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

213 tests total (all passing):

### Vault-only reading (8 tests)
- 6 unit tests for `readNote()` with vault dir — section detection,
  arbitrary content paths, missing files, field preservation
- 1 integration test demonstrating the pre-fix bug (stale repo misses vault sections)
- 1 integration test for partial vault sections (only posted platforms detected)

### BFS discovery improvements (15 new tests)
- 8 wiki link extraction tests — path-based, display text, heading anchors,
  `.md` extension handling, filename-only, mixed formats, deduplication
- 4 `findAllReflections` tests — sorted order, empty directory, no directory, non-date files
- 3 BFS multi-reflection and wiki-link content tests — multi-reflection seeding,
  vault format discovery, posted-note link traversal

## Recommendations for Future Prevention

1. **Single source of truth:** The pipeline reads from the vault exclusively.
   This principle should be maintained for any future changes.

2. **Idempotency tokens:** Instead of relying on section header presence to detect
   prior posts, consider maintaining a separate posting log (e.g., a JSON file in the
   vault) that records which notes have been posted to which platforms.

3. **CI log analysis:** The "already exists in Obsidian note, skipping" messages in
   runs 44 and 45 were a clear signal. Consider adding alerting for this pattern —
   if we're skipping vault writes but still making social posts, something is wrong.
