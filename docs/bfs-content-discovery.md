# BFS Content Discovery & Auto-Posting

## Overview

Extension of the social media auto-posting pipeline to support posting
**any published note** — not just daily reflections — to Twitter, Bluesky,
and Mastodon. Uses breadth-first search (BFS) across markdown links to
discover content that hasn't been posted yet.

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│  GitHub Actions (every 2 hours)                                  │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  auto-post.ts (orchestrator)                                     │
│  ┌──────────────────────────────────────┐                        │
│  │ 1. Check configured platforms        │                        │
│  │ 2. Is it past 9 AM Pacific?          │                        │
│  │    YES → Prior day reflection first  │                        │
│  │    NO  → Skip to BFS                 │                        │
│  │ 3. BFS content discovery             │                        │
│  │    Start: most recent reflection     │                        │
│  │    Follow: markdown links            │                        │
│  │    Skip: index pages, home page      │                        │
│  │    Find: 1 unposted note/platform   │                        │
│  │ 4. Post each note via main()         │                        │
│  └──────────────────────────────────────┘                        │
│                                                                  │
│  find-content-to-post.ts (BFS module)                            │
│  ┌──────────────────────────────────────┐                        │
│  │ • Parse markdown links               │                        │
│  │ • Detect posted platforms            │                        │
│  │ • BFS traversal                      │                        │
│  │ • Content filtering                  │                        │
│  └──────────────────────────────────────┘                        │
│                                                                  │
│  tweet-reflection.ts (posting pipeline)                          │
│  ┌──────────────────────────────────────┐                        │
│  │ • Read note (by date or path)        │                        │
│  │ • Generate post text via Gemini      │                        │
│  │ • Post to social platforms           │                        │
│  │ • Fetch/generate embeds              │                        │
│  │ • Write embeds to Obsidian vault     │                        │
│  └──────────────────────────────────────┘                        │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

## Modules

### `scripts/find-content-to-post.ts`

Pure BFS content discovery module. Key exports:

| Function | Description |
|---|---|
| `discoverContentToPost(config, isPastPostingHour)` | Main entry point — returns content to post |
| `bfsContentDiscovery(config)` | BFS across linked notes |
| `getPriorDayReflectionIfNeeded(config)` | Check if yesterday's reflection needs posting |
| `readContentNote(path, contentDir)` | Read and parse any content note |
| `extractMarkdownLinks(body, notePath, contentDir)` | Parse `[text](path.md)` links |
| `detectPostedPlatforms(content)` | Check for `## 🐦 Tweet` etc. sections |
| `isPostableContent(note)` | Filter out index pages and short notes |
| `findMostRecentReflection(contentDir)` | Find BFS starting point |
| `isPastPostingHourUTC(hour)` | Time-of-day check |

### `scripts/auto-post.ts`

Orchestrator script — entry point for scheduled runs:

1. Reads configured platforms from environment
2. Calls `discoverContentToPost()` to find what to post
3. Groups results by note (one `main()` call per unique note)
4. Delegates posting to `tweet-reflection.ts` via `main()`

### `scripts/tweet-reflection.ts` (updated)

New additions:
- `readNote(relativePath, contentDir)` — read any content file, not just reflections
- `--note <path>` CLI argument — post a specific note
- `main({ note })` option — pass note path programmatically

## Content Discovery Strategy

### Priority 1: Prior Day's Reflection

If the current UTC hour is past the posting hour (default: 17 = 9 AM PST),
and yesterday's reflection hasn't been posted to all configured platforms,
post that first.

### Priority 2: BFS Content Discovery

Starting from the most recent reflection:
1. Parse all markdown links (`[text](../path/to/file.md)`)
2. Add linked notes to the BFS queue
3. For each visited note:
   - Skip if it's an index page (`index.md`) or home page
   - Skip if it has too little content (<50 chars after headers)
   - Check which platforms still need a post
   - If the note is missing an embed for a needed platform, select it
4. Return at most **one note per platform** per run

### Content Exclusions

- `index.md` files (aggregation pages, not standalone content)
- Notes with fewer than 50 characters of content (after stripping headers)
- Notes that already have the relevant platform's embed section

## Workflow Changes

### Schedule

Changed from daily at 5 PM UTC to **every 2 hours**:

```yaml
schedule:
  - cron: "0 */2 * * *"
```

### Manual Dispatch

New `note` input for manual workflow dispatch:

```yaml
workflow_dispatch:
  inputs:
    note:
      description: "Note path relative to content/ (e.g. books/sophies-world.md)"
```

### Script Selection

- **Manual dispatch with `--date` or `--note`**: Runs `tweet-reflection.ts` directly
- **Scheduled run**: Runs `auto-post.ts` orchestrator for BFS discovery

## Testing

### BFS Module Tests (`find-content-to-post.test.ts`)

58 tests covering:
- Frontmatter parsing
- Index/home page detection
- Markdown link extraction
- Platform detection
- Content note reading
- Postable content filtering
- Most recent reflection finding
- Prior day reflection checking
- BFS content discovery
- Content discovery orchestration
- Time-of-day checking
- Property-based tests (50 iterations each)

### Existing Tests (`tweet-reflection.test.ts`)

93 tests (89 original + 4 new `readNote` tests):
- `readNote` reads arbitrary content notes by relative path
- `readNote` returns null for non-existent notes
- `readNote` extracts date from reflection filenames
- `readNote` detects existing social media sections

### Running Tests

```bash
# BFS module tests
npx tsx --test scripts/find-content-to-post.test.ts

# Existing pipeline tests
npx tsx --test scripts/tweet-reflection.test.ts

# All tests
npx tsx --test
```

## References

- [PR #5798 — BFS Content Discovery & Auto-Posting](https://github.com/bagrounds/obsidian-github-publisher-sync/pull/5798)
- [BFS Algorithm — Wikipedia](https://en.wikipedia.org/wiki/Breadth-first_search)
- [GitHub Actions Cron Syntax](https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows#schedule)
