# Platform Post Length Enforcement: Counting Graphemes, Not Characters

*2026-03-09*

## The Bug

Our auto-posting pipeline hit a wall when trying to share a book review on Bluesky:

```
⚠️  Bluesky posting failed (non-fatal):
   Invalid app.bsky.feed.post record: Record/text must not be longer than 300 graphemes
```

The post was about *Attached: The New Science of Adult Attachment and How It Can Help You Find—and Keep—Love*. That's a mouthful of a book title, and its URL slug was even longer:

```
https://bagrounds.org/books/attached-the-new-science-of-adult-attachment-and-how-it-can-help-you-find-and-keep-love
```

At ~113 characters, that URL alone eats more than a third of Bluesky's 300-grapheme budget.

## The Root Cause: Twitter's URL Shortening Illusion

Our pipeline generates a single post and sends it to Twitter, Bluesky, and Mastodon. We validated the text length using Twitter's rules, where *all URLs count as 23 characters* (thanks to t.co shortening). So a post validated at 253 "effective Twitter characters" could actually be 320+ real characters — well over Bluesky's 300-grapheme limit.

The validation was correct for Twitter but blind to Bluesky's reality.

## What Are Graphemes?

This is where it gets interesting. Bluesky doesn't count *characters* or *bytes* or JavaScript's `.length` — it counts **graphemes**: what a human perceives as a single character.

Consider:
- `Hello` — 5 graphemes (same as `.length`)
- `📚` — 1 grapheme (but JavaScript `.length` returns 2)
- `👨‍👩‍👧‍👦` — 1 grapheme (but JavaScript `.length` returns 11!)
- `🇺🇸` — 1 grapheme (`.length` is 4)

Emoji sequences, flag characters, and combining marks make naive character counting unreliable. Modern JavaScript solves this with `Intl.Segmenter`:

```typescript
function countGraphemes(text: string): number {
  const segmenter = new Intl.Segmenter("en", { granularity: "grapheme" });
  let count = 0;
  for (const _ of segmenter.segment(text)) count++;
  return count;
}
```

No external libraries needed — `Intl.Segmenter` has been available since Node.js 16.

## The Solution Space

We brainstormed several approaches:

| Approach | Pros | Cons |
|----------|------|------|
| Generate separate text per platform | Optimized for each | Expensive, complex |
| Simple truncation | Easy | Loses meaning mid-sentence |
| Validate at 280 actual chars | Simple | Wastes Twitter's URL shortening benefit |
| URL shortener | Preserves content | External dependency, link rot |
| **Intelligent per-platform fitting** | **Preserves meaning, robust** | **Slightly more code** |
| Two-pass AI generation | High quality | Extra API calls, latency |

We chose **intelligent per-platform fitting**: validate per platform using correct grapheme counting, and progressively truncate in order of decreasing expendability.

## Progressive Truncation: Preserving What Matters

Our posts follow a consistent structure:

```
2026-03-08 | 📖 Attached 💕 Love 🧠 Science 📚      ← Title (essential)
                                                       ← Blank line
📚 Books | 💕 Relationships | 🧠 Psychology            ← Topic tags (expendable)
https://bagrounds.org/books/attached-...               ← URL (essential)
```

The `fitPostToLimit()` function applies three strategies progressively:

1. **Remove topic tags from right to left** — `🧠 Psychology` goes first, then `💕 Relationships`, etc.
2. **Remove the entire topic line** — if even one tag is too many
3. **Truncate remaining content with "…"** — last resort, preserving the URL

The URL is *always* preserved — it's essential for Bluesky's link card previews and facet detection.

## The Fix in Action

For the book post that triggered the bug:

**Before** (320 graphemes → ❌ rejected):
```
2026-03-08 | 📖 Attached 💕 Love 🧠 Science 📚

📚 Books | 💕 Relationships | 🧠 Psychology | 🔗 Attachment Theory | 🧬 Neuroscience
https://bagrounds.org/books/attached-the-new-science-of-adult-attachment-and-how-it-can-help-you-find-and-keep-love
```

**After** (≤300 graphemes → ✅ accepted):
```
2026-03-08 | 📖 Attached 💕 Love 🧠 Science 📚

📚 Books | 💕 Relationships | 🧠 Psychology
https://bagrounds.org/books/attached-the-new-science-of-adult-attachment-and-how-it-can-help-you-find-and-keep-love
```

Two tags removed, meaning preserved, URL intact.

## Engineering Principles

- **Pure functions**: `countGraphemes()`, `truncateToGraphemeLimit()`, and `fitPostToLimit()` are all pure — no side effects, fully testable
- **Progressive degradation**: Try the least destructive option first
- **No new dependencies**: Uses built-in `Intl.Segmenter` instead of adding a grapheme-splitter library
- **Defense in depth**: AI prompt updated *and* hard truncation as safety net — belt and suspenders
- **Property-based testing**: 50-iteration fuzz tests ensure the output *always* fits the limit, regardless of input

## Lessons Learned

1. **Platform limits are measured differently** — Twitter counts URLs as 23 chars; Bluesky counts full-text graphemes; Mastodon counts characters. A universal validation is a myth.
2. **Graphemes ≠ characters ≠ bytes** — When dealing with emoji-heavy text (and our posts are full of emoji), correct Unicode handling isn't optional.
3. **AI prompts are suggestions, not guarantees** — Telling the AI "keep it under 300" helps, but a hard enforcement layer is essential. Prompts are probabilistic; code is deterministic.
