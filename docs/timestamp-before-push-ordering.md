# Timestamp Before Push Ordering

## Problem

The [frontmatter path timestamp feature](frontmatter-path-timestamps.md) updates the
`updated` field in every file along the BFS path from the daily reflection to a posted
note. This creates a breadcrumb trail that Enveloppe follows when publishing from
Obsidian mobile.

However, the original implementation set these timestamps **after** `main()` had
already pushed the vault back to Obsidian:

```typescript
// ❌ BROKEN: timestamps set after push — never reach Obsidian
await main({ note: notePath, vaultDir });     // posts to social + pushes vault
updatePathTimestamps(longestPath, vaultDir);   // updates locally — too late!
```

Because `main()` pushes the vault as its final step, the timestamp updates only
existed in the local cache directory and were never synced to Obsidian. On the next
pipeline run, the vault would be re-pulled from Obsidian, overwriting the local
timestamps.

## Fix

Move `updatePathTimestamps()` **before** `main()`:

```typescript
// ✅ FIXED: timestamps set before push — included in vault push
updatePathTimestamps(longestPath, vaultDir);   // breadcrumb timestamps on disk
await main({ note: notePath, vaultDir });       // posts to social + pushes vault (with timestamps)
```

Now when `main()` pushes the vault, it includes both:
1. The new social media embed sections written to the posted note
2. The `updated` frontmatter timestamps on all intermediate files

## Why This Ordering Is Safe

**If `main()` succeeds:** Both embeds and timestamps are pushed together. ✅

**If `main()` fails (throws):** The timestamps were set locally but never pushed.
They are harmless — the next vault pull overwrites them, and the next pipeline
run will retry both the timestamps and the posting. ✅

**If no embed sections are added** (all platforms already posted): `main()` exits
early without pushing. The timestamps remain local only. This is correct — if
there's nothing new to push, there's no trail needed. ✅

## Data Flow (Corrected)

```
auto-post.ts
  ├─ Pull Obsidian vault (once)
  ├─ BFS content discovery → ContentToPost[] with pathFromRoot
  ├─ For each note to post:
  │   ├─ updatePathTimestamps(pathFromRoot, vaultDir)   ← timestamps FIRST
  │   └─ main({ note, vaultDir })                       ← posts + pushes (includes timestamps)
  └─ Done
```

## Testing

Two tests validate the ordering constraint:

1. **Source-level ordering test:** Reads `auto-post.ts` and asserts that
   `updatePathTimestamps(` appears before `await main(` in the source code.
2. **Functional test:** Sets timestamps, then reads files (simulating what the
   push would see), and asserts timestamps are present.

## Related

- [frontmatter-path-timestamps.md](frontmatter-path-timestamps.md) — Full design of the breadcrumb trail feature
- [duplicate-post-prevention.md](duplicate-post-prevention.md) — Vault-only architecture
