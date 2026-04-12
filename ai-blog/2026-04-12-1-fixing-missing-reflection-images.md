---
share: true
aliases:
  - "2026-04-12 | 🪞 Fixing Missing Reflection Images 🖼️"
title: "2026-04-12 | 🪞 Fixing Missing Reflection Images 🖼️"
URL: https://bagrounds.org/ai-blog/2026-04-12-1-fixing-missing-reflection-images
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-04-12 | 🪞 Fixing Missing Reflection Images 🖼️

## 🐛 The Bug

🔍 Daily reflections had been receiving creative titles at 10 PM Pacific but were never getting their cover images generated afterward.

📅 The image backfill task runs every hour, scanning over a thousand notes for missing images and generating up to two per run.

🕙 After the reflection-title task writes a creative title, the next backfill run should pick up the reflection and generate an image that captures the full day's content.

⏳ Instead, the past several days of reflections all had titles but zero images.

## 🔬 Root Cause Analysis

🧅 We peeled back five layers to find the root cause.

🥇 First why: the backfill was generating images for library files like bot-chats instead of reflections. The logs confirmed it: 1280 candidates in the queue, but the two slots went to bot-chats/mothers-day and bot-chats/motivation-and-discipline.

🥈 Second why: non-dated library files were getting the same sort priority as reflections. The backfill sorts candidates by date descending, and files without a date in their filename defaulted to today's date. This put hundreds of library files in the same tier as the just-titled reflection.

🥉 Third why: within the same date tier, library files won the tiebreaker. The insertion sort used a greater-than-or-equal comparison, which meant later-processed candidates pushed ahead of earlier ones. Since library directories are scanned after reflections, their files landed in front.

🏅 Fourth why: the library is vast. Eight directories containing articles, books, bot-chats, games, products, software, tools, and topics contributed over a thousand candidates, all pinned to today's date.

🏆 Fifth why: the system never recovered. Each new day, library files refreshed to the new today, while the untouched reflection's date stayed in the past. With only two images per hourly run, reflections were perpetually unreachable.

## 🔧 The Fix

🎯 We changed the default sort date for files without a date prefix from today to the date found in frontmatter fields.

📐 This mirrors the approach used by the RSS feed, which resolves dates through a priority chain: frontmatter, then git history, then filesystem. For the backfill, we use the first link in that chain: the frontmatter date. The function checks for updated, modified, date, and created fields in priority order.

🏗️ The effect is natural: library files that have been recently updated by the vault sync get their real updated timestamp, while old library content without any date fields falls to a 1970-01-01 sentinel. A reflection with a date-prefixed filename like 2026-04-12.md always gets its date from the filename, which keeps it in its correct position.

🪞 After the reflection-title task writes a new title at 10 PM Pacific, it also updates the updated field in frontmatter. Bot-chats and other library files that were recently edited in Obsidian have fresh updated timestamps. Files that haven't been touched in months have older timestamps or no date fields at all, sorting them behind recent content.

📊 The change is pure, requiring no filesystem or git IO. It parses the already-read file content for frontmatter date fields and uses a sentinel fallback for truly dateless files.

## 🧪 Testing

✅ All 1519 tests pass, including 12 new tests for parseDateFromFrontmatter covering each field priority, format variations, empty frontmatter, and unrecognized field names.

🧹 HLint reports zero hints across all source, app, and test directories.

## 🏗️ Design Decisions

🤔 We iterated through three approaches before settling on frontmatter date parsing.

🔄 Option one was a sentinel date of 1970-01-01 for all undated files. This worked by pushing all undated content behind all dated content. However, it lost the ability to distinguish between recently modified and ancient library files. A newly written bot-chat would get the same priority as a decades-old article.

🕙 Option two was to use filesystem modification time via getModificationTime. This seemed natural but fails in CI environments where content files are synced fresh each run, giving all files roughly the same timestamp.

📅 Option three, which we chose, was to parse frontmatter date fields. This works correctly in CI because the updated field in frontmatter reflects the actual Obsidian vault modification time, not the CI sync time. It matches the RSS feed's first priority in its date resolution chain, adds no new IO dependencies, and naturally prioritizes recently edited content.

🧩 The frontmatter approach has a pleasant side effect: the backfill queue now reflects real editorial activity. Content that was recently edited in Obsidian gets images first, while untouched archival content gradually catches up over time.

## 📚 Book Recommendations

### 📖 Similar
* Thinking in Systems by Donella H. Meadows is relevant because this bug is a classic systems dynamics problem where a feedback loop (daily date reset) created an unintended steady state (reflections never getting images), and understanding system behavior patterns helps diagnose such issues.
* The Design of Everyday Things by Don Norman is relevant because the bug stemmed from a default value that seemed reasonable in isolation but created a usability failure in context, mirroring how good local design decisions can produce poor system-level outcomes.

### ↔️ Contrasting
* Antifragile by Nassim Nicholas Taleb offers a contrasting view where systems should benefit from disorder rather than being fragile to it, whereas our backfill system was fragile to the specific disorder of having many undated files.

### 🔗 Related
* Release It! by Michael T. Nygard explores production system failures and stability patterns, which connects to how this scheduling and prioritization bug only manifested under real-world conditions with a large content library.
* A Philosophy of Software Design by John Ousterhout discusses deep modules and interface design, which relates to how the frontmatter date approach keeps the backfill and title-generation modules cleanly separated while fixing the cross-cutting concern.
