# Reflection Title Generation

## Overview

The **reflection-title** task automatically generates creative, emoji-enriched
titles for daily reflection notes in the Obsidian vault. It runs at or after
9 PM Pacific time each day, after all blog posts and content have been added
to the daily reflection.

## Architecture

| Component | Path |
|-----------|------|
| Library | `scripts/lib/reflection-title.ts` |
| Tests | `scripts/lib/reflection-title.test.ts` |
| Scheduler entry | `scripts/lib/scheduler.ts` (`reflection-title`, hour 5 UTC) |
| Orchestrator runner | `scripts/run-scheduled.ts` (`runReflectionTitle`) |

## Schedule

- **Hour**: 5 UTC (≈9 PM PST / 10 PM PDT)
- **Semantics**: At-or-after — eligible at hour 5 and all subsequent hours
- **Idempotency**: Skips if the title field already contains a creative title
  (i.e., anything beyond the bare date)

## Title Format

Titles follow the pattern observed across 20+ existing reflection notes:

```
YYYY-MM-DD | 🎨 Keyword1 🔧 Keyword2 ... [category emojis]
```

### Structure

1. **Date prefix**: `YYYY-MM-DD`
2. **Pipe separator**: ` | `
3. **Emoji+keyword pairs**: Each key concept from the day's content gets 1–3
   relevant emojis followed by 1–2 words
4. **Trailing category emojis**: Indicate which content sections appeared

### Category Emojis

| Emoji | Section |
|-------|---------|
| 📚 | Books |
| 🐔 | Chickie Loo |
| 🤖 | Auto Blog Zero |
| 🏛️ | Systems for Public Good |
| 📺 | Videos |
| 📰 | News |
| 📄 | Articles/documents |
| 🎮 | Games |
| 🎤 | Audio/podcasts |
| 💻 | Programming/coding |

## Data Flow

1. Pull Obsidian vault via `syncObsidianVault()`
2. Read today's reflection note (`reflections/YYYY-MM-DD.md`)
3. Check idempotency: skip if title already set (not just the date)
4. Collect up to 20 recent titles from previous reflections for style reference
5. Build Gemini prompt with note content and example titles
6. Call Gemini with model chain (retry + fallback)
7. Parse response, apply title to frontmatter (`title`, `aliases`) and H1 heading
8. Write updated content and push vault

## Model Configuration

- **Default model chain**: `gemini-2.5-flash` → `gemini-2.5-flash-lite` →
  `gemini-3.1-flash-lite-preview`
- **Environment override**: `REFLECTION_TITLE_MODEL` prepends a model to the
  chain
- **Retry**: Exponential backoff (2s, 4s, 8s) on 5XX/429 errors, up to 3
  retries per model

## Frontmatter Updates

The task updates three locations in the reflection note:

1. `title:` frontmatter field → `YYYY-MM-DD | <creative title>`
2. `aliases:` frontmatter array → `[YYYY-MM-DD | <creative title>]`
3. `# YYYY-MM-DD` H1 heading → `# YYYY-MM-DD | <creative title>`

## Pure Functions (no I/O)

| Function | Purpose |
|----------|---------|
| `reflectionNeedsTitle(content, date)` | Idempotency check |
| `buildReflectionTitlePrompt(content, titles)` | Gemini prompt construction |
| `parseReflectionTitle(raw)` | Clean raw model response |
| `applyReflectionTitle(content, date, title)` | Apply title to note |

## I/O Functions

| Function | Purpose |
|----------|---------|
| `generateReflectionTitle(config)` | End-to-end: prompt → Gemini → parse → apply |
| `callGeminiModelChain(apiKey, models, prompt)` | Gemini API with retry and model fallback |

## Tests

37 tests across 5 suites covering:

- `reflectionNeedsTitle`: Date-only detection, titled detection, edge cases
- `buildReflectionTitlePrompt`: Prompt structure, examples inclusion, category emojis
- `parseReflectionTitle`: Code fence stripping, quote removal, date prefix handling
- `applyReflectionTitle`: Frontmatter updates, H1 replacement, content preservation, idempotency
- Integration: needsTitle → applyTitle → no longer needsTitle
