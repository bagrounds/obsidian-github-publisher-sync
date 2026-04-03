---
share: true
date: 2026-03-25
title: "🔄 Smarter Publishing & 🤖🐲 AI Fiction for Daily Reflections"
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]

# 🔄 Smarter Publishing & 🤖🐲 AI Fiction for Daily Reflections

## 🎯 Two Changes, One Theme

📱 Daily reflections are the hub of this Obsidian vault — every blog post, book note, and social media embed lands there.
🔧 Today we shipped two features that make reflections smarter: a cleaner notification system for file changes and automated fiction generation.

## 🔄 The Updates Section: Replacing the Breadcrumb Trail

### 🧭 The Old Way

📍 Previously, when an automated task modified a file (backfilling an image, inserting a wiki link), the system propagated an `updated` timestamp along BFS paths back to the reflection.
🐌 This "breadcrumb trail" strategy touched many files across the vault just to signal that something changed.
📱 On Obsidian mobile, discovering what changed required searching for recently-updated timestamps — not exactly a glanceable experience.

### ✨ The New Way

📋 Now, a `## 🔄 Updates` section at the bottom of each daily reflection collects wiki links to every file modified that day.
👀 One glance at the reflection reveals every file touched by automation — image backfill, internal linking, social posting.
🧩 The implementation is refreshingly simple: `buildUpdateLink` formats a wiki link, `addUpdateLinks` inserts it into the reflection content.

### 🛡️ Idempotency by Design

🔁 If a link already exists in the Updates section, it's silently skipped.
📌 If the section doesn't exist yet, it's created at the end of the file.
🔄 Re-running the same task with the same files produces zero changes — safe for the hourly scheduler's relentless cadence.

### 📊 Before and After

| 📏 Aspect | ❌ Breadcrumb Trail | ✅ Updates Section |
|---|---|---|
| 📍 Signal location | `updated` timestamp scattered across vault files | Single section in today's reflection |
| 📂 Files touched | Many (BFS path propagation) | One (the reflection note) |
| 📱 Mobile discoverability | Search required | Glanceable list |
| 🔧 Implementation complexity | BFS traversal + timestamp comparison | Append wiki link + duplicate check |

## 🤖🐲 AI Fiction: Automated Storytelling

### 💡 The Idea

🌅 Every evening at 10 PM Pacific, after the day's readings and blog posts have accumulated in the reflection, a short fiction passage is generated.
🧠 The fiction abstracts themes from the day's content — it's not a summary, but an impressionistic riff on whatever the day held.
🎯 Each sentence starts with an emoji, no quotation marks are allowed, and the whole passage stays under 100 words.

### 🧹 Stripping for Focus

📄 Before the reflection reaches Gemini, the `stripForPrompt` function removes noise:
- 📋 YAML frontmatter
- 🐦 Social media embed sections
- 🔄 The Updates section itself

🎯 What remains is the substantive content — books, blog posts, notes, and thoughts — the raw material for fiction.

### 📍 Placement Matters

📌 The fiction section lands just before embed sections and the Updates section.
👀 This keeps it visible as authored content rather than buried under social media embeds.
🏗️ The `applyFiction` function handles the insertion logic, respecting the reflection's existing structure.

### 🤖 Model Chain

🔗 Fiction generation uses the same resilient model chain pattern as reflection titles:

| 🔢 Priority | 🤖 Model |
|---|---|
| 1️⃣ | gemini-2.5-flash |
| 2️⃣ | gemini-2.5-flash-lite |
| 3️⃣ | gemini-3.1-flash-lite-preview |

🔧 The `FICTION_MODEL` environment variable can prepend a custom model for experimentation.
🛡️ Each model gets exponential backoff retries on transient errors before falling through to the next.

### ⏰ Scheduling

📅 The `ai-fiction` task shares the 10 PM Pacific slot with `reflection-title`, but runs first.
🔄 Both use at-or-after scheduling — if the 10 PM run fails, subsequent hourly runs pick it up.
🧩 Idempotency ensures the fiction section is never duplicated.

## 🏗️ Architecture Recap

| 📦 Component | 📂 Path | 🎯 Purpose |
|---|---|---|
| 🔄 Updates Library | `scripts/lib/daily-updates.ts` | 🔧 Build and insert update wiki links |
| 🤖 Fiction Library | `scripts/lib/ai-fiction.ts` | 🧠 Strip, prompt, parse, and apply fiction |
| 🧪 Updates Tests | `scripts/lib/daily-updates.test.ts` | ✅ Pure function and I/O tests |
| 🧪 Fiction Tests | `scripts/lib/ai-fiction.test.ts` | ✅ Pure function tests |
| ⏰ Scheduler | `scripts/lib/scheduler.ts` | 📅 Hour 22 at-or-after for ai-fiction |
| 🎛️ Orchestrator | `scripts/run-scheduled.ts` | 🔄 runAiFiction and update link integration |

## 💡 Lessons Learned

1. 📱 **Optimize for the reader's device** — breadcrumb trails were elegant in theory but invisible on mobile; a simple list in one place wins
2. 🧩 **Idempotency is infrastructure** — when tasks run hourly, every operation must be safe to repeat without side effects
3. 🧹 **Strip before prompting** — removing frontmatter and embeds from the AI context produces more focused, creative output
4. ⏰ **Share scheduling slots carefully** — fiction runs before title generation so the title can incorporate fiction themes
5. 🔗 **Model chains are table stakes** — free-tier rate limits mean every AI feature needs fallback models

## 📚 Book Recommendations

### 📖 Similar
- 🧠 Atomic Habits by James Clear
- 📓 The Bullet Journal Method by Ryder Carroll
- 🏗️ A Philosophy of Software Design by John Ousterhout

### 🔄 Contrasting
- 🎨 The Art of Fiction by John Gardner
- 🤖 Gödel, Escher, Bach by Douglas Hofstadter

### 🎨 Creatively Related
- ✍️ Bird by Bird by Anne Lamott
- 🪞 If on a Winter's Night a Traveler by Italo Calvino
- 🔧 The Design of Everyday Things by Don Norman
