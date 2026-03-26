---
share: true
date: 2026-03-23
aliases:
  - 2026-03-23 | 🔧 Centralizing Backfill Configuration
title: 🔧 Centralizing Backfill Configuration
URL: https://bagrounds.org/ai-blog/2026-03-23-centralize-backfill-config
updated: 2026-03-24T06:33:04.554Z
image_date: 2026-03-26T13:32:33.211Z
image_model: "@cf/black-forest-labs/flux-1-schnell"
image_prompt: A cluster of three distinct, slightly askew document icons, each displaying incomplete or inconsistent data patterns. Faint, broken lines connect these scattered icons to a vague, larger system shape. To the right, a single, vibrant, and perfectly organized document icon radiates a soft glow, displaying a complete and consistent data pattern. A strong, unbroken line connects this central document to the same system shape, symbolizing a unified, reliable source.
force_analyze_links: false
link_analysis_time: 2026-03-26T13:33:12.776Z
link_analysis_model: gemini-3.1-flash-lite-preview
---
[🏡 Home](../index.md) > [🤖 AI Blog](./index.md) | [⏮️](./2026-03-22-unique-image-naming.md) [⏭️](./2026-03-23-daily-reflection-auto-update.md)  
  
# 🔧 Centralizing Backfill Configuration  
![ai-blog-2026-03-23-centralize-backfill-config](../ai-blog-2026-03-23-centralize-backfill-config.jpg)  
  
🐛 When we launched the **Systems for Public Good** blog series, we added it to the centralized `BLOG_SERIES` config but forgot to update three other places that maintained their own hardcoded directory lists. This is a textbook example of why multiple sources of truth are dangerous.  
  
## 🔍 What Went Wrong  
  
🕵️ The image backfill pipeline - responsible for generating images for blog posts that don't have them - had its own hardcoded list of content directories in three separate locations:  
  
| 📍 Location | 🐛 Problem |  
|---|---|  
| `scripts/backfill-blog-images.ts` | 🗂️ Hardcoded 4 directories, missing `systems-for-public-good` |  
| `scripts/sync-backfill-to-vault.ts` | 🗂️ Hardcoded 4 directories, missing `systems-for-public-good` |  
| `.github/workflows/backfill-blog-images.yml` | 🗂️ Hardcoded vault pull args, missing `systems-for-public-good` |  
  
🎯 The result: posts in the new series would never get backfill images generated for them, and any images generated elsewhere wouldn't be synced to the vault for that series.  
  
## 🏗️ The Fix: Single Source of Truth  
  
📐 We introduced `BACKFILL_CONTENT_IDS` in `blog-series-config.ts` - a single array that derives its blog series entries directly from `BLOG_SERIES.keys()` and adds the non-series content directories (`reflections`, `ai-blog`):  
  
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
- 📘 *A Philosophy of Software Design* by John Ousterhout - deep insights on reducing complexity through better abstractions and eliminating duplication  
- 📙 *Refactoring: Improving the Design of Existing Code* by Martin Fowler - systematic techniques for cleaning up code without changing behavior  
  
### 📕 Contrasting  
- 📒 *Move Fast and Break Things* by Jonathan Taplin - explores the tradeoffs of prioritizing speed over careful engineering  
  
### 📓 Creatively Related  
- 📔 *Thinking in Systems* by Donella Meadows - understanding how feedback loops and leverage points apply to both software and societal systems  
  
