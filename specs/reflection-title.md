# Reflection Title Generation

## Overview

The **reflection-title** task automatically generates creative, emoji-enriched
titles for daily reflection notes in the Obsidian vault. It runs at or after
10 PM Pacific time each day, after all blog posts and content have been added
to the daily reflection.

## Architecture

| Component | Path |
|-----------|------|
| Library | `haskell/src/Automation/ReflectionTitle.hs` |
| Tests | `haskell/test/Automation/ReflectionTitleTest.hs` |
| Scheduler entry | `haskell/src/Automation/Scheduler.hs` (`reflection-title`, hour 22 Pacific) |
| Orchestrator runner | `haskell/app/RunScheduled.hs` (`runReflectionTitle`) |

## Schedule

- **Hour**: 22 Pacific (10 PM PST / PDT)
- **Semantics**: At-or-after — eligible at hour 22 and all subsequent hours
  (in Pacific time) until 11:59 PM Pacific
- **Catchup**: Also titles yesterday's reflection if it's still untitled
- **Idempotency**: Skips if the title field already contains a creative title
  (i.e., anything beyond the bare date)

## Titling Eligibility

🗓️ A reflection note becomes eligible for titling at 10 PM Pacific on the day of the reflection. 📋 The cutoff datetime for any given reflection is computed by `reflectionTitleCutoff`:

```haskell
reflectionTitleCutoff :: Day -> LocalTime
reflectionTitleCutoff reflectionDay = LocalTime reflectionDay (TimeOfDay 22 0 0)
```

🕐 A reflection on day `D` can be titled whenever `currentPacificTime >= reflectionTitleCutoff D`. This keeps the day and time bundled together as a full datetime, rather than comparing a bare time-of-day against an isolated threshold.

## Backfill: Scanning the Last 5 Days

🔄 `runReflectionTitle` does not hard-code a single target date. Instead, it scans the **last 5 calendar days** (relative to today Pacific), computes the cutoff datetime for each, and titles every eligible untitled reflection:

- 📅 Candidate days: today, today minus 1, today minus 2, today minus 3, today minus 4
- ✅ Eligible: `currentPacificTime >= reflectionTitleCutoff candidateDay`
- 🏷️ For each eligible day: if the reflection file exists and lacks a creative title, generate and apply a title

🛡️ This means if the automation system stops running for several days, any untitled reflections that have passed their 10 PM cutoff will be backfilled automatically on the next run. The "is it time yet?" question is always answered by comparing two full datetimes.

## Title Format

Titles follow a creative game observed across 20+ existing reflection notes:

```
YYYY-MM-DD | 🕊️ Gentle 🚪 Constraint 🏛️ Commons 📚🐔🤖🏛️📺
```

### The "One Word Per Title" Game

1. **Extract linked content titles** — deterministically pull titles of books,
   blog posts, videos, etc. from list items in the reflection note, excluding
   list items from the Updates section
2. **Strip prefixes** — remove date prefixes and emoji prefixes from titles
3. **AI structured sentence building** — Gemini follows a multi-step process
   that defers word selection to avoid premature commitment:
   a. Build a full word inventory — label ALL words in ALL titles with parts of speech
   b. Draft 2–3 grammatical sentence templates using only POS labels (no actual words yet)
   c. Fill templates from the full inventory, trying multiple word combinations (one word per title)
   d. Compare candidates and iterate until a coherent, evocative phrase emerges
   e. As a last resort, may skip a title or use two words to preserve coherence
4. **Emoji insertion** — each chosen word gets 1–2 relevant emojis;
   small filler words ("of", "the", "in") do NOT get emojis
5. **Trailing category emojis** — deterministically extracted from section
   heading emojis in the note

### Category Emojis (Deterministic)

Leading emojis from each H2 heading are extracted and appended, excluding
the Updates section heading (`## 🔄 Updates`). For example:
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
7. Build structured Gemini prompt with multi-step sentence-building instructions
8. Call Gemini with model chain (retry + fallback)
9. Parse response: strip code fences, quotes, backticks, preamble, normalize
   emoji spacing, append deterministic trailing emojis
   - **Preamble stripping**: LLMs occasionally prepend conversational text
     (e.g., "Here's an attempt:") before the title. The parser handles this
     by preferring lines that start with an emoji character. For single-line
     responses with inline preamble, it finds the first emoji and discards
     everything before it.
10. Apply title to frontmatter (`title`, `aliases`) and H1 heading
11. Write updated content and push vault

## Model Configuration

- **Default model chain**: `gemini-2.5-flash` → `gemini-2.5-flash-lite` →
  `gemini-3.1-flash-lite-preview` (thinking model first for structured reasoning)
- **Environment override**: `REFLECTION_TITLE_MODEL` prepends a model to the
  chain
- **Retry**: Reuses `isRetriableError` from `Automation.Retry` for
  exponential backoff (2s, 4s, 8s) on 5XX/429 errors, up to 3 retries per model

## Social Media Safety Gate

Reflection notes are blocked from social media posting until they have a
creative title. The `isUntitledReflection()` function in
`Automation.SocialPosting` returns true when a reflection's title is just
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
| `extractLinkedTitles(content)` | Extract content titles from list items (excludes Updates section) |
| `extractTrailingEmojis(content)` | Extract category emojis from section headings (excludes Updates section) |
| `extractHeadingEmojis(heading)` | Extract leading emojis from one heading line |
| `stripTitlePrefixes(title)` | Remove date and emoji prefixes |
| `reflectionNeedsTitle(content, date)` | Idempotency check |
| `reflectionTitleCutoff(reflectionDay)` | Return the earliest `LocalTime` at which a reflection for `reflectionDay` is eligible to be titled (i.e., `reflectionDay @ 22:00:00`) |
| `buildReflectionTitlePrompt(titles, examples)` | Gemini prompt construction |
| `parseReflectionTitle(raw)` | Clean raw model response |
| `applyReflectionTitle(content, date, title)` | Apply title to note |

## I/O Functions

| Function | Purpose |
|----------|---------|
| `generateReflectionTitle(config)` | End-to-end: extract → prompt → Gemini → parse → apply |
| `callGeminiModelChain(apiKey, models, prompt)` | Gemini API with retry and model fallback |

## Tests

64 tests across 10 suites covering:

- `extractHeadingEmojis`: Wiki links, markdown links, plain headings, no-emoji headings
- `extractTrailingEmojis`: Multi-heading extraction, deduplication
- `stripTitlePrefixes`: Emoji stripping, date stripping, combined, plain text
- `extractLinkedTitles`: Wiki links, markdown links, heading exclusion, date prefix stripping
- `reflectionNeedsTitle`: Date-only detection, titled detection, edge cases
- `reflectionTitleCutoff`: returns `LocalTime day (TimeOfDay 22 0 0)` for a given `Day`; eligibility tests verify correct comparison semantics (at/after 10 PM eligible, before not, next day noon eligible, same day noon not)
- `buildReflectionTitlePrompt`: One-word-per-title instructions, examples inclusion, numbering
- `parseReflectionTitle`: Code fence stripping, quote removal, date prefix handling, backtick
  stripping, emoji spacing normalization, preamble stripping (single-line, multi-line, thinking output)
- `applyReflectionTitle`: Frontmatter updates, H1 replacement, content preservation, idempotency
- Integration: needsTitle → applyTitle → no longer needsTitle
