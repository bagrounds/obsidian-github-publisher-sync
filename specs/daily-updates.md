# 🔄 Daily Updates — Changes Directory

## 🎯 Overview

📋 When files are modified by automated tasks (image backfill, internal linking, auto-posting), a wiki link to each modified file is recorded in a daily changes page at `changes/YYYY-MM-DD.md`.
🔁 Replaces the old approach of writing updates directly into the daily reflection note, reducing Enveloppe plugin link-checking overhead.
📂 Each day gets its own changes page in the `changes/` directory, named after the date (matching the reflection page naming convention).
🪞 Each reflection page links to its corresponding changes page at the bottom.
📱 Optimized for Obsidian mobile — reflections stay lightweight while changes are a click away.
🧩 Fully idempotent — links and details already present are silently skipped.
📊 A stats line at the top summarizes total counts per update type.
📐 Updates are rendered as a compact markdown table with one row per page and emoji column headers.

## 🏗️ Architecture

### 📦 Components

| 🧩 Component | 📂 Path | 📝 Purpose |
|---|---|---|
| 📚 Library | `haskell/src/Automation/DailyUpdates.hs` | 🔧 Typed update details, parse/merge/render pipeline, changes page management |
| 📚 Library | `haskell/src/Automation/DailyReflection.hs` | 🪞 Reflection template with changes link, trailing section ordering |
| 🧪 Tests | `haskell/test/Automation/DailyUpdatesTest.hs` | ✅ Tests covering table format, stats, migration, idempotency, changes directory |
| 🧪 Tests | `haskell/test/Automation/DailyReflectionTest.hs` | ✅ Tests covering reflection template with changes link |
| 🔌 Consumers | `haskell/src/Automation/SocialPosting.hs` | 📢 Adds `PostedTo` details after social media posting |
| 🔌 Consumers | `haskell/app/RunScheduled.hs` | 🖼️🔗 Adds `ImageAdded` and `InternalLinksAdded` details |

### 🔄 Data Flow

```
🖼️ backfill-blog-images / 🔗 internal-linking / 📢 auto-post
         ↓
📂 Collect modified file paths + build typed UpdateDetail values
         ↓
🔧 addUpdateLinksToReflection(vaultDir, Day, [UpdateLink])
         ↓
📄 Ensure daily reflection exists (create from template if missing)
         ↓
📁 Ensure changes directory exists (with index.md + Dataview query)
         ↓
📄 Ensure changes page exists (changes/YYYY-MM-DD.md)
   ├── 🔍 Find previous changes page date
   ├── 📄 Create page with backward link to previous
   └── ⏭️ Add forward link to previous changes page
         ↓
📄 Read today's changes page
         ↓
🧩 addUpdateLinks(content, links) — parse → merge → render pipeline
   ├── 📖 Parse existing updates section (table or legacy bullet format)
   ├── 🔀 Merge new entries with existing (per-page, per-column)
   ├── 📊 Compute stats line from merged entries
   └── 📐 Render as markdown table with only active columns
         ↓
💾 Write updated changes page
         ↓
🔗 Ensure reflection has a link to the changes page
```

## 📂 Changes Directory Structure

📁 The `changes/` directory is a sibling of `reflections/` in the vault root.

📄 Each changes page follows this template:

```markdown
---
share: true
aliases:
  - "YYYY-MM-DD"
title: "YYYY-MM-DD"
URL: "https://bagrounds.org/changes/YYYY-MM-DD"
---
[[index|Home]] > [[changes/index|Changes]] | [[reflections/YYYY-MM-DD|🪞 YYYY-MM-DD]] | [[changes/PREV-DATE|⏮️]]
# YYYY-MM-DD
```

🧭 The reflection backlink includes both the mirror emoji and the date for clarity.
🔗 Forward and backward navigation links (⏭️ and ⏮️) are added between consecutive changes pages, following the same pattern used for reflections.
📎 When a new changes page is created, the previous changes page receives a forward link.

📑 The index page follows this template:

```markdown
---
share: true
aliases:
  - "🔄 Changes"
title: "🔄 Changes"
URL: "https://bagrounds.org/changes"
---
[[index|Home]]
# 🔄 Changes

\`\`\`dataview
LIST WITHOUT ID link(file.path, file.frontmatter.title)
FROM "changes"
WHERE file.name != this.file.name
SORT file.name DESC
\`\`\`
```

