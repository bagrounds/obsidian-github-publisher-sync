# 🔄 Daily Updates — Wiki Link Notifications in Reflections

## 🎯 Overview

📋 When files are modified by automated tasks (image backfill, internal linking, auto-posting), a wiki link to each modified file is appended to the daily reflection's `## 🔄 Updates` section.
🔁 Replaces the old "breadcrumb trail" strategy that updated `updated` frontmatter timestamps along BFS paths.
📱 Optimized for Obsidian mobile — a single glance at the reflection reveals every file touched today.
🧩 Fully idempotent — links already present are silently skipped.

## 🏗️ Architecture

### 📦 Components

| 🧩 Component | 📂 Path | 📝 Purpose |
|---|---|---|
| 📚 Library | `scripts/lib/daily-updates.ts` | 🔧 Pure functions for building and inserting update links |
| 🧪 Tests | `scripts/lib/daily-updates.test.ts` | ✅ Tests covering all pure and I/O functions |
| 🔌 Consumers | `scripts/auto-post.ts` | 📢 Adds update links after social media posting |
| 🔌 Consumers | `scripts/run-scheduled.ts` | 🖼️🔗 Adds update links after backfill-blog-images and internal-linking |

### 🔄 Data Flow

```
🖼️ backfill-blog-images / 🔗 internal-linking / 📢 auto-post
         ↓
📂 Collect list of modified file paths
         ↓
🔧 addUpdateLinksToReflection(vaultDir, date, modifiedPaths)
         ↓
📄 Read today's reflection note
         ↓
🧩 addUpdateLinks(content, links)
   ├── 📌 Create ## 🔄 Updates section if missing
   ├── ➕ Append new links (skip duplicates)
   └── 📍 Place section at end of reflection
         ↓
💾 Write updated reflection note
```

## 🆚 Old vs New Strategy

| 📏 Aspect | ❌ Breadcrumb Trail (Old) | ✅ Updates Section (New) |
|---|---|---|
| 📍 Where | `updated` timestamp in each file along BFS path | `## 🔄 Updates` section in daily reflection |
| 📱 Discoverability | Must search vault for recently-updated timestamps | One section in today's reflection |
| 🔧 Complexity | BFS traversal to propagate timestamps | Simple append of wiki links |
| 🧩 Idempotency | Timestamp comparison | Link-text deduplication |
| 📊 Scope | Touches many files across the vault | Touches only the reflection note |

## 🔗 Link Format

📝 Each update link is a wiki link with the file's title as display text:

```markdown
- [[path/to/file|File Title]]
```

📄 The title is extracted from the file's frontmatter `title` field or H1 heading.

## 📍 Section Placement

📌 The `## 🔄 Updates` section is placed at the **end** of the reflection note.
🔄 If the section already exists, new links are appended within it.
🆕 If the section does not exist, it is created at the end of the file.

## 🔧 Key Functions

### 🧊 Pure Functions (No I/O)

| 🔧 Function | 📝 Purpose |
|---|---|
| `buildUpdateLink(filePath, title)` | 🔗 Creates a `- [[path\|title]]` wiki link line |
| `addUpdateLinks(content, links)` | 📎 Inserts update links into reflection content, skipping duplicates |

### 💾 I/O Functions

| 🔧 Function | 📝 Purpose |
|---|---|
| `extractTitleFromFile(filePath)` | 📄 Reads a file and extracts its title from frontmatter or H1 |
| `addUpdateLinksToReflection(vaultDir, date, modifiedPaths)` | 🎯 Orchestrator: read reflection → build links → insert → write |

## 🛡️ Idempotency

✅ All operations are idempotent:
- 🔗 Link insertion checks whether the link target already appears in the Updates section
- 📌 Section creation only happens when `## 🔄 Updates` heading is absent
- 🔄 Re-running with the same modified paths produces no changes

## 🧪 Testing

🔬 Tests in `scripts/lib/daily-updates.test.ts` covering:
- 🔗 `buildUpdateLink`: link formatting with various paths and titles
- 📎 `addUpdateLinks`: new section creation, appending to existing section, duplicate skipping
- 📄 `extractTitleFromFile`: frontmatter title extraction, H1 fallback, missing title handling
- 🎯 `addUpdateLinksToReflection`: end-to-end orchestration with filesystem
