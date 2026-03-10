# Frontmatter Path Timestamps: Enveloppe Trail for Obsidian Mobile Publishing

## Problem

When the auto-posting pipeline posts a note to social media and updates it with embed
sections, the modified file may be several hops away from the daily reflection in the
content graph. For example:

```
reflection (today) → reflection (3 days ago) → book (posted & updated)
```

The [Enveloppe](https://github.com/Enveloppe/obsidian-enveloppe) plugin — used to
publish content from Obsidian mobile — discovers changed files using a breadth-first
search strategy similar to our own. It starts from the note you explicitly publish and
follows links to find other changed files. If intermediate files haven't been modified,
Enveloppe won't follow the trail and the posted note (with its new social media embeds)
won't be published.

Manually identifying and publishing all intermediate files from Obsidian mobile is
tedious and error-prone.

## Solution: Updated Frontmatter Trail

After posting a note to social media, update the `updated` property in the YAML
frontmatter of every file along the shortest BFS path from the daily reflection to
the posted note. This creates a breadcrumb trail of modified files that Enveloppe
will follow.

### Example

Given this content graph where `books/deep-book.md` was just posted:

```
reflections/2026-03-10.md → reflections/2026-03-09.md → reflections/2026-03-08.md → books/deep-book.md
```

The pipeline updates the `updated` field in all four files:

```yaml
# reflections/2026-03-10.md
---
updated: 2026-03-10T00:01:08.852Z
---

# reflections/2026-03-09.md
---
updated: 2026-03-10T00:01:08.852Z
---

# reflections/2026-03-08.md
---
updated: 2026-03-10T00:01:08.852Z
---

# books/deep-book.md
---
updated: 2026-03-10T00:01:08.852Z
---
```

Now when the user publishes `reflections/2026-03-10.md` from Obsidian mobile,
Enveloppe's BFS follows the trail of recently-modified files all the way to
`books/deep-book.md`.

## Architecture

### BFS Path Tracking

The existing `bfsContentDiscovery()` function was extended with parent pointer
tracking — the standard technique for finding shortest paths in unweighted graphs.

```
BFS State:
  visited: Set<string>         — prevents revisiting nodes
  queue: string[]              — BFS frontier
  parentMap: Map<string, string | null>  — NEW: maps each node to its BFS parent
```

When a node is first discovered (added to the queue), its parent is recorded in
`parentMap`. The root node has a parent of `null`.

### Path Reconstruction

`reconstructPath(target, parentMap)` walks the parent chain from the target back
to the root, building the shortest path:

```
parentMap: { root → null, A → root, B → A, target → B }
reconstructPath("target") → ["root", "A", "B", "target"]
```

### Frontmatter Update

`updateFrontmatterTimestamp(filePath, timestamp)` modifies the YAML frontmatter:

- If `updated:` exists → replaces the value
- If frontmatter exists but no `updated:` → inserts before the closing `---`
- If no frontmatter → adds a minimal `---\nupdated: ...\n---` block

### Integration in auto-post.ts

Before posting, `auto-post.ts` calls `updatePathTimestamps()` with the longest
path from the grouped content items. This ensures all intermediate files have
their timestamps set **before** `main()` pushes the vault:

```typescript
// Update timestamps along the BFS path BEFORE posting
const longestPath = items.reduce(...);
updatePathTimestamps(longestPath, vaultDir);

await main({ note: notePath, vaultDir });
```

The timestamps must be written before `main()` because `main()` pushes the
vault to Obsidian Sync after writing embed sections. If timestamps were set
after the push, they would only exist locally and never reach Obsidian.

## Data Flow

```
auto-post.ts
  ├─ Pull Obsidian vault (once)
  ├─ BFS content discovery (tracks parent pointers)  ← NEW
  │   └─ Returns ContentToPost[] with pathFromRoot    ← NEW
  ├─ For each note to post:
  │   ├─ updatePathTimestamps() — touch intermediates ← NEW (must be BEFORE push)
  │   └─ main() — post to social, write embeds, push vault
  └─ Done
```

## New Functions

| Function | Module | Purpose |
|----------|--------|---------|
| `reconstructPath()` | find-content-to-post.ts | Walk parent pointers to build shortest path |
| `updateFrontmatterTimestamp()` | find-content-to-post.ts | Update `updated` field in one file's frontmatter |
| `updatePathTimestamps()` | find-content-to-post.ts | Update timestamps for all files along a path |

## Testing

18 new tests added (259 total, all passing):

| Category | Tests | What It Validates |
|----------|-------|-------------------|
| `reconstructPath` | 4 | Root-only, 2-hop, multi-hop, missing target |
| `updateFrontmatterTimestamp` | 5 | Add, replace, create frontmatter, non-existent file, body preservation |
| `updatePathTimestamps` | 2 | Multi-file update, skip missing files |
| BFS path tracking integration | 4 | 1-hop, 3-hop, root-only, diamond (shortest path) |
| `discoverContentToPost` path | 1 | Prior-day reflection has single-element path |

## Design Decisions

### Why shortest path?

BFS guarantees shortest path in unweighted graphs. This minimizes the number of
intermediate files that need their timestamps updated, which:

1. Reduces unnecessary file modifications
2. Creates the most direct trail for Enveloppe to follow
3. Avoids touching files that aren't relevant to the posted content

### Why update all files on the path?

Enveloppe's BFS starts from the explicitly published note and follows links to
find changed files. If any file on the path is unchanged, Enveloppe won't traverse
past it. Updating all files ensures the trail is unbroken.

### Why use the `updated` frontmatter field?

This field is already used by index pages in the vault (e.g., `books/index.md`).
Reusing it means:

1. No new fields or conventions to introduce
2. Quartz (the site generator) already understands `updated` for display purposes
3. The semantic meaning ("this file was last modified at this time") is accurate

### Why not update the file's filesystem mtime instead?

Enveloppe checks frontmatter fields, not filesystem timestamps. The `updated`
frontmatter field is the standard Obsidian convention for tracking modification time.