📊 The index uses a Dataview query to automatically list all changes pages, newest first.

## 🪞 Reflection Integration

🔗 Every new reflection page includes a changes link as an H2 heading at the very bottom of the template, via the shared `changesLink` function defined in `DailyReflection`.
📌 For existing reflections (created before this feature), the changes link is added automatically as an H2 heading when updates are first written for that date.
📐 The changes link prefix (`"## [[changes/"`) is included in `trailingSectionHeaders`, so blog series sections and social embeds are always placed above it. The prefix includes the H2 marker to ensure section insertion never splits the heading from the link.

## 🏷️ Update Detail Types

📦 Each `UpdateLink` carries a list of typed `UpdateDetail` values (ADT, not free-text strings):

| 🏷️ Constructor | 📝 Description | 📋 Source | 🔣 Column Emoji |
|---|---|---|---|
| `ImageAdded` | An image was added to the page | backfill-blog-images | 🖼️ |
| `InternalLinksAdded Int` | N internal links were added | internal-linking | 🔗 |
| `PostedTo Bluesky` | Page was posted to Bluesky | auto-post | 🦋 |
| `PostedTo Mastodon` | Page was posted to Mastodon | auto-post | 🐘 |
| `PostedTo Twitter` | Page was posted to Twitter | auto-post | 🐦 |

📄 Example changes page with table-format updates:

```markdown
---
share: true
aliases:
  - "2026-03-28"
title: "2026-03-28"
URL: "https://bagrounds.org/changes/2026-03-28"
---
[[index|Home]] > [[changes/index|Changes]] | [[reflections/2026-03-28|🪞 2026-03-28]]
# 2026-03-28

## 🔄 Updates
📊 3 pages · 2 🖼️ images · 5 🔗 links · 2 🦋 Bluesky · 1 🐘 Mastodon

| Page | 🖼️ | 🔗 | 🦋 | 🐘 |
|---|---|---|---|---|
| [[ai-blog/2026-03-28-my-post\|2026-03-28 \| 📝 My Post 🤖]] | 🖼️ | 2 | 🦋 | 🐘 |
| [[books/some-book\|Some Book]] | 🖼️ | 3 | 🦋 |  |
| [[ai-fiction/chapter-5\|Chapter 5]] |  |  |  | 🐘 |
```

## 📐 Table Format

📊 The stats line appears directly below the section header, serving as both a summary and a legend. Each stat includes the emoji and a descriptive word (e.g., "2 🖼️ images · 3 🔗 links · 1 🦋 Bluesky") so readers know what each column represents. Only non-zero types are shown.

📐 Only columns with at least one entry are shown. Column headers are single emojis for compact width. Cell values use the column emoji (e.g., 🖼️, 🦋, 🐘) instead of generic checkmarks, so readers at the bottom of a large table can identify columns without scrolling to the header. Internal link cells show numeric counts.

🔤 Pipe characters in wiki links are escaped as `\|` to prevent breaking the markdown table structure. Titles such as "2026-03-28 | My Reflection" render safely inside table cells.

🔢 Canonical column ordering: 🖼️ → 🔗 → 🦋 → 🐘 → 🐦

## 🔀 Merge Behavior

🔄 When the same page receives updates from different operations (e.g., image backfill then social posting), details merge into the same table row:
- `ImageAdded` + `ImageAdded` = `ImageAdded` (idempotent)
- `InternalLinksAdded a` + `InternalLinksAdded b` = `InternalLinksAdded (a + b)` (additive)
- `PostedTo p` + `PostedTo p` = `PostedTo p` (idempotent)

📖 Legacy bullet-format sections are automatically migrated to table format on the next update.

## 🔧 Key Functions

### 🧊 Pure Functions (No I/O)

| 🔧 Function | 📝 Purpose |
|---|---|
| `addUpdateLinks(content, links)` | 📎 Parse existing section → merge new entries → render table with stats |
| `buildChangesPageContent(date, previousDate)` | 📄 Build the frontmatter, nav (with backward link), and heading for a changes page. Date parameter is `Day`. |
| `buildChangesIndexContent` | 📑 Build the index page with a Dataview query for the changes directory |
| `addChangesForwardLink(content, targetDate)` | ⏭️ Add a forward navigation link to a changes page |

