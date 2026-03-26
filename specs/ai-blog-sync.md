# 🤖 AI Blog Vault Sync — Automated Navigation & Reflection Linking

## 🎯 Overview

📝 AI blog posts written during PRs are automatically synced to the Obsidian vault with navigation links and daily reflection references.
🔗 Each post gets ⏮️ and ⏭️ links connecting it to its chronological neighbors in the ai-blog series.
📅 New posts are linked from the daily reflection matching their date via the Updates section.
🔄 All processing is idempotent and runs as part of the existing hourly backfill task.

## 🏗️ Architecture

### 📦 Components

| 🧩 Component | 📂 Path | 📝 Purpose |
|---|---|---|
| 📚 Library | `scripts/lib/ai-blog-links.ts` | 🔧 Pure functions for building and inserting nav links |
| 🧪 Tests | `scripts/lib/ai-blog-links.test.ts` | ✅ 42 tests covering all pure and I/O functions |
| 🔌 Consumer | `scripts/run-scheduled.ts` | 🖼️ Integrated into backfill-blog-images task |

### 🔄 Data Flow

The ai-blog sync runs as steps 3 and 5 of the backfill-blog-images task.

Step 1: Pull vault posts for all content directories (vault to repo).
Step 2: Backfill blog images (max 1 per hour).
Step 3 (NEW): Scan ai-blog posts and add missing navigation links (⏮️/⏭️).
Step 4: Sync modified repo files back to vault.
Step 5 (NEW): Link newly-linked ai-blog posts from their respective daily reflections.
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

The system detects unlinked posts by comparing each post's current nav line against its expected nav line based on file sort order.
Posts are sorted by filename, which uses the YYYY-MM-DD date prefix for chronological ordering.
When a new post appears (from a merged PR), it will have only the nav prefix without any navigation links.
The system adds the appropriate links and also updates adjacent posts whose neighbors have changed.

## 🛡️ Idempotency

All operations are idempotent and safe for hourly execution.

Nav link check: compares the current nav line against the expected line. If they match, the file is not touched.
Reflection links: the addUpdateLinksToReflection function skips links already present in the Updates section.
Second runs: after the first successful run links all posts, subsequent runs report zero modifications.

## 🎧 TTS Considerations

AGENTS.md now includes guidance for writing TTS-friendly AI blog posts.
Tables, code blocks, and inline code should be accompanied by prose descriptions for audio listeners.
Descriptive sentences and lists are preferred over visual-only formatting.

## 📐 Design Decisions

Integration with backfill was chosen over a standalone task to avoid redundant vault pull/push cycles.
Posts are linked by filename sort order rather than frontmatter dates for reliability and simplicity.
Navigation links use the same ⏮️/⏭️ emoji convention as the blog series for consistency.
Daily reflection links use the post's date (from filename), not the current date, so posts land in the correct reflection.
