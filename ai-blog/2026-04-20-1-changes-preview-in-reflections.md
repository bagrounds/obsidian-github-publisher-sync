---
share: true
aliases:
  - "2026-04-20 | 📊 Changes Preview in Reflections 🪞"
title: "2026-04-20 | 📊 Changes Preview in Reflections 🪞"
URL: https://bagrounds.org/ai-blog/2026-04-20-1-changes-preview-in-reflections
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-04-20 | 📊 Changes Preview in Reflections 🪞

## 🎯 The Goal

📝 Daily reflections already included a link to their corresponding changes page, but that link pointed to the specific day rather than the changes index, and you had to click through to see what actually changed.

🔍 The goal was threefold: make the H2 heading link point to the changes index page for consistency with other section headings, show a compact stats preview directly in the reflection so readers get a snapshot without navigating away, and keep that preview perfectly in sync with the changes page.

## 🔧 What Changed

### 🔗 H2 Now Points to the Changes Index

📐 Previously, the changes heading at the bottom of each reflection was formatted as an H2 linking to that specific day's changes page, like "changes slash 2026-04-01." 🔄 Now, the H2 links to the changes index page instead, using the path "changes slash index," matching how other sections like blog series link to their index. 🆕 The display text stays the same, showing the rotation arrows emoji followed by "Changes," but the link target has changed from the daily page to the directory listing.

### 📊 Stats Preview Line

🪞 A new line appears directly under the H2 heading, showing a wikilink to the day's changes page followed by the stats summary. 📏 The format starts with the date as a clickable link to that day's changes page, followed by a pipe separator, and then the stats summary. 🔢 For example, a reflection for April first with three page changes and two images would show "2026-04-01" as a clickable link, then "chart emoji 3 pages, middle dot, 2 image emoji images."

💡 This gives readers a quick glance at the day's change activity without consuming vertical space for the full table or requiring a click to the changes page.

### 🔄 Automatic Stats Sync

🔁 Every time the changes page is updated with new entries, the stats preview in the corresponding reflection is automatically refreshed to match. 📊 This ensures the reflection always shows the latest stats without any manual intervention. 🧩 The sync is handled by the upsertChangesPreview function, which either inserts a new stats preview or replaces an existing one.

## 🏗️ Architecture

📦 Four new pure functions were introduced to support this feature.

🔗 The changesLink constant points to the changes index. 📊 The buildChangesStatsPreview function constructs the stats preview line by formatting a date-linked wikilink followed by the stats text wrapped in a ChangesStats domain type. 🔄 The upsertChangesPreview function handles inserting or updating the changes section in a reflection. 🔎 The extractStatsLine function locates the stats in a changes page by finding the first line starting with the chart emoji and wraps it in ChangesStats.

🧪 On the I/O side, the old ensureChangesLinkInReflection function was replaced with updateChangesPreviewInReflection, which reads the reflection, applies upsertChangesPreview, and writes back if anything changed. 🎯 The orchestrator function addUpdateLinksToReflection now extracts the stats from the updated changes page and passes it to the reflection updater.

## 🧪 Testing

🔬 Ten new tests cover every aspect of the feature.

📊 Unit tests verify that buildChangesStatsPreview produces the correct format and that changesLink points to the index. 🔄 The upsertChangesPreview function is tested for inserting into content without a changes section, updating an existing stats preview, inserting a preview when only the heading exists, and preserving content before the changes section. 🎲 A property test confirms that upsertChangesPreview is idempotent for arbitrary dates.

🔗 Integration tests verify that the stats preview appears in the reflection after writing changes, that the preview updates correctly after multiple rounds of updates, and that old-format headings are migrated during the integration flow. 🔎 The extractStatsLine function is tested for finding stats in various content structures and returning nothing when no stats exist.

## 📚 Book Recommendations

### 📖 Similar
* Refactoring by Martin Fowler is relevant because this change exemplifies the kind of small, safe, incremental refactoring that Fowler champions, transforming one interface into another while preserving all behavior and adding tests first.
* Domain-Driven Design by Eric Evans is relevant because the stats preview feature demonstrates modeling domain concepts as pure data transformations, keeping I/O at the edges and using a shared ubiquitous language across the codebase.

### ↔️ Contrasting
* The Pragmatic Programmer by David Thomas and Andrew Hunt offers a broader view on practical programming trade-offs, sometimes favoring quick pragmatic solutions over the principled functional architecture that shaped this change.

### 🔗 Related
* Haskell Programming from First Principles by Christopher Allen and Julie Moronuki explores the pure functional programming style that makes features like upsertChangesPreview testable and composable without any I/O dependencies.
