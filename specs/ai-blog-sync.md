# 🤖 AI Blog Vault Sync — Automated Navigation & Reflection Linking

## 🎯 Overview

📝 AI blog posts written during PRs are automatically synced to the Obsidian vault with navigation links and daily reflection references.
🔗 Each post gets ⏮️ and ⏭️ links connecting it to its chronological neighbors in the ai-blog series.
📅 New posts are linked from the daily reflection matching their date via a dedicated AI Blog section.
🔄 All processing is idempotent and runs as part of the existing hourly backfill task.

## 🏗️ Architecture

### 📦 Components

| 🧩 Component | 📂 Path | 📝 Purpose |
|---|---|---|
| 📚 Library | `haskell/src/Automation/AiBlogLinks.hs` | 🔧 Pure functions for building and inserting nav links |
| 🧪 Tests | `haskell/test/Automation/AiBlogLinksTest.hs` | ✅ 42 tests covering all pure and I/O functions |
| 🔌 Consumer | `haskell/app/RunScheduled.hs` | 🖼️ Integrated into backfill-blog-images task |

### 🔄 Data Flow

The ai-blog sync runs as part of the backfill-blog-images task.

Step 1: Sync new AI blog posts from repo to vault (copy-if-missing only — never overwrites existing vault files).
Step 2: Backfill blog images (max 4 per hour).
Step 3: Scan ai-blog posts in vault and add missing navigation links (⏮️/⏭️).
Step 4: Add update links from image backfill results to daily reflections.
Step 5: Link AI blog posts to their date's daily reflection with a dedicated AI Blog section.
Step 6: Push vault.

### 🧭 Navigation Links

Each ai-blog post's breadcrumb line starts with the nav prefix and may include prev/next links.

A post with both neighbors gets a nav line like this:
Nav prefix, pipe separator, back link to previous post, forward link to next post.

For example, the nav prefix followed by a pipe, then the back link emoji pointing to the previous post's filename, and the forward link emoji pointing to the next post's filename.

The first post in the series has no back link.
The last post has no forward link.
A single post has only the nav prefix with no additional links.

### 🔍 Detection Mechanism

The system ensures every ai-blog post is linked from its date's daily reflection by processing all posts on every run.
Posts are sorted by filename, which uses the YYYY-MM-DD date prefix for chronological ordering.
The insertPostLink function is idempotent: it checks whether a link to each post already exists in the reflection and only writes when something is missing.
Navigation link updates (⏮️/⏭️) are tracked separately and only written when the expected nav line differs from the current one.

## 🛡️ Idempotency

All operations are idempotent and safe for hourly execution.

Nav link check: compares the current nav line against the expected line. If they match, the file is not touched.
Reflection links: every hourly run processes all ai-blog posts and ensures each has a link in its date's reflection. The insertPostLink function checks for existing links and only modifies the file when a new link is needed. This avoids the fragile one-shot trigger that previously relied on nav-link modification as a proxy for new posts.
Second runs: after the first successful run links all posts, subsequent runs detect existing links and skip them with zero writes.

## 🎧 TTS Considerations

AGENTS.md now includes guidance for writing TTS-friendly AI blog posts.
Tables, code blocks, and inline code should be accompanied by prose descriptions for audio listeners.
Descriptive sentences and lists are preferred over visual-only formatting.

## 📐 Design Decisions

Integration with backfill was chosen over a standalone task to avoid redundant vault pull/push cycles.
Posts are linked by filename sort order rather than frontmatter dates for reliability and simplicity.
Navigation links use the same ⏮️/⏭️ emoji convention as the blog series for consistency.
Daily reflection links use the post's date (from filename), not the current date, so posts land in the correct reflection.
