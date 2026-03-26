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
🚫 Untitled reflections shouldn't be posted to social media.

## 🎮 The Title Game

📊 We analyzed over 20 recent reflection titles to discover the creative game behind them:

1. 📋 Extract all linked content titles from the day's reflection (books, blog posts, videos)
2. 🎯 Pick exactly one interesting word from each content title
3. 🔤 Arrange these words into a meaningful phrase or sentence fragment
4. 🎨 Prefix each meaningful word with 1–2 relevant emojis
5. 🏷️ Append trailing category emojis (extracted from section headings)

| 📅 Date | 🔗 Content Titles | 🏷️ Result |
|----------|-------------------|-----------|
| 📆 2026-03-23 | 📚 A **Gentle** Afternoon..., 🤖 The Crucible of **Constraint**..., 🏛️ The Forgotten **Commons**... | 🕊️ Gentle 🚪 Constraint 🏛️ Commons 📚🐔🤖🏛️📺 |
| 📆 2026-03-10 | 📚 Hold Me **Tight**..., 🏗️ **Functional** Refactoring..., 🤖 The **Agentic** Playbook..., 🔊 Teaching the Robot to **Breathe**... | 🫂 Tight 🏗️ Functional 🤖 Agentic 🗣️ Breathe 📚 |
| 📆 2026-02-20 | 📚 **Rogue** Protocol, 📚 **Exit** Strategy | 🕵️‍♀️ Rogue 🚪 Exit 📚 |

## 🏗️ Architecture

🧱 The solution maximizes deterministic computation and minimizes what Gemini must do:

| 📦 Component | 📂 Path | 🎯 Purpose |
|--------------|---------|-------------|
| 📚 Library | `scripts/lib/reflection-title.ts` | 🔧 Deterministic extraction + focused AI prompt |
| 🧪 Tests | `scripts/lib/reflection-title.test.ts` | ✅ 54 tests across 9 suites |
| ⏰ Scheduler | `scripts/lib/scheduler.ts` | 📅 At-or-after scheduling at 10 PM Pacific |
| 🎛️ Orchestrator | `scripts/run-scheduled.ts` | 🔄 Vault sync, idempotency, yesterday catchup |
| 📋 Spec | `specs/reflection-title.md` | 📐 Product and engineering specification |

### 🧩 Deterministic vs AI Boundary

| 🔧 Step | 🤖 Who | 📝 Description |
|----------|--------|----------------|
| 📋 Extract linked titles | 💻 Code | Parse list items for wiki/markdown link display text |
| ✂️ Strip prefixes | 💻 Code | Remove date and emoji prefixes from titles |
| 🏷️ Extract trailing emojis | 💻 Code | Collect leading emojis from each H2 heading |
| 🎮 Play the word game | 🤖 Gemini | Pick one word per title, form a phrase, add emojis |
| 🔨 Assemble full title | 💻 Code | Append deterministic trailing emojis |
| 📝 Apply to note | 💻 Code | Update frontmatter and H1 heading |

## ⏰ Scheduling Strategy

🌙 The task runs at or after **10 PM Pacific time** — late enough that all daily content is in.

🔁 The `atOrAfter` flag ensures resilient retry — if hour 22 fails, hour 23 will catch it.
📅 Also checks yesterday's reflection if it's still untitled (catchup for missed days).

## 🛡️ Safety Gate

🚫 Untitled reflections are blocked from social media posting:
- 📋 `isUntitledReflection()` checks if a reflection's title is just the bare date
- ⛔ `isPostableContent()` returns false for untitled reflections
- 🔒 `getPriorDayReflectionIfNeeded()` skips untitled reflections

## 🔗 Shared Infrastructure

| 🔧 Feature | 📝 Description |
|-------------|----------------|
| 🔄 Retry logic | ♻️ Reuses `isRetriableError` from `generate-blog-post.ts` |
| 🤖 Model chain | 🏆 gemini-3.1-flash-lite-preview (best) → gemini-2.5-flash → gemini-2.5-flash-lite |
| ⏳ Backoff | 🔁 Exponential backoff (2s, 4s, 8s) on transient errors, 3 retries per model |
| ⚙️ Env override | 🔧 `REFLECTION_TITLE_MODEL` prepends to the chain |

## 🧪 Testing Strategy

✅ 54 tests organized across 9 suites:
- 🎨 `extractHeadingEmojis` — wiki links, markdown links, plain headings
- 🏷️ `extractTrailingEmojis` — multi-heading extraction, deduplication
- ✂️ `stripTitlePrefixes` — emoji stripping, date stripping, plain text
- 📋 `extractLinkedTitles` — wiki/markdown links, heading exclusion, date prefix stripping
- 🔍 `reflectionNeedsTitle` — bare date detection, titled detection
- 📝 `buildReflectionTitlePrompt` — one-word-per-title instructions, examples, numbering
- 🧹 `parseReflectionTitle` — code fences, quotes, date prefixes
- 🎨 `applyReflectionTitle` — frontmatter/H1 updates, content preservation, idempotency
- 🔗 Integration — needsTitle → applyTitle → no longer needsTitle

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
