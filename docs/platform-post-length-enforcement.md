# Platform Post Length Enforcement

## Problem

Bluesky rejected a post with the error:

```
Invalid app.bsky.feed.post record: Record/text must not be longer than 300 graphemes
```

The post was for a book note with a long URL:
```
https://bagrounds.org/books/attached-the-new-science-of-adult-attachment-and-how-it-can-help-you-find-and-keep-love
```

## Root Cause

The pipeline generates a single post text for all platforms. The text is validated
against Twitter's 280-character limit using `calculateTweetLength()`, which accounts
for Twitter's t.co URL shortening (all URLs count as 23 characters).

This means a post validated at 280 "effective Twitter characters" can have an actual
grapheme count well above 300 when the URL is long:

| Component           | Twitter length | Actual graphemes |
|---------------------|---------------|-----------------|
| Title + tags text   | ~230          | ~230            |
| Long URL (~90 chars)| 23 (t.co)     | ~90             |
| **Total**           | **~253** ✅   | **~320** ❌     |

## Solution: Per-Platform Length Enforcement

### Approach Considered

| Option | Description | Verdict |
|--------|-------------|---------|
| Per-platform AI generation | Generate separate texts per platform | Over-engineered, expensive |
| Simple truncation | Cut text at limit and add "…" | Loses meaning, poor UX |
| Lowest common denominator | Validate at 280 actual chars (no URL shortening) | Too restrictive for Twitter |
| URL shortener | Use a URL shortener for Bluesky | External dependency, link rot |
| **Intelligent per-platform fitting** | **Validate per platform, progressively truncate** | **✅ Best balance** |
| Two-pass AI generation | Generate, validate, re-generate if too long | Slow, extra API calls |

### Implementation

Three new pure functions:

1. **`countGraphemes(text)`** — Counts Unicode grapheme clusters using `Intl.Segmenter`
   (built into Node.js 16+, no external dependencies). Bluesky's server counts graphemes,
   not JavaScript string length or bytes.

2. **`truncateToGraphemeLimit(text, maxGraphemes)`** — Truncates text to a grapheme limit,
   appending "…" as the last grapheme. Returns unchanged text when within limit.

3. **`fitPostToLimit(text, maxGraphemes)`** — Intelligent post truncation that understands
   the post format (title, topic tags, URL). Applies three progressive strategies:
   - **Strategy 1:** Remove pipe-separated topic tags from right to left
   - **Strategy 2:** Remove the entire topic line (and preceding blank line)
   - **Strategy 3:** Truncate remaining content with "…", preserving the URL

### Integration Points

Before each platform's `post()` call:

```typescript
// Bluesky: enforce 300-grapheme limit
const blueskyText = fitPostToLimit(postText, BLUESKY_MAX_LENGTH);

// Mastodon: enforce 500-char limit (defensive)
const mastodonText = fitPostToLimit(postText, MASTODON_MAX_LENGTH);
```

The Gemini prompt was also updated to mention Bluesky's 300-character limit,
encouraging the AI to generate shorter topic tag lines.

### Why Graphemes?

Bluesky counts **graphemes** (user-perceived characters), not JavaScript `.length`
(UTF-16 code units) or bytes. This matters for emoji:

| Text | `.length` | Graphemes |
|------|-----------|-----------|
| `Hello` | 5 | 5 |
| `📚` | 2 | 1 |
| `👨‍👩‍👧‍👦` | 11 | 1 |
| `🇺🇸` | 4 | 1 |

Using `Intl.Segmenter` with `granularity: 'grapheme'` ensures accurate counting
that matches Bluesky's server-side validation.

## Testing

26 new tests added:
- `countGraphemes`: ASCII, empty, emoji, ZWJ sequences, flags, mixed text
- `truncateToGraphemeLimit`: within limit, at limit, over limit, emoji, edge cases
- `fitPostToLimit`: all strategies exercised, real bug reproduction, property-based
- Property-based: 50-iteration fuzz tests ensuring output always fits the limit
