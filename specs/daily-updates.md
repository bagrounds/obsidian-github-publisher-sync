# 🔄 Daily Updates — Wiki Link Notifications in Reflections

## 🎯 Overview

📋 When files are modified by automated tasks (image backfill, internal linking, auto-posting), a wiki link to each modified file is appended to the daily reflection's `## 🔄 Updates` section.
🔁 Replaces the old "breadcrumb trail" strategy that updated `updated` frontmatter timestamps along BFS paths.
📱 Optimized for Obsidian mobile — a single glance at the reflection reveals every file touched today.
🧩 Fully idempotent — links already present are silently skipped.
📂 Updates are organized into sub-sections by category so you can tell at a glance what kind of changes were made.

## 🏗️ Architecture

### 📦 Components

| 🧩 Component | 📂 Path | 📝 Purpose |
|---|---|---|
| 📚 Library (TS) | `scripts/lib/daily-updates.ts` | 🔧 Pure functions for building and inserting update links |
| 📚 Library (HS) | `haskell/src/Automation/DailyUpdates.hs` | 🔧 Haskell implementation with categorized sub-sections |
| 🧪 Tests (TS) | `scripts/lib/daily-updates.test.ts` | ✅ Tests covering all pure and I/O functions |
| 🧪 Tests (HS) | `haskell/test/Automation/DailyUpdatesTest.hs` | ✅ Haskell tests covering categorized update links |
| 🔌 Consumers | `haskell/src/Automation/SocialPosting.hs` | 📢 Adds update links to specific posted pages after social media posting |
| 🔌 Consumers | `haskell/app/RunScheduled.hs` | 🖼️🔗 Adds update links after backfill-blog-images and internal-linking |

### 🔄 Data Flow

```
🖼️ backfill-blog-images / 🔗 internal-linking / 📢 auto-post
         ↓
📂 Collect list of modified file paths + determine UpdateCategory
         ↓
🔧 addUpdateLinksToReflection(vaultDir, date, category, modifiedPaths)
         ↓
📄 Ensure daily reflection exists (create from template if missing)
         ↓
📄 Read today's reflection note
         ↓
🧩 addUpdateLinks(content, category, links)
   ├── 📌 Create ## 🔄 Updates section if missing
   ├── 📂 Create category sub-section (### header) if missing
   ├── ➕ Append new links under category sub-section (skip duplicates)
   └── 📍 Place section at end of reflection
         ↓
💾 Write updated reflection note
```

## 📂 Update Categories

🏷️ Each update link is associated with a category that determines which sub-section it appears under:

| 🏷️ Category | 📝 Sub-header | 📋 Used By |
|---|---|---|
| `ImageUpdate` | `### 🖼️ Images` | backfill-blog-images |
| `InternalLinkUpdate` | `### 🔗 Internal Links` | internal-linking / nav link changes |
| `SocialPostUpdate` | `### 📢 Social Posts` | social media posting |
| `OtherUpdate name` | `### <name>` | any future automation |

📄 Example reflection with categorized updates:

```markdown
## 🔄 Updates

### 🖼️ Images

- [[ai-blog/2026-03-28-my-post|my-post]]

### 📢 Social Posts

- [[ai-blog/2026-03-27-cool-post|Cool Post]]
- [[books/some-book|Some Book]]
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
📢 Social posting links use the specific page title from the `ContentNote` rather than a generic label.

## 📍 Section Placement

📌 The `## 🔄 Updates` section is placed at the **end** of the reflection note.
📂 Within the updates section, each category gets its own `###` sub-heading.
🔄 If the section or sub-section already exists, new links are appended within it.
🆕 If the section does not exist, it is created at the end of the file with the first sub-section.
🆕 If a sub-section does not exist, it is appended at the end of the updates section.

## 🔧 Key Functions

### 🧊 Pure Functions (No I/O)

| 🔧 Function | 📝 Purpose |
|---|---|
| `buildUpdateLink(filePath, title)` | 🔗 Creates a `- [[path\|title]]` wiki link line |
| `addUpdateLinks(content, category, links)` | 📎 Inserts categorized update links into reflection content, skipping duplicates |
| `categorySubHeader(category)` | 📂 Returns the sub-heading text for a given `UpdateCategory` |

### 💾 I/O Functions

| 🔧 Function | 📝 Purpose |
|---|---|
| `extractTitleFromFile(filePath)` | 📄 Reads a file and extracts its title from frontmatter or H1 |
| `addUpdateLinksToReflection(vaultDir, date, category, modifiedPaths)` | 🎯 Orchestrator: ensure reflection exists → build links → insert → write |

## 🛡️ Idempotency

✅ All operations are idempotent:
- 🔗 Link insertion checks whether the link target already appears in the Updates section
- 📌 Section and sub-section creation only happens when the heading is absent
- 🔄 Re-running with the same modified paths produces no changes

## 🧪 Testing

🔬 TypeScript tests in `scripts/lib/daily-updates.test.ts` covering:
- 🔗 `buildUpdateLink`: link formatting with various paths and titles
- 📎 `addUpdateLinks`: new section creation, appending to existing section, duplicate skipping
- 📄 `extractTitleFromFile`: frontmatter title extraction, H1 fallback, missing title handling
- 🎯 `addUpdateLinksToReflection`: end-to-end orchestration with filesystem

🔬 Haskell tests in `haskell/test/Automation/DailyUpdatesTest.hs` covering:
- 📂 `categorySubHeader`: correct emoji sub-headings for each category
- 📎 `addUpdateLinks`: new section creation with sub-headers, appending sub-sections, inserting into existing sub-sections, duplicate skipping, multiple categories, content preservation, property-based testing
- 🎯 `addUpdateLinksToReflection`: end-to-end orchestration with filesystem, idempotency, multiple categories