### 💾 I/O Functions

| 🔧 Function | 📝 Purpose |
|---|---|
| `extractTitleFromFile(filePath)` | 📄 Reads a file and extracts its title from frontmatter |
| `addUpdateLinksToReflection(vaultDir, date, links)` | 🎯 Orchestrator: ensure reflection and changes page exist → write updates to changes page → link reflection. Date parameter is `Day`. |
| `ensureChangesDirectory(changesDir)` | 📁 Create changes directory and index if missing |
| `ensureChangesPage(changesDir, date)` | 📄 Create changes page from template if missing, add forward link to previous page. Date parameter is `Day`. |
| `ensureChangesLinkInReflection(reflectionPath, date)` | 🔗 Add changes link to reflection if not already present |
| `findPreviousChangesDate(changesDir, today)` | 🔍 Find the most recent changes page date before today |

## 🛡️ Data Loss Prevention

📐 The table parser uses whitespace-insensitive header detection: it splits each line by pipe characters, strips whitespace from each cell, and checks if any cell equals "Page". This correctly handles both compact tables written by the automation and padded tables reformatted by Obsidian's editor.

📊 A safety check compares the number of parsed entries against the page count in the stats line (e.g., "📊 31 pages"). If zero entries were parsed but the stats line indicates entries exist, the function refuses to overwrite and returns the content unchanged. The I/O wrapper logs a warning for diagnosis.

🔗 As a defensive measure, the parser supports two link formats in table rows:
- **Wiki links**: `[[path\|title]]` — the native format written by the automation
- **Standard markdown links**: `[title](path)` — supported defensively in case content is ever modified

📐 When parsing standard markdown links, relative paths are resolved to vault-relative paths:
- `./file.md` → `reflections/file` (same directory)
- `../dir/file.md` → `dir/file` (parent directory)
- `file.md` → `reflections/file` (bare filename)

🔀 Tables may contain a mix of wiki links and markdown links. The parser tries wiki link format first, then falls back to markdown link format.

🔒 The scheduled workflow uses a concurrency group (`scheduled-tasks`) to ensure only one run executes at a time, preventing last-writer-wins race conditions when vault modifications overlap.

## 🛡️ Idempotency

✅ All operations are idempotent:
- 🔗 Detail deduplication is **per-page, per-column**: the same detail type under the same page is merged, not duplicated. Same detail type across different pages creates separate rows.
- 📊 Stats are recomputed from the full merged state each time, so they always reflect the current total.
- 📌 Section creation only happens when the heading is absent.
- 🔄 Re-running with the same modified paths and details produces no changes.
- 📢 Social posting updates record only the platforms that were **newly posted** in the current run.
- 📁 Changes directory and index creation are idempotent — existing files are not overwritten.
- 🔗 Changes link insertion in reflections checks for existing link prefix before adding.

## 🧪 Testing

🔬 Tests in `haskell/test/Automation/DailyUpdatesTest.hs` covering:
- 📊 Table creation with stats and emoji column headers
- 🔀 Merging new pages and details into existing tables
- 🔗 Internal link count accumulation (additive merging)
- 📐 Only active columns shown in table header
- 📖 Legacy bullet format migration to table on next update
- 🧩 Idempotency (duplicate details produce no changes)
- 📍 Section placement before social media embeds
- 🎯 End-to-end orchestration with filesystem
- 🔬 Property-based testing (content outside updates section preserved)
- 🔗 Standard markdown link parsing and preservation
- 🔤 Escaped pipes in markdown link titles
- 🛡️ Data loss prevention when table rows are unparseable
- 📊 Stats page count extraction from stats line
- 🗺️ Relative path resolution for markdown links
- 📐 Obsidian-formatted table with column padding
- 🔀 Mixed wiki and markdown links in same table
- 📂 Updates written to changes page instead of reflection
- 📑 Changes index page creation with Dataview query
- 🔗 Changes link added to reflection
- 📄 Changes page frontmatter and navigation with date in reflection backlink
- ⏭️ Forward and backward navigation links between consecutive changes pages

🔬 Tests in `haskell/test/Automation/DailyReflectionTest.hs` covering:
- 🔗 Changes link included in new reflection template
- 📍 Changes link positioned after heading
- 🧩 Inserting a section before the changes link preserves the H2 heading
