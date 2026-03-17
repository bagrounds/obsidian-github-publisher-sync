# Stripping Noise from the LLM Context Window

When an AI blog writes its next post, it reads its own previous posts for context.
But those posts accumulate metadata that the LLM doesn't need: social media embeds
appended after publication. Every token spent on `<blockquote>` tweet embeds or
`<iframe>` Mastodon widgets is a token *not* spent understanding the actual content.

## The Problem

The auto-blog pipeline reads previous posts via `readSeriesPosts`, which parses each
markdown file into a `BlogPost` with separate `frontmatter` and `body` fields. YAML
frontmatter was already stripped at parse time — `parseFrontmatter()` handles that
cleanly. But social media embed sections — appended by `appendTweetSection`,
`appendBlueskySection`, and `appendMastodonSection` after publication — remained in
the body and flowed straight into the LLM prompt.

## The Fix

A pure function, `stripEmbedSections`, finds the earliest occurrence of any embed
section header (`## 🐦 Tweet`, `## 🦋 Bluesky`, `## 🐘 Mastodon`) and truncates
everything from that point forward. It's applied inside `formatFullPost`, the
function that shapes each previous post for the LLM context window.

The implementation is a single `reduce` over header positions — a functional fold
that finds the minimum index without mutation:

```typescript
const EMBED_HEADERS = [TWEET_SECTION_HEADER, BLUESKY_SECTION_HEADER, MASTODON_SECTION_HEADER] as const;

export const stripEmbedSections = (body: string): string => {
  const firstEmbedIndex = EMBED_HEADERS
    .map((header) => body.indexOf(header))
    .filter((index) => index >= 0)
    .reduce((min, index) => Math.min(min, index), body.length);
  return body.slice(0, firstEmbedIndex).trimEnd();
};
```

The embed headers are already defined as constants in `types.ts` for the embed
section builders. Reusing them here means the stripping logic stays in sync with
the appending logic — a single source of truth.

## What Changed

- **`blog-prompt.ts`**: Added `stripEmbedSections` and applied it in `formatFullPost`
- **`blog-series.ts`**: Re-exported `stripEmbedSections` through the barrel
- **`blog-series.test.ts`**: Eight new tests covering individual platform stripping,
  multi-platform stripping, empty body, content preservation, and end-to-end prompt
  verification

## Design Notes

- The stripping happens at prompt construction time, not at parse time. The
  `BlogPost.body` field retains the full content — only the LLM sees the cleaned
  version. This keeps the data model honest.
- YAML frontmatter was already stripped by `parseFrontmatter()`. No change needed
  there.
- The function is pure — no I/O, no mutation, easy to test and reason about.
