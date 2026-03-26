# 🤖🐲 AI Fiction — Automated Fiction in Daily Reflections

## 🎯 Overview

📋 Generates a short, emoji-rich AI fiction passage for each daily reflection note.
🧠 Themes are abstracted from the day's content — frontmatter and embed sections are stripped before prompting.
🤖 Uses a Gemini model chain with retry and fallback for resilience.
🕐 Runs at 10 PM Pacific (hour 22), before the reflection-title task in the same scheduling slot.
🧩 Fully idempotent — skips if `## 🤖🐲 AI Fiction` section already exists.

## 🏗️ Architecture

### 📦 Components

| 🧩 Component | 📂 Path | 📝 Purpose |
|---|---|---|
| 📚 Library | `scripts/lib/ai-fiction.ts` | 🔧 Pure functions for prompt building, response parsing, and content application |
| 🧪 Tests | `scripts/lib/ai-fiction.test.ts` | ✅ Tests covering all pure functions |
| ⏰ Scheduler entry | `scripts/lib/scheduler.ts` | 📅 `ai-fiction` task at hour 22 Pacific with `atOrAfter` |
| 🎛️ Orchestrator | `scripts/run-scheduled.ts` | 🔄 `runAiFiction` — vault sync, idempotency, Gemini call, write-back |

### 🔄 Data Flow

```
⏰ Scheduler (hour 22+ Pacific)
         ↓
🎛️ runAiFiction()
         ↓
📥 Pull Obsidian vault via syncObsidianVault()
         ↓
📄 Read today's reflection note (reflections/YYYY-MM-DD.md)
         ↓
🛡️ reflectionNeedsFiction(content) → skip if ## 🤖🐲 AI Fiction exists
         ↓
🧹 stripForPrompt(content) → remove frontmatter + embed sections
         ↓
🧠 buildFictionPrompt(strippedContent) → structured Gemini prompt
         ↓
🤖 generateFiction(apiKey, models, prompt) → call Gemini with model chain
         ↓
📋 parseFictionResponse(raw) → clean and validate response
         ↓
📝 applyFiction(content, fiction) → insert section before embeds/updates
         ↓
💾 Write updated reflection + push vault
```

## ⏰ Schedule

- **Hour**: 22 Pacific (10 PM PST / PDT)
- **Semantics**: At-or-after — eligible at hour 22 and all subsequent hours until 11:59 PM Pacific
- **Ordering**: Runs BEFORE `reflection-title` in the same hour 22 slot
- **Idempotency**: Skips if `## 🤖🐲 AI Fiction` section already exists in today's reflection

## ✍️ Fiction Rules

📝 The generated fiction passage follows strict formatting rules:

| 📏 Rule | 📝 Detail |
|---|---|
| 🎯 Each sentence starts with an emoji | 🌟 The emoji reflects the sentence's mood or theme |
| 🚫 No quotation marks | ❌ Neither single nor double quotes allowed |
| 📐 Under 100 words | 🧮 The entire fiction passage must be concise |
| 🌀 Themes abstracted from content | 🧠 Inspired by the day's reflection, not a literal summary |

## 🧹 Content Stripping

📄 Before sending the reflection to Gemini, the `stripForPrompt` function removes:
- 📋 YAML frontmatter (between `---` delimiters)
- 🐦 Embed sections: `## 🐦 Tweet`, `## 🦋 Bluesky`, `## 🐘 Mastodon`
- 🔄 Updates section: `## 🔄 Updates`

🎯 This focuses the model on meaningful content — readings, notes, and links — rather than metadata or social media embeds.

## 📍 Section Placement

📌 The `## 🤖🐲 AI Fiction` section is placed:
- ⬆️ **Before** embed sections (`## 🐦 Tweet`, `## 🦋 Bluesky`, `## 🐘 Mastodon`)
- ⬆️ **Before** the updates section (`## 🔄 Updates`)
- ⬇️ **After** all substantive content sections (books, blog posts, videos, etc.)

🔄 This ensures fiction is visible as authored content, not buried under embeds.

## 🤖 Model Configuration

- **Default model chain**: `gemini-2.5-flash` → `gemini-2.5-flash-lite` → `gemini-3.1-flash-lite-preview`
- **Environment override**: `FICTION_MODEL` prepends a model to the chain when set
- **Retry**: Exponential backoff (2s, 4s, 8s) on 5XX/429 errors, up to 3 retries per model
- **Fallback**: On definitive failure, proceeds to the next model in the chain

## 🔧 Key Functions

### 🧊 Pure Functions (No I/O)

| 🔧 Function | 📝 Purpose |
|---|---|
| `stripForPrompt(content)` | 🧹 Remove frontmatter and embed/updates sections from reflection content |
| `reflectionNeedsFiction(content)` | 🛡️ Idempotency check — returns false if `## 🤖🐲 AI Fiction` already exists |
| `buildFictionPrompt(strippedContent)` | 🧠 Construct structured Gemini prompt with fiction rules and themes |
| `parseFictionResponse(raw)` | 📋 Clean raw model response — strip fences, validate constraints |
| `applyFiction(content, fiction)` | 📝 Insert `## 🤖🐲 AI Fiction` section at the correct position |

### 💾 I/O Functions

| 🔧 Function | 📝 Purpose |
|---|---|
| `generateFiction(apiKey, models, prompt)` | 🤖 Call Gemini with model chain, retry, and fallback |

### 🎛️ Orchestrator

| 🔧 Function | 📝 Purpose |
|---|---|
| `runAiFiction()` | 🔄 End-to-end: pull vault → check idempotency → generate → apply → push vault |

## 🛡️ Idempotency

✅ All operations are idempotent:
- 📌 `reflectionNeedsFiction` checks for the presence of `## 🤖🐲 AI Fiction` heading
- 🔄 Re-running after fiction is already inserted produces no changes
- 🚫 No duplicate fiction sections are ever created

## 🧪 Testing

🔬 Tests in `scripts/lib/ai-fiction.test.ts` covering:
- 🧹 `stripForPrompt`: frontmatter removal, embed section removal, updates section removal, content preservation
- 🛡️ `reflectionNeedsFiction`: detection of existing fiction section, fresh reflections
- 🧠 `buildFictionPrompt`: prompt structure, fiction rules inclusion, content forwarding
- 📋 `parseFictionResponse`: code fence stripping, whitespace normalization
- 📝 `applyFiction`: section placement before embeds, placement before updates, end-of-file placement, idempotency
