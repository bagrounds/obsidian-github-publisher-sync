---
date: 2026-03-25
title: 🪞 Automated Reflection Title Generation with Gemini AI
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]

# 🪞 Automated Reflection Title Generation with Gemini AI

## 🎯 The Problem

📅 Every day, a reflection note captures the day's readings, blog posts, videos, and thoughts.
🏷️ Each reflection deserves a creative, emoji-enriched title that distills the day's themes at a glance.
✍️ Previously, these titles were crafted manually — time-consuming and easy to forget.

## 🔬 Reverse Engineering the Title Pattern

📊 We analyzed over 20 recent reflection titles from the published site to identify the pattern:

| 📅 Date | 🏷️ Title |
|----------|-----------|
| 📆 2026-03-23 | 🕊️ Gentle 🚪 Constraint 🏛️ Commons 📚🐔🤖🏛️📺 |
| 📆 2026-03-18 | 🧠 Evolution, 🏰 Empire, and the 🎷 Symphony of 🐔 Chickie 🎵 Loo 📚🐔🤖📺 |
| 📆 2026-03-10 | 🫂 Tight 🏗️ Functional 🤖 Agentic 🗣️ Breathe 📚 |
| 📆 2026-03-05 | 😴🧠💤 Tired 🤖 Murderbot 📺 |

🧩 The pattern emerged: each title is a sequence of emoji+keyword pairs capturing key themes, ending with category emojis indicating which sections appeared in the note.

## 🏗️ Architecture

🧱 The solution follows the established library-first architecture:

| 📦 Component | 📂 Path | 🎯 Purpose |
|--------------|---------|-------------|
| 📚 Library | `scripts/lib/reflection-title.ts` | 🔧 Pure functions + Gemini API calls |
| 🧪 Tests | `scripts/lib/reflection-title.test.ts` | ✅ 37 tests across 5 suites |
| ⏰ Scheduler | `scripts/lib/scheduler.ts` | 📅 At-or-after scheduling at hour 5 UTC |
| 🎛️ Orchestrator | `scripts/run-scheduled.ts` | 🔄 Vault sync, idempotency, execution |
| 📋 Spec | `specs/reflection-title.md` | 📐 Product and engineering specification |

## ⏰ Scheduling Strategy

🌙 The task runs at or after 9 PM Pacific time — late enough that all daily content is in.

🕐 We schedule at **hour 5 UTC**, which maps to:
- 🌧️ PST (winter): exactly 9 PM
- ☀️ PDT (summer): 10 PM (still "at or after 9 PM")

🔁 The `atOrAfter` flag on the schedule entry ensures resilient retry — if hour 5 fails, hour 6 through 23 will catch it.

## 🤖 Prompt Engineering

🎨 The Gemini prompt was reverse-engineered from the 20+ title examples:
- 📝 System prompt defines the title format rules and category emoji legend
- 📋 Recent titles are included as style reference examples
- 📄 The full reflection note content is provided for thematic extraction
- 🎯 Output is constrained to a single line — just the creative part, no date prefix

## 🛡️ Resilience Features

| 🔧 Feature | 📝 Description |
|-------------|----------------|
| 🔄 Idempotency | ⏭️ Skips if title already contains ` \| ` separator |
| 🔗 Model chain | 🤖 gemini-2.5-flash → gemini-2.5-flash-lite → gemini-3.1-flash-lite-preview |
| ⏳ Retry | 🔁 Exponential backoff (2s, 4s, 8s) on transient errors |
| 🧹 Response parsing | ✂️ Strips code fences, quotes, date prefixes, multi-line responses |
| ⚙️ Env override | 🔧 `REFLECTION_TITLE_MODEL` for custom model selection |

## 🧪 Testing Strategy

✅ 37 tests organized across 5 suites verify every pure function:
- 🔍 `reflectionNeedsTitle` — detects whether a title is just a bare date
- 📝 `buildReflectionTitlePrompt` — validates prompt structure and example inclusion
- ✂️ `parseReflectionTitle` — handles code fences, quotes, date prefixes
- 🎨 `applyReflectionTitle` — frontmatter and H1 updates with content preservation
- 🔗 Integration — applies title then verifies idempotency

## 📚 Book Recommendations

### 📖 Similar
- 🧠 *Atomic Habits* by James Clear
- 📓 *The Artist's Way* by Julia Cameron

### 🔄 Contrasting
- 🤖 *Gödel, Escher, Bach* by Douglas Hofstadter
- 📊 *Thinking, Fast and Slow* by Daniel Kahneman

### 🎨 Creatively Related
- 🪞 *The Midnight Library* by Matt Haig
- ✍️ *Bird by Bird* by Anne Lamott
