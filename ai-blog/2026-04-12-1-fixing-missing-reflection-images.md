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

🎯 We changed the default sort date for files without a date prefix from today to January 1, 1970.

📐 This is the undatedFileFallback sentinel, a single constant that replaces the dynamic today value in the backfill candidate constructor.

🏗️ The effect is immediate: any content with a real date in its filename, including reflections and blog posts, now sorts before all undated library content.

🪞 After a reflection receives its creative title at 10 PM, it becomes the highest-priority candidate in the next backfill run, because its date is today while library files are pinned to 1970.

📊 The change is a single-line substitution in the checkCandidate function, replacing fromMaybe today with fromMaybe undatedFileFallback.

## 🧪 Testing

✅ We added three focused tests verifying that the sentinel date is 1970-01-01, that it sorts after any modern date, and that dated content like reflections always takes priority.

🔢 All 1510 tests pass, including the three new ones.

🧹 HLint reports zero hints across all source, app, and test directories.

## 🏗️ Design Decisions

🤔 We considered three approaches before settling on the sentinel date.

🔄 Option one was to make the sort stable by changing the comparison from greater-than-or-equal to strictly-greater-than. This would preserve insertion order for same-date items, giving reflections priority on the same day. But it would not help after midnight when library files refresh to the new today.

🕙 Option two was to generate the image immediately after the title, as part of the reflection-title task. This would be the most direct pipeline, but it would couple two currently independent modules and require threading image provider configuration through the title generator.

📅 Option three, which we chose, was to change the default date for undated files. This keeps the modules decoupled, requires minimal code changes, and provides a permanent fix: dated content always sorts before undated content, regardless of the current day.

🧩 The sentinel date approach also has a pleasant side effect: it reveals the true priority of the backfill queue. Content created with intention, timestamped by the user, gets processed first. Library content accumulates in the background and fills remaining capacity.

## 📚 Book Recommendations

### 📖 Similar
* Thinking in Systems by Donella H. Meadows is relevant because this bug is a classic systems dynamics problem where a feedback loop (daily date reset) created an unintended steady state (reflections never getting images), and understanding system behavior patterns helps diagnose such issues.
* The Design of Everyday Things by Don Norman is relevant because the bug stemmed from a default value that seemed reasonable in isolation but created a usability failure in context, mirroring how good local design decisions can produce poor system-level outcomes.

### ↔️ Contrasting
* Antifragile by Nassim Nicholas Taleb offers a contrasting view where systems should benefit from disorder rather than being fragile to it, whereas our backfill system was fragile to the specific disorder of having many undated files.

### 🔗 Related
* Release It! by Michael T. Nygard explores production system failures and stability patterns, which connects to how this scheduling and prioritization bug only manifested under real-world conditions with a large content library.
* A Philosophy of Software Design by John Ousterhout discusses deep modules and interface design, which relates to how the sentinel date approach keeps the backfill and title-generation modules cleanly separated while fixing the cross-cutting concern.
