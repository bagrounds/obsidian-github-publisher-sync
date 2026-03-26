# Reflection Title Generation

## Overview

The **reflection-title** task automatically generates creative, emoji-enriched
titles for daily reflection notes in the Obsidian vault. It runs at or after
10 PM Pacific time each day, after all blog posts and content have been added
to the daily reflection.

## Architecture

| Component | Path |
|-----------|------|
| Library | `scripts/lib/reflection-title.ts` |
| Tests | `scripts/lib/reflection-title.test.ts` |
| Scheduler entry | `scripts/lib/scheduler.ts` (`reflection-title`, hour 22 Pacific) |
| Orchestrator runner | `scripts/run-scheduled.ts` (`runReflectionTitle`) |

## Schedule

- **Hour**: 22 Pacific (10 PM PST / PDT)
- **Semantics**: At-or-after — eligible at hour 22 and all subsequent hours
  (in Pacific time) until 11:59 PM Pacific
- **Catchup**: Also titles yesterday's reflection if it's still untitled
- **Idempotency**: Skips if the title field already contains a creative title
  (i.e., anything beyond the bare date)

## Title Format

Titles follow a creative game observed across 20+ existing reflection notes:

```
YYYY-MM-DD | 🕊️ Gentle 🚪 Constraint 🏛️ Commons 📚🐔🤖🏛️📺
```

### The "One Word Per Title" Game

1. **Extract linked content titles** — deterministically pull titles of books,
   blog posts, videos, etc. from list items in the reflection note
2. **Strip prefixes** — remove date prefixes and emoji prefixes from titles
3. **AI picks one word per title** — Gemini selects exactly one interesting word
   from each content title and forms a coherent phrase
4. **Emoji insertion** — each meaningful word gets 1–2 relevant emojis
5. **Trailing category emojis** — deterministically extracted from section
   heading emojis in the note

### Category Emojis (Deterministic)

Leading emojis from each H2 heading are extracted and appended. For example:
- `## [📚 Books](...)` → 📚
- `## [🐔 Chickie Loo](...)` → 🐔
- `## 🤖🐲 AI Fiction` → 🤖🐲

## Data Flow

1. Pull Obsidian vault via `syncObsidianVault()`
2. Read today's reflection note (`reflections/YYYY-MM-DD.md`)
3. Check idempotency: skip if title already set (not just the date)
4. If today is skipped, also check yesterday's reflection
5. **Deterministic prep:**
   a. Extract linked content titles from list items
   b. Extract trailing emojis from section headings
6. Collect up to 20 recent creative titles as style examples
7. Build focused Gemini prompt: "pick one word per title"
8. Call Gemini with model chain (retry + fallback)
9. Parse response, append deterministic trailing emojis
10. Apply title to frontmatter (`title`, `aliases`) and H1 heading
11. Write updated content and push vault

## Model Configuration

- **Default model chain**: `gemini-3.1-flash-lite-preview` → `gemini-2.5-flash` →
  `gemini-2.5-flash-lite` (best model first)
- **Environment override**: `REFLECTION_TITLE_MODEL` prepends a model to the
  chain
- **Retry**: Reuses `isRetriableError` from `generate-blog-post.ts` for
  exponential backoff (2s, 4s, 8s) on 5XX/429 errors, up to 3 retries per model

## Social Media Safety Gate

Reflection notes are blocked from social media posting until they have a
creative title. The `isUntitledReflection()` function in
`find-content-to-post.ts` returns true when a reflection's title is just
the bare date (e.g., `2026-03-24`), causing:
- `isPostableContent()` to return false
- `getPriorDayReflectionIfNeeded()` to skip untitled reflections

## Frontmatter Updates

The task updates three locations in the reflection note:

1. `title:` frontmatter field → `YYYY-MM-DD | <creative title>`
2. `aliases:` frontmatter array → `[YYYY-MM-DD | <creative title>]`
3. `# YYYY-MM-DD` H1 heading → `# YYYY-MM-DD | <creative title>`

## Pure Functions (no I/O)

| Function | Purpose |
|----------|---------|
| `extractLinkedTitles(content)` | Extract content titles from list items |
| `extractTrailingEmojis(content)` | Extract category emojis from section headings |
| `extractHeadingEmojis(heading)` | Extract leading emojis from one heading line |
| `stripTitlePrefixes(title)` | Remove date and emoji prefixes |
| `reflectionNeedsTitle(content, date)` | Idempotency check |
| `buildReflectionTitlePrompt(titles, examples)` | Gemini prompt construction |
| `parseReflectionTitle(raw)` | Clean raw model response |
| `applyReflectionTitle(content, date, title)` | Apply title to note |

## I/O Functions

| Function | Purpose |
|----------|---------|
| `generateReflectionTitle(config)` | End-to-end: extract → prompt → Gemini → parse → apply |
| `callGeminiModelChain(apiKey, models, prompt)` | Gemini API with retry and model fallback |

## Tests

54 tests across 9 suites covering:

- `extractHeadingEmojis`: Wiki links, markdown links, plain headings, no-emoji headings
- `extractTrailingEmojis`: Multi-heading extraction, deduplication
- `stripTitlePrefixes`: Emoji stripping, date stripping, combined, plain text
- `extractLinkedTitles`: Wiki links, markdown links, heading exclusion, date prefix stripping
- `reflectionNeedsTitle`: Date-only detection, titled detection, edge cases
- `buildReflectionTitlePrompt`: One-word-per-title instructions, examples inclusion, numbering
- `parseReflectionTitle`: Code fence stripping, quote removal, date prefix handling
- `applyReflectionTitle`: Frontmatter updates, H1 replacement, content preservation, idempotency
- Integration: needsTitle → applyTitle → no longer needsTitle
