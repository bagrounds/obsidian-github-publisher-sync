# Text-to-Speech (TTS) Audio Player

A browser-native Text-to-Speech player embedded on every page, powered by the
[Web Speech API](https://developer.mozilla.org/en-US/docs/Web/API/SpeechSynthesis)
(`SpeechSynthesis`). Zero external dependencies, free, no ads.

## Features

### Player Controls
| Control | Description |
|---------|-------------|
| **Play / Pause** | Start or pause reading. Uses `synth.cancel()` for reliable cross-utterance pausing. |
| **Skip ±30 s** | Jump forward or backward approximately 30 seconds (estimated via word counts). |
| **Speed selector** | Choose 0.5×, 0.75×, 1×, 1.25×, 1.5×, 1.75×, or 2× playback rate. |
| **Seek bar** | Drag to jump to any point in the article. Shows elapsed and total estimated time. |

### Always-Fixed Collapsible Player
The player is permanently fixed at the bottom-right corner of the viewport.
A small **🔊 toggle tab** sits above the player panel. Tapping the tab slides
the player panel down out of view; tapping again brings it back. When collapsed,
only the tab remains visible at the bottom-right corner. If a `FixedFooter`
element is present on the page, the player positions itself above it automatically.

### Text Extraction
The player reads only the `<article>` content. The following are stripped:

- **Navigation & chrome** — `nav`, `header`, `footer`, `.sidebar`, `.backlinks`,
  `.graph`, `.toc`, `.explorer`, `.search`, `button`
- **Code & technical blocks** — `pre`, `script`, `style`, `code` (inline)
- **Visual-only content** — `svg`, `.katex`, `.mermaid`, `.external-icon`
- **The TTS player itself** — `.tts-container`

Within each block element, the player clones the node (to avoid mutating the
live DOM), removes inline junk selectors, then runs the text through `cleanText()`.

### Emoji Stripping
All emoji are removed before the synthesiser reads the text. This avoids the
browser vocalising emoji names (e.g. "house with garden" for 🏡). The
`stripEmojis()` function targets:

| Category | Unicode Range | Example |
|----------|---------------|---------|
| Extended pictographics | `\p{Extended_Pictographic}` | 😀 🌍 🏡 |
| Variation selectors | U+FE00–U+FE0F | ⭐︎ → ⭐️ |
| Zero-width joiners | U+200D | 👨‍👩‍👧‍👦 family sequences |
| Skin-tone modifiers | U+1F3FB–U+1F3FF | 👋🏽 medium skin tone |
| Regional indicators | U+1F1E0–U+1F1FF | 🇺🇸 flags |
| Tag characters | U+E0020–U+E007F | 🏴󠁧󠁢󠁥󠁮󠁧󠁿 subdivision flags |
| Keycap combining | U+20E3 | 1️⃣ keycap digits |

### Sentence Highlighting & Autoscroll
Text extraction is **block-aware**: the player walks the article's block-level
elements (`<p>`, `<li>`, `<h1>`–`<h6>`, `<td>`, `<th>`, `<dd>`, `<dt>`,
`<figcaption>`, `<summary>`) and maps each sentence back to the DOM element
that contains it.

During playback:
1. The current block element receives a `.tts-highlight` CSS class (a subtle
   background-colour change using the Quartz `--highlight` variable).
2. `scrollIntoView({ behavior: 'smooth', block: 'center' })` keeps the
   highlighted element centred in the viewport.
3. When the reader advances to the next sentence in a different block, the
   previous highlight is removed and the new one is applied.

### Deduplication of Nested Blocks
Parent block elements that contain nested block children are automatically
skipped. For example, an `<li>` wrapping a `<p>` would otherwise read the
same text twice — the `<li>`'s full text and then the `<p>`'s identical text.
The player detects this with `el.querySelector(BLOCK_SELECTORS)` and only
reads the innermost leaf blocks.

### Speed Persistence
When navigating between pages in the SPA, the speed `<select>` element's DOM
value is preserved by the framework. On each `nav` event, the player reads
the current value of the selector (`Number(speedSel.value)`) instead of
resetting to 1×.

### Speed Change Behaviour
Changing speed mid-playback does **not** restart the current sentence. The
`SpeechSynthesisUtterance.rate` property is set per-utterance and cannot be
modified after an utterance has begun speaking. The new rate is stored and
applied to the next utterance when the current one finishes. This avoids the
jarring "backward jump" that would occur if the player cancelled and restarted
from the same sentence index.

## Architecture

### Files

| File | Role |
|------|------|
| `quartz/components/TextToSpeech.tsx` | Preact component rendering the player HTML. Registered in both content and list page layouts via `quartz.layout.ts`. |
| `quartz/components/scripts/tts.inline.ts` | Client-side player logic. Runs on every SPA navigation (`nav` event). Handles text extraction, speech synthesis, highlighting, autoscroll, seek, speed, and toggle. Cleans up via `addCleanup`. |
| `quartz/components/scripts/tts.utils.ts` | Pure utility functions (no DOM dependency). Includes `stripEmojis`, `cleanText`, `splitIntoSentences`, `wordCount`, `estimateDuration`, `formatTime`, `buildCumulativeWords`, `sentenceIndexForTime`, and selector constants. |
| `quartz/components/scripts/tts.test.ts` | Unit and property-based tests for all utility functions. |
| `quartz/components/styles/tts.scss` | Styles for the player wrapper, tab, container, controls, and sentence highlight. Uses Quartz CSS variables for theming. |

### Data Flow

```
nav event
  → extractArticleBlocks()     // walk <article> block elements, clone + clean
  → splitIntoSentences()       // split cleaned text into sentence chunks
  → buildSentenceBlockMap()    // map each sentence → its source DOM block
  → buildCumulativeWords()     // prefix-sum word counts for time estimation
  → prepare()                  // compute totalDuration, display total time

Play
  → speakFrom(idx)             // cancel any current speech, start from sentence idx
    → speakCurrent()           // create SpeechSynthesisUtterance for current sentence
      → utterance.onend        // advance to next sentence, update highlight
  → highlightCurrentSentence() // add .tts-highlight class, scrollIntoView
  → startTick()                // setInterval to update seek bar every 250 ms
```

### Time Estimation
The player uses a word-count heuristic to estimate playback position:
- **AVG_WPM** = 150 (average words per minute)
- **WPS** = AVG_WPM / 60 = 2.5 (words per second at 1× speed)
- `estimateDuration(words, rate) = words / (WPS × rate)`

This is necessarily approximate since `SpeechSynthesis` does not expose a
reliable elapsed-time or progress callback. The seek bar interpolates within
the current sentence using wall-clock time.

## Tests

The test suite (`tts.test.ts`) contains **100 tests** across 17 describe blocks:

### Unit Tests (83 tests)
- **Constants** — `AVG_WPM`, `WPS`, selector arrays
- **stripEmojis** — common emoji, ZWJ sequences, skin tones, flags, keycaps, variation selectors
- **splitIntoSentences** — periods, exclamation/question marks, ellipsis, trailing text, long input, empty strings
- **wordCount** — empty, single, multiple, whitespace-only
- **estimateDuration** — zero words, rate scaling, fractional counts
- **formatTime** — zero, sub-minute, exact minutes, mixed, fractional, negative, NaN, Infinity
- **buildCumulativeWords** — empty, single, accumulation, zeros
- **sentenceIndexForTime** — boundaries, middle, end, beyond-end, rate, empty, single
- **cleanText** — whitespace collapsing, markdown stripping, emoji removal, mixed content
- **Integration** — full pipeline, speed scaling, seek consistency, emoji-heavy text

### Property-Based Tests (17 tests)
Randomised inputs over 50 iterations per test to verify invariants:
- **stripEmojis** — never increases length, preserves ASCII, no pictographic in output
- **splitIntoSentences** — no lost words, no empty strings
- **wordCount** — non-negative, single word = 1
- **estimateDuration + formatTime** — non-negative duration, m:ss format, rate halving
- **buildCumulativeWords** — length preserved, monotonically non-decreasing, last = sum
- **sentenceIndexForTime** — valid index, monotonic with time
- **cleanText** — never increases length, strips markdown characters

## Browser Compatibility

The Web Speech API is supported in all modern browsers (Chrome, Edge, Safari,
Firefox). If `speechSynthesis` is not available, the player hides itself.

## Deployment Note

The `deploy.yml` workflow temporarily includes this feature branch for live
mobile testing. The branch reference should be removed on merge to main.
