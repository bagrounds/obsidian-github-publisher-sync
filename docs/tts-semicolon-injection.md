# TTS Semicolon Injection for Natural Pauses

## Problem

The Web Speech API's `SpeechSynthesisUtterance` reads text as a continuous
stream.  When the TTS player joins block-level text elements (headings, list
items, table cells) with spaces, the synthesiser runs them together without
pause.  This makes the output sound unnatural — headings blend into body
text, and list items blur into a single run-on sentence.

## Solution

A new pure utility function, **`injectBlockPauses(text)`**, appends a
semicolon (`;`) to any block's cleaned text that does not already end with
pause-producing punctuation (`.`, `!`, `?`, `;`, `:`).  The semicolon is
a natural speech break: synthesisers treat it as a clause boundary and insert
a brief pause, similar to a comma but slightly longer.

### Why a Semicolon?

| Character | Pause behaviour | Downside |
|-----------|----------------|----------|
| `.` | Full stop — long pause, pitch drop | Changes meaning (headings sound like sentences) |
| `,` | Short pause — sometimes too subtle | Often ignored by synthesisers on short fragments |
| `;` | Medium pause — natural clause break | Slightly unusual in prose, but invisible to the listener |

The semicolon strikes the best balance: it produces a perceptible pause
without altering the perceived sentence structure.

## Architecture

### New Function

**`tts.utils.ts`** — `injectBlockPauses(text: string): string`

```typescript
export function injectBlockPauses(text: string): string {
  if (!text) return text
  if (/[.!?;:]$/.test(text)) return text
  return text + ";"
}
```

Properties:
- **Pure** — no side effects, no DOM dependency
- **Idempotent** — applying twice gives the same result as once
- **Non-destructive** — text that already ends with punctuation is unchanged

### Integration Point

**`tts.inline.ts`** — `extractArticleBlocks()`

```typescript
// Before:
const text = cleanText(clone.textContent ?? "")

// After:
const text = injectBlockPauses(cleanText(clone.textContent ?? ""))
```

The function is applied per-block after `cleanText()` and before blocks are
joined into the full text string.  This means every block-level element
(heading, list item, table cell, paragraph) that lacks terminal punctuation
gets a semicolon before entering the sentence-splitting pipeline.

### Data Flow

```
DOM block element
  → clone + remove inline junk
  → cleanText()           // collapse whitespace, strip markdown/emoji
  → injectBlockPauses()   // append ";" if no terminal punctuation  ← NEW
  → blocks[] array
  → join(" ")
  → splitIntoSentences()
  → SpeechSynthesisUtterance
```

## Tests

18 new tests added to `tts.test.ts`:

### Unit Tests (12)
- Empty input returns empty string
- Plain text gets semicolon appended
- Heading-like text gets semicolon
- Text ending with `.` is unchanged
- Text ending with `!` is unchanged
- Text ending with `?` is unchanged
- Text ending with `;` is unchanged
- Text ending with `:` is unchanged
- List item text gets semicolon
- Text ending with a number gets semicolon
- Text ending with closing parenthesis gets semicolon
- Single word gets semicolon

### Property-Based Tests (4)
- Output length is never less than input length
- Output always ends with pause-producing punctuation
- Function is idempotent (applying twice = applying once)
- Text already ending with punctuation is unchanged

### Integration Tests (2)
- Block pauses are injected before sentence splitting
- Headings and list items get natural breaks while paragraphs are preserved

## Browser Compatibility

No new browser API usage.  The semicolon is injected into plain text before
it reaches `SpeechSynthesisUtterance`.  All browsers that support the Web
Speech API will produce the pause.
