---
share: true
aliases:
  - "2026-03-30 | 🔗 Using the Right Alias in Wikilinks 🏷️"
title: "2026-03-30 | 🔗 Using the Right Alias in Wikilinks 🏷️"
URL: https://bagrounds.org/ai-blog/2026-03-30-2-wikilink-alias-fix
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-03-30 | 🔗 Using the Right Alias in Wikilinks 🏷️

## 🐛 The Bug

🔍 When the Haskell automation inserted wikilinks into Obsidian notes, it sometimes used raw filename slugs as the display text instead of the proper title from the linked-to note's frontmatter.

🎯 For example, a wikilink to a blog post about image generation might have looked like this: the link target followed by a pipe and then the raw slug 2026-03-28-my-cool-post. That is, the display text was just the filename with dashes, not the human-friendly title.

✅ The correct behavior is to read the target note's frontmatter title (which matches the Obsidian alias) and use it as the wikilink display text. So instead of a slug, you see the full title with emojis, like 2026-03-28 | 🎨 My Cool Post 🤖.

## 🔎 Root Cause

📂 The issue was in the Haskell orchestration code in RunScheduled.hs. When the image backfill pipeline generated images for blog posts, it produced a list of modified file paths. The code needed to create wikilinks pointing to those modified files and insert them into the daily reflection note.

🐞 Instead of reading the title from each modified file's frontmatter, the Haskell code fabricated a title by stripping the directory prefix and file extension from the filename. This string manipulation turned a path like ai-blog/2026-03-28-my-cool-post.md into just 2026-03-28-my-cool-post, which is a far cry from the actual display title.

🆚 The TypeScript implementation correctly reads the title from each file's frontmatter using the extractTitleFromFile function, which looks up the title field and falls back to the filename only when frontmatter is absent.

## 🔧 The Fix

🛠️ Two changes were made to the Haskell RunScheduled.hs file.

### 1️⃣ Image Backfill Update Links

🔄 Replaced the filename-based title fabrication with calls to extractTitleFromFile. This function reads the target file, parses its frontmatter, and returns the title field. If the file is missing or has no title, it falls back to the filename base name, which is the same safe fallback the TypeScript version uses.

### 2️⃣ Internal Linking Update Links

➕ Added missing update link creation for the internal linking pipeline. The TypeScript version adds wikilinks to the daily reflection for every file modified by internal linking, using the proper title from frontmatter. The Haskell version was missing this step entirely. Now it filters for modified files in the linking result, reads each file's title, and inserts categorized update links into the daily reflection.

## 🧪 Testing

✅ All 665 existing Haskell tests continue to pass. The pure functions like buildUpdateLink and addUpdateLinks were already well-tested. The fix is in the orchestration layer where titles are obtained, not in the pure link-building logic.

## 💡 Lessons Learned

🏗️ When porting functionality between languages, it is easy to get the happy path right but miss small details in the data plumbing. The Haskell formatWikilink function was identical to TypeScript's, but the value fed into it was wrong because the title was derived from a filename instead of read from the actual file.

🔗 A good principle for wikilinks: always let the target note define its own display name. Never fabricate a display name from the file path. The note's frontmatter title (which mirrors its Obsidian alias) is the single source of truth for how that note should appear in links.

## 📚 Book Recommendations

### 📖 Similar
* Haskell Programming from First Principles by Christopher Allen and Julie Moronuki is relevant because it covers the functional programming patterns used throughout this codebase, including algebraic data types and the IO monad, which are central to how titles are threaded through the pipeline.
* Domain-Driven Design by Eric Evans is relevant because the fix embodies a core DDD principle: letting each entity (in this case, each note) define its own identity (its display title) rather than deriving it from external context.

### ↔️ Contrasting
* The Pragmatic Programmer by David Thomas and Andrew Hunt offers a broader perspective on avoiding duplication, and would argue that deriving titles from filenames is a violation of the DRY principle since the title already exists in frontmatter.

### 🔗 Related
* Real World Haskell by Bryan O'Sullivan, John Goerzen, and Don Stewart is relevant because it covers practical Haskell IO patterns and file handling that are directly applicable to the extractTitleFromFile function and the traverse-based title reading approach used in the fix.
