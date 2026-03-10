# Functional Refactoring of the Auto-Posting Pipeline

## Overview

The auto-posting pipeline was refactored from a 2,356-line monolith (`tweet-reflection.ts`) into 16 focused modules under `scripts/lib/`.

## Module Structure

```
scripts/lib/
├── types.ts              Shared types, interfaces, constants
├── text.ts               Pure grapheme/length functions
├── html.ts               HTML escaping, date formatting
├── retry.ts              Generic retry with exponential backoff
├── timer.ts              Pipeline timing instrumentation
├── frontmatter.ts        Frontmatter parsing, note I/O
├── embed-section.ts      Generic section builder (factory pattern)
├── gemini.ts             AI text generation
├── env.ts                Environment validation
├── obsidian-sync.ts      Obsidian Headless Sync operations
├── pipeline.ts           Main pipeline orchestration
└── platforms/
    ├── twitter.ts        Twitter API integration
    ├── bluesky.ts        Bluesky AT Protocol integration
    ├── mastodon.ts       Mastodon REST API integration
    └── og-metadata.ts    OpenGraph metadata fetching
```

## Key Patterns

### Higher-Order Functions
`createSectionBuilder(header)` returns a section-building function, eliminating 3× duplication.

### Pure Functions
`escapeHtml`, `textToHtml`, `formatDisplayDate`, `countGraphemes` — all referentially transparent.

### Declarative Platform Configuration
Platform posting tasks are generated from a declarative configuration array using `filter` and `map`.

### Backward Compatibility
`tweet-reflection.ts` re-exports all public symbols, so existing imports and tests continue to work.

## Testing

- 259 original tests pass unchanged via re-exports
- 102 new tests cover extracted modules directly
- 361 total tests, all passing
