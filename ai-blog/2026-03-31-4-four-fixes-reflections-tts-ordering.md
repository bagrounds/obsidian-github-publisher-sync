---
share: true
aliases:
  - "2026-03-31 | 🔧 Four Fixes: Reflections, TTS, and Ordering 🛠️"
title: "2026-03-31 | 🔧 Four Fixes: Reflections, TTS, and Ordering 🛠️"
URL: https://bagrounds.org/ai-blog/2026-03-31-four-fixes-reflections-tts-ordering
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-03-31 | 🔧 Four Fixes: Reflections, TTS, and Ordering 🛠️

## 🧩 The Problem

🐛 Four separate bugs were reported today, all related to the daily automation pipeline and the text-to-speech reader.

🔗 First, when the Haskell automation created new daily reflection pages, the back link to the previous day and the forward link on the previous day were both missing.

🔇 Second, the TTS reader was reading social media embed sections aloud, including raw Tweet, Bluesky, and Mastodon embeds that sound garbled when synthesized.

📑 Third, the TTS auto-play feature would sometimes navigate to index pages, which are navigation hubs rather than content pages.

📐 Fourth, when blog sections were inserted into reflection notes, the Updates section could end up in the middle of the page instead of staying at the bottom where it belongs.

## 🔍 Root Cause Analysis

### 🔢 The Off-by-One That Silenced Every Link

🔎 The reflection linking bug turned out to be a simple off-by-one error in a length check. The function that searches for previous reflection files used a minimum length filter of 14 characters. But a standard date filename like "2026-03-31.md" is only 13 characters long. This meant the filter rejected every single date file, so the system never found a previous reflection. No previous reflection meant no back link on the new page and no forward link on the old one.

🩹 The fix was a one-character change: greater-than-or-equal-to 14 became greater-than-or-equal-to 13.

### ⏭️ The First Reflection Edge Case

🏗️ There was a second bug hiding in the forward link insertion logic. The function that adds a forward link to the previous day relied on finding the back-arrow emoji marker in the target file, then inserting the forward link immediately after it. But the very first reflection page has no back link, so the anchor pattern was never found, and the forward link was silently dropped.

🛠️ The fix adds a fallback: when no back-arrow marker exists, the function looks for the breadcrumb navigation line and appends the forward link after it.

### 🔇 Social Media Sections in TTS

🎧 The TTS reader walks through all block-level elements in the article, extracting cleaned text for speech synthesis. Social media embed sections, which appear as H2 headings with platform names like Tweet, Bluesky, or Mastodon, were treated as regular content and read aloud.

🛠️ The fix detects these social section headings during text extraction and sets a flag to skip all content until the next non-social H2 heading is encountered. A new constant in tts.utils.ts defines the platform names to detect.

### 📑 Index Pages in Auto-Play

⏭️ The auto-play resolution function already filtered out index pages when falling back to article link discovery, but it did not apply the same filter to series navigation links. If a series happened to have an index page as its next or back link, auto-play would navigate there.

🛠️ The fix adds the same index page check to both the next and back series link conditions, ensuring auto-play never lands on an index page regardless of how the link was discovered.

### 📐 Section Ordering in Reflections

📄 When inserting a new blog section into a reflection note, the code looked for social media embed sections and inserted before them. But it did not account for the Updates section, so a blog section could be inserted after Updates, breaking the intended ordering.

🛠️ The fix extends the insertion point search to include the Updates section header alongside the social media headers. Similarly, when creating a new Updates section, the code now checks for social media sections and inserts before them instead of blindly appending at the end.

## 🧬 Consolidation

🗂️ The updates section header constant was previously defined in three separate files across the Haskell codebase. As part of this fix, all definitions were consolidated into a single location in the shared Types module, eliminating duplication and preventing future drift.

## 🧪 Testing

✅ All 675 Haskell tests pass, including new tests for forward link insertion on first reflections, section ordering with Updates, and section ordering with both Updates and social media sections.

✅ All 184 TypeScript tests pass, including new tests for index page filtering on series nav links, property-based tests ensuring auto-play never returns an index page from nav links, and a constant validation test for the social section headings.

## 📚 Book Recommendations

### 📖 Similar
* Working Effectively with Legacy Code by Michael Feathers is relevant because this work involved tracing subtle bugs through existing systems, understanding the behavior of interconnected components, and making surgical fixes without breaking other functionality.
* Debugging by David J. Agans is relevant because the root cause analysis of the off-by-one error and the edge case in forward link insertion illustrate systematic debugging techniques applied to real production code.

### ↔️ Contrasting
* The Design of Everyday Things by Don Norman offers a contrasting perspective by focusing on how good design prevents errors in the first place, rather than fixing them after the fact. The length check bug is a classic example of an interface that made the wrong value easy to write.

### 🔗 Related
* Domain-Driven Design by Eric Evans is relevant because the consolidation of the updates section header into a shared Types module reflects the principle of a ubiquitous language, where domain concepts live in exactly one place.
* Release It! by Michael T. Nygaard is relevant because the section ordering and auto-play fixes address production behavior issues that only surface when multiple automated systems interact over time.
