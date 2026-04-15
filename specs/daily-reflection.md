# 📝 Daily Reflection Auto-Update

## 🎯 Overview

📋 Automatically creates and updates daily reflection notes in the Obsidian vault when blog posts are generated.
🤖 Entirely deterministic — no AI required.
🔗 Eliminates the manual step of linking new blog posts from daily reflection notes.

## 🏗️ Architecture

### 📦 Components

| 🧩 Component | 📂 Path | 📝 Purpose |
|---|---|---|
| 📚 Library | `haskell/src/Automation/DailyReflection.hs` | 🔧 Pure functions for reflection creation and post link insertion |
| 🧪 Tests | `haskell/test/Automation/DailyReflectionTest.hs` | ✅ 40 tests covering all pure and I/O functions |
| 🔌 Integration | `haskell/app/RunScheduled.hs` | 📝 Calls reflection update after generating a post |
| ⚙️ Workflow | `.github/workflows/scheduled.yml` | 🤖 Consolidated hourly cron (runs all blog series) |

### 🔄 Data Flow

```
📝 RunScheduled.hs (blog generation)
         ↓
🤖 Generate blog post (Gemini AI)
         ↓
💾 Write post file to series dir
         ↓
📎 Write exact path to $GITHUB_OUTPUT
         ↓
🔑 Check for OBSIDIAN_AUTH_TOKEN + OBSIDIAN_VAULT_NAME
         ↓ (if available)
☁️ Sync Obsidian Vault (pull)
         ↓
📄 Ensure daily reflection exists
   ├── 🆕 Create from template if missing
   └── 🔗 Add forward link to previous day
         ↓
📎 Insert post link in reflection
   ├── 📌 Create series section if missing
   └── ➕ Append link to existing section
         ↓
☁️ Push Obsidian Vault
```

## 📐 Reflection Template

### 📄 Generated Frontmatter

```yaml
---
share: true
aliases:
  - YYYY-MM-DD
title: YYYY-MM-DD
URL: https://bagrounds.org/reflections/YYYY-MM-DD
Author: "[[bryan-grounds]]"
tags:
---
```

### 🧭 Navigation Line

```
[[index|Home]] > [[reflections/index|Reflections]] | [[reflections/PREV-DATE|⏮️]] [[reflections/NEXT-DATE|⏭️]]
```

⏮️ Back links are added when a previous reflection exists. ⏭️ Forward links are added to the previous day's reflection when a new day is created. Both work even on the first reflection (which has no back link).

### 📌 Section Heading Format

```
## [[series-id/index|icon Series Name]]
```

### 🔗 Post Link Format

```
- [[series-id/filename-without-ext|Post Title From Frontmatter]]
```

## 🔧 Key Functions

### 🧊 Pure Functions (No I/O)

| 🔧 Function | 📝 Purpose |
|---|---|
| `buildReflectionContent(date, previousDate?)` | 📄 Generates full reflection markdown from template (uses shared `formatWikilink`) |
| `buildSeriesSectionHeading(series)` | 📌 Creates `## [[series/index\|icon name]]` heading (uses shared `formatWikilink`) |
| `buildPostLink(seriesId, filenameNoExt, title)` | 🔗 Creates `- [[series/file\|title]]` link (uses shared `formatWikilink`) |
| `addForwardLink(content, targetDate)` | ⏭️ Adds forward navigation link to previous day (uses shared `formatWikilink`) |
| `insertPostLink(content, series, filename, title)` | 📎 Inserts post link, creating section if needed |

### 💾 I/O Functions

| 🔧 Function | 📝 Purpose |
|---|---|
| `findPreviousReflectionDate(dir, today)` | 🔍 Finds most recent reflection before today |
| `ensureDailyReflection(dir, today)` | 🆕 Creates reflection and links if not exists |
| `updateDailyReflection(vaultDir, today, series, file, title)` | 🎯 Main orchestrator |

## 🛡️ Idempotency

✅ All operations are idempotent:
- 📄 Reflection creation skips if file already exists
- ⏭️ Forward link addition skips if `⏭️` already present
- 🔗 Post link insertion skips if link target already in content
- 📌 Section creation only happens when section heading is absent

## 📌 Section Insertion Rules

1. ✅ If the series section heading already exists, append the link at the end of that section
2. 🆕 If the section heading does not exist, create it at the bottom of the page
3. ⬆️ New sections are always inserted BEFORE any Updates section (`## 🔄 Updates`) and social media embed sections (`## 🐦 Tweet`, `## 🦋 Bluesky`, `## 🐘 Mastodon`)
4. 🔄 Existing sections and content are never modified or reordered
5. 📐 Page ordering from top to bottom: content sections, Updates section, social media sections

## 🕐 Timezone & Future-Date Guard

🌎 All reflection dates use Pacific time via `todayPacific()`. Reflections must never be created for a date after today in Pacific time.

🛡️ The `runBackfillImages` task derives dates from ai-blog filenames (via `extractPostDate`). Because filenames may be committed with UTC dates that are ahead of Pacific time, the Haskell implementation filters out any date that exceeds today Pacific before linking to the reflection.

🤖 AI blog posts are linked using the same `insertPostLink` mechanism as blog series, creating a dedicated `## [[ai-blog/index|🤖 AI Blog]]` section rather than placing links in the Updates section.

## ⚙️ Workflow Integration

🔌 The daily reflection update is integrated directly into the blog generation task in `RunScheduled.hs` and runs automatically when Obsidian vault credentials are available as environment variables.

🔑 When `OBSIDIAN_AUTH_TOKEN` and `OBSIDIAN_VAULT_NAME` are set, the script:
1. 📥 Pulls the vault via `syncObsidianVault`
2. 📝 Calls `updateDailyReflection` with the known filename and **full display title** (including date and series icon emojis, e.g., "2026-04-14 | 📰 My Post 📰")
3. 📤 Pushes changes via `pushObsidianVault` (only if reflection was modified)

🚫 When credentials are absent (local development, dry runs), the reflection update is silently skipped.

📎 The script also writes the exact post path to `$GITHUB_OUTPUT` so downstream workflow steps reference the precise file — no glob-based filename guessing.

### ➕ Adding a New Series

🆕 To add a new blog series with automatic reflection updates:
1. 📋 Add a `BlogSeriesConfig` entry to `haskell/src/Automation/BlogSeriesConfig.hs`
2. ⚙️ Add a `BlogSeriesRunConfig` entry in `haskell/src/Automation/Scheduler.hs` and a schedule entry
3. ✅ The reflection update comes for free — no additional configuration needed

## 🧪 Testing

🔬 40 tests across 8 suites covering:
- 📄 Reflection content generation (6 tests)
- 📌 Section heading formatting (2 tests)
- 🔗 Post link formatting (2 tests)
- ⏭️ Forward link addition with idempotency (3 tests)
- 📎 Post link insertion — new sections, existing sections, embed ordering (9 tests)
- 🔍 Previous reflection date finding (6 tests)
- 🆕 Reflection creation and forward linking (6 tests)
- 🎯 Full update orchestration (6 tests)
