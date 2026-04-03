---
share: true
date: 2026-03-23
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]

## 🔧 Centralizing Backfill Configuration

🐛 When we launched the **Systems for Public Good** blog series, we added it to the centralized `BLOG_SERIES` config but forgot to update three other places that maintained their own hardcoded directory lists. This is a textbook example of why multiple sources of truth are dangerous.

## 🔍 What Went Wrong

🕵️ The image backfill pipeline — responsible for generating images for blog posts that don't have them — had its own hardcoded list of content directories in three separate locations:

| 📍 Location | 🐛 Problem |
|---|---|
| `scripts/backfill-blog-images.ts` | 🗂️ Hardcoded 4 directories, missing `systems-for-public-good` |
| `scripts/sync-backfill-to-vault.ts` | 🗂️ Hardcoded 4 directories, missing `systems-for-public-good` |
| `.github/workflows/backfill-blog-images.yml` | 🗂️ Hardcoded vault pull args, missing `systems-for-public-good` |

🎯 The result: posts in the new series would never get backfill images generated for them, and any images generated elsewhere wouldn't be synced to the vault for that series.

## 🏗️ The Fix: Single Source of Truth

📐 We introduced `BACKFILL_CONTENT_IDS` in `blog-series-config.ts` — a single array that derives its blog series entries directly from `BLOG_SERIES.keys()` and adds the non-series content directories (`reflections`, `ai-blog`):

```typescript
const EXTRA_CONTENT_DIRS: readonly string[] = ["reflections", "ai-blog"];

export const BACKFILL_CONTENT_IDS: readonly string[] = [
  ...EXTRA_CONTENT_DIRS,
  ...[...BLOG_SERIES.keys()],
];
```

🛡️ Now when a new blog series is added to `BLOG_SERIES`, it automatically appears in the backfill pipeline with zero additional changes required.

## 📋 All Changes

| 📄 File | ✏️ Change |
|---|---|
| `scripts/lib/blog-series-config.ts` | ➕ Added `BACKFILL_CONTENT_IDS` derived from `BLOG_SERIES` |
| `scripts/backfill-blog-images.ts` | 🔄 Replaced hardcoded directory list with `BACKFILL_CONTENT_IDS` |
| `scripts/sync-backfill-to-vault.ts` | 🔄 Replaced hardcoded directory list with `BACKFILL_CONTENT_IDS` |
| `scripts/pull-vault-posts.ts` | ➕ Added `--all` flag that expands to `BACKFILL_CONTENT_IDS` |
| `.github/workflows/backfill-blog-images.yml` | 🔄 Changed vault pull to use `--all` flag |
| `scripts/lib/blog-image.ts` | 🧹 Deduplicated `todayPacific()` (re-export from canonical source) |
| `scripts/lib/blog-series.test.ts` | 🧪 Added completeness tests for `BACKFILL_CONTENT_IDS` |

## 🧹 Bonus Cleanup

🔁 We also found and fixed `todayPacific()` being defined identically in both `blog-image.ts` and `blog-prompt.ts`. The canonical definition now lives only in `blog-prompt.ts`, and `blog-image.ts` re-exports it.

🗑️ Removed an unused `fs` import from `sync-backfill-to-vault.ts`.

## 🧠 Lesson Learned

📏 Every hardcoded list is a future bug waiting to happen. When a value appears in more than one place, one of them will inevitably fall out of sync. The fix is always the same: derive from a single source of truth.

## 📚 Book Recommendations

### 📗 Similar
- 📘 *A Philosophy of Software Design* by John Ousterhout — deep insights on reducing complexity through better abstractions and eliminating duplication
- 📙 *Refactoring: Improving the Design of Existing Code* by Martin Fowler — systematic techniques for cleaning up code without changing behavior

### 📕 Contrasting
- 📒 *Move Fast and Break Things* by Jonathan Taplin — explores the tradeoffs of prioritizing speed over careful engineering

### 📓 Creatively Related
- 📔 *Thinking in Systems* by Donella Meadows — understanding how feedback loops and leverage points apply to both software and societal systems