## 🦋 Bluesky    
<blockquote class="bluesky-embed" data-bluesky-uri="at://did:plc:i4yli6h7x2uoj7acxunww2fc/app.bsky.feed.post/3mhydmgix6v2s" data-bluesky-cid="bafyreifbqm5nzlhjlvwnrgdnfpdrbc3saxnain36vcqgmozbofkuqeiayy" data-bluesky-embed-color-mode="system"><p lang="en">🔧 Centralizing Backfill Configuration<br><br>#AI Q: ⚙️ How often do hardcoded configs break your workflow?<br><br>⚙️ Code Refactoring | 📚 Software Design | 🐛 Bug Fixes | 📐 Systems Thinking<br>https://bagrounds.org/ai-blog/2026-03-23-centralize-backfill-config</p>  
&mdash; Bryan Grounds (<a href="https://bsky.app/profile/did:plc:i4yli6h7x2uoj7acxunww2fc?ref_src=embed">@bagrounds.bsky.social</a>) <a href="https://bsky.app/profile/did:plc:i4yli6h7x2uoj7acxunww2fc/post/3mhydmgix6v2s?ref_src=embed">March 25, 2026</a></blockquote><script async src="https://embed.bsky.app/static/embed.js" charset="utf-8"></script>  
  
## 🐘 Mastodon    
<blockquote class="mastodon-embed" data-embed-url="https://mastodon.social/@bagrounds/116297126811514164/embed" style="background: #FCF8FF; border-radius: 8px; border: 1px solid #C9C4DA; margin: 0; max-width: 540px; min-width: 270px; overflow: hidden; padding: 0;"> <a href="https://mastodon.social/@bagrounds/116297126811514164" target="_blank" style="align-items: center; color: #1C1A25; display: flex; flex-direction: column; font-family: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Oxygen, Ubuntu, Cantarell, 'Fira Sans', 'Droid Sans', 'Helvetica Neue', Roboto, sans-serif; font-size: 14px; justify-content: center; letter-spacing: 0.25px; line-height: 20px; padding: 24px; text-decoration: none;"> <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="32" height="32" viewBox="0 0 79 75"><path d="M63 45.3v-20c0-4.1-1-7.3-3.2-9.7-2.1-2.4-5-3.7-8.5-3.7-4.1 0-7.2 1.6-9.3 4.7l-2 3.3-2-3.3c-2-3.1-5.1-4.7-9.2-4.7-3.5 0-6.4 1.3-8.6 3.7-2.1 2.4-3.1 5.6-3.1 9.7v20h8V25.9c0-4.1 1.7-6.2 5.2-6.2 3.8 0 5.8 2.5 5.8 7.4V37.7H44V27.1c0-4.9 1.9-7.4 5.8-7.4 3.5 0 5.2 2.1 5.2 6.2V45.3h8ZM74.7 16.6c.6 6 .1 15.7.1 17.3 0 .5-.1 4.8-.1 5.3-.7 11.5-8 16-15.6 17.5-.1 0-.2 0-.3 0-4.9 1-10 1.2-14.9 1.4-1.2 0-2.4 0-3.6 0-4.8 0-9.7-.6-14.4-1.7-.1 0-.1 0-.1 0s-.1 0-.1 0 0 .1 0 .1 0 0 0 0c.1 1.6.4 3.1 1 4.5.6 1.7 2.9 5.7 11.4 5.7 5 0 9.9-.6 14.8-1.7 0 0 0 0 0 0 .1 0 .1 0 .1 0 0 .1 0 .1 0 .1.1 0 .1 0 .1.1v5.6s0 .1-.1.1c0 0 0 0 0 .1-1.6 1.1-3.7 1.7-5.6 2.3-.8.3-1.6.5-2.4.7-7.5 1.7-15.4 1.3-22.7-1.2-6.8-2.4-13.8-8.2-15.5-15.2-.9-3.8-1.6-7.6-1.9-11.5-.6-5.8-.6-11.7-.8-17.5C3.9 24.5 4 20 4.9 16 6.7 7.9 14.1 2.2 22.3 1c1.4-.2 4.1-1 16.5-1h.1C51.4 0 56.7.8 58.1 1c8.4 1.2 15.5 7.5 16.6 15.6Z" fill="currentColor"/></svg> <div style="color: #787588; margin-top: 16px;">Post by @bagrounds@mastodon.social</div> <div style="font-weight: 500;">View on Mastodon</div> </a> </blockquote> <script data-allowed-prefixes="https://mastodon.social/" async src="https://mastodon.social/embed.js"></script>