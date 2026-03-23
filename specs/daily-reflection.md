# 📝 Daily Reflection Auto-Update

## 🎯 Overview

📋 Automatically creates and updates daily reflection notes in the Obsidian vault when blog posts are generated.
🤖 Entirely deterministic — no AI required.
🔗 Eliminates the manual step of linking new blog posts from daily reflection notes.

## 🏗️ Architecture

### 📦 Components

| 🧩 Component | 📂 Path | 📝 Purpose |
|---|---|---|
| 📚 Library | `scripts/lib/daily-reflection.ts` | 🔧 Pure functions for reflection creation and post link insertion |
| 🧪 Tests | `scripts/lib/daily-reflection.test.ts` | ✅ 40 tests covering all pure and I/O functions |
| 🖥️ CLI | `scripts/update-daily-reflection.ts` | 🚀 Entry point for workflow integration |
| ⚙️ Workflow | `.github/workflows/auto-blog-zero.yml` | 🤖 Auto Blog Zero daily post workflow |
| ⚙️ Workflow | `.github/workflows/chickie-loo.yml` | 🐔 Chickie Loo daily post workflow |

### 🔄 Data Flow

```
📝 Blog Post Generated
        ↓
🖥️ update-daily-reflection.ts CLI
        ↓
📖 Read post title from frontmatter
        ↓
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
[[index|Home]] > [[reflections/index|Reflections]] | [[reflections/PREV-DATE|⏮️]]
```

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
| `buildReflectionContent(date, previousDate?)` | 📄 Generates full reflection markdown from template |
| `buildSeriesSectionHeading(series)` | 📌 Creates `## [[series/index\|icon name]]` heading |
| `buildPostLink(seriesId, filenameNoExt, title)` | 🔗 Creates `- [[series/file\|title]]` link |
| `addForwardLink(content, targetDate)` | ⏭️ Adds forward navigation link to previous day |
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
3. ⬆️ New sections are always inserted BEFORE any social media embed sections (`## 🐦 Tweet`, `## 🦋 Bluesky`, `## 🐘 Mastodon`)
4. 🔄 Existing sections and content are never modified or reordered

## ⚙️ Workflow Integration

🔌 Added as a step in both `auto-blog-zero.yml` and `chickie-loo.yml` workflows, after the "Sync Posts to Obsidian Vault" step and before the "Sync Image to Obsidian Vault" step.

```yaml
- name: Update Daily Reflection
  env:
    OBSIDIAN_AUTH_TOKEN: ${{ secrets.OBSIDIAN_AUTH_TOKEN }}
    OBSIDIAN_VAULT_NAME: ${{ secrets.OBSIDIAN_VAULT_NAME }}
    OBSIDIAN_VAULT_CACHE_DIR: /tmp/obsidian-vault-cache
  run: |
    SERIES="<series-id>"
    POST=$(ls -1 ${SERIES}/$(date +%Y-%m-%d)*.md 2>/dev/null | head -1)
    if [ -n "$POST" ]; then
      npx tsx scripts/update-daily-reflection.ts --series ${SERIES} --post "$POST"
    fi
```

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
