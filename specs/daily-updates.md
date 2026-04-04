# 🔄 Daily Updates — Wiki Link Notifications in Reflections

## 🎯 Overview

📋 When files are modified by automated tasks (image backfill, internal linking, auto-posting), a wiki link to each modified file is appended to the daily reflection's `## 🔄 Updates` section.
🔁 Replaces the old "breadcrumb trail" strategy that updated `updated` frontmatter timestamps along BFS paths.
📱 Optimized for Obsidian mobile — a single glance at the reflection reveals every file touched today.
🧩 Fully idempotent — links and details already present are silently skipped.
📂 Updates are organized by page, with each page listing its changes as indented sub-bullets.

## 🏗️ Architecture

### 📦 Components

| 🧩 Component | 📂 Path | 📝 Purpose |
|---|---|---|
| 📚 Library | `haskell/src/Automation/DailyUpdates.hs` | 🔧 Pure functions for building and inserting page-based update links with detail sub-bullets |
| 🧪 Tests | `haskell/test/Automation/DailyUpdatesTest.hs` | ✅ Tests covering page-based update links |
| 🔌 Consumers | `haskell/src/Automation/SocialPosting.hs` | 📢 Adds platform-specific details after social media posting |
| 🔌 Consumers | `haskell/app/RunScheduled.hs` | 🖼️🔗 Adds details after backfill-blog-images and internal-linking |

### 🔄 Data Flow

```
🖼️ backfill-blog-images / 🔗 internal-linking / 📢 auto-post
         ↓
📂 Collect modified file paths + build detail descriptions
         ↓
🔧 addUpdateLinksToReflection(reflectionsDir, date, [UpdateLink])
         ↓
📄 Ensure daily reflection exists (create from template if missing)
         ↓
📄 Read today's reflection note
         ↓
🧩 addUpdateLinks(content, links)
   ├── 📌 Create ## 🔄 Updates section if missing
   ├── 📂 Create page entry if missing
   ├── ➕ Append new detail sub-bullets under page entry (skip duplicates)
   └── 📍 Place section before social media embeds
         ↓
💾 Write updated reflection note
```

## 📂 Update Details by Source

🏷️ Each `UpdateLink` carries a list of detail descriptions that appear as indented sub-bullets under the page link:

| 🏷️ Source | 📝 Detail Text | 📋 Used By |
|---|---|---|
| Image backfill | `🖼️ added image` | backfill-blog-images |
| Internal linking | `🔗 added N internal link(s)` (e.g., `🔗 added 1 internal link` or `🔗 added 2 internal links`) | internal-linking (count from FileResult) |
| Social posting | `🦋 posted to BlueSky`, `🐘 posted to Mastodon`, `🐦 posted to Twitter` | auto-post (per-platform details) |

📄 Example reflection with page-based updates:

```markdown
## 🔄 Updates
- [[ai-blog/2026-03-28-my-post|2026-03-28 | 📝 My Post 🤖]]
  - 🖼️ added image
  - 🦋 posted to BlueSky
  - 🐘 posted to Mastodon
  - 🔗 added 2 internal links
- [[books/some-book|Some Book]]
  - 🦋 posted to BlueSky
```

## 🆚 Old vs New Strategy

| 📏 Aspect | ❌ Breadcrumb Trail (Old) | ✅ Updates Section (New) |
|---|---|---|
| 📍 Where | `updated` timestamp in each file along BFS path | `## 🔄 Updates` section in daily reflection |
| 📱 Discoverability | Must search vault for recently-updated timestamps | One section in today's reflection |
| 🔧 Complexity | BFS traversal to propagate timestamps | Simple append of wiki links |
| 🧩 Idempotency | Timestamp comparison | Detail-text deduplication |
| 📊 Scope | Touches many files across the vault | Touches only the reflection note |

## 🔗 Link Format

📝 Each page appears once as a top-level list item with its title as display text, followed by indented detail sub-bullets:

```markdown
- [[path/to/file|File Title]]
  - 🖼️ added image
  - 🦋 posted to BlueSky
```

📄 The title is extracted from the linked-to file's frontmatter `title` field, which matches the note's alias. Falls back to the filename if no title is found.
📢 Social posting links use the specific page title from the `ContentNote` rather than a generic label.

## 📍 Section Placement

📌 The `## 🔄 Updates` section is placed **before** social media embed sections (`## 🐦 Tweet`, `## 🦋 Bluesky`, `## 🐘 Mastodon`) if they exist, otherwise at the **end** of the reflection note.
📂 Within the updates section, each page gets its own `- [[path|title]]` entry with detail sub-bullets.
🔄 If the section or page entry already exists, new details are appended as indented sub-bullets.
🆕 If the section does not exist, it is created before social media sections (or at the end if none exist).
🆕 If a page is not yet listed, it is appended at the end of the updates section.
📐 Page ordering from top to bottom: content sections, Updates section, social media sections.

## 🔧 Key Functions

### 🧊 Pure Functions (No I/O)

| 🔧 Function | 📝 Purpose |
|---|---|
| `buildUpdateLink(filePath, title)` | 🔗 Creates a `- [[path\|title]]` wiki link line |
| `buildPageEntry(path, title, details)` | 📋 Creates a page link line plus indented detail sub-bullets |
| `addUpdateLinks(content, links)` | 📎 Inserts page-based update links with details into reflection content, skipping duplicates |

### 💾 I/O Functions

| 🔧 Function | 📝 Purpose |
|---|---|
| `extractTitleFromFile(filePath)` | 📄 Reads a file and extracts its title from frontmatter or H1 |
| `addUpdateLinksToReflection(reflectionsDir, date, links)` | 🎯 Orchestrator: ensure reflection exists → insert links with details → write |

## 🛡️ Idempotency

✅ All operations are idempotent:
- 🔗 Detail insertion checks whether the specific detail text already appears under the page's entry in the Updates section
- 📌 Section and page entry creation only happens when the heading or link is absent
- 🔄 Re-running with the same modified paths and details produces no changes

## 🧪 Testing

🔬 Tests in `haskell/test/Automation/DailyUpdatesTest.hs` covering:
- 📎 `addUpdateLinks`: new section creation with page entries and details, adding pages to existing sections, inserting details into existing page entries, duplicate skipping, multiple pages, incremental updates from different operations, content preservation, property-based testing
- 🎯 `addUpdateLinksToReflection`: end-to-end orchestration with filesystem, idempotency, incremental detail accumulation, multiple pages
