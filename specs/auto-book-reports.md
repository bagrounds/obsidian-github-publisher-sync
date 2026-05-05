# 📚🤖 Auto-Generate Book Reports

## 🎯 Overview

📚 An automation pipeline that discovers book references in recent content for which we do not yet have a `content/books/<slug>.md` page, then generates a full book report with an Amazon affiliate link and links it into today's daily reflection.

🧱 The pipeline is intentionally **modular** with one Haskell module per concern, and intentionally **conservative** — when any step is uncertain, the candidate is skipped, never silently published.

🚦 The task is **not** auto-scheduled by default. It must be invoked via `cabal run run-scheduled -- --task auto-book-reports` until vetted on real content.

## 🏗️ Module Layout

| 🧩 Module | 📂 Path | 📝 Purpose |
|---|---|---|
| 🔎 Discovery | `Automation.AutoBookReports.Discovery` | Pure: list known book slugs/titles, gather recent reflection bodies |
| 🤖 Identify | `Automation.AutoBookReports.Identify` | Pure: build identification prompt, parse Gemini response into `BookCandidate`s |
| 🛒 AmazonLink | `Automation.AutoBookReports.AmazonLink` | Pure: variant priority, affiliate URL formatting, parse Gemini lookup response |
| 📝 Report | `Automation.AutoBookReports.Report` | Pure: prompt building, frontmatter assembly, slug, body composition |
| 🔗 ReflectionLink | `Automation.AutoBookReports.ReflectionLink` | Pure: insert wikilink into the reflection's `## [📚 Books](../books/index.md)` section |
| 🎼 Orchestrator | `Automation.AutoBookReports` | IO: wires Gemini calls, file IO, and logging |

🧪 Each pure module has its own test suite. The orchestrator delegates all decisions to pure functions so it stays trivial.

## 🔄 Pipeline

```
1. 📂 List existing book slugs from <vault>/books/
2. 📚 Read recent reflection bodies (last N days, N = 7)
3. 🤖 Ask Gemini: "Which book titles are referenced here that are NOT in this list?"
4. 🚦 For each candidate (in order):
   a. 🛒 Look up Amazon ASIN+variant (Gemini + Google Search grounding)
       — if not found, SKIP and move to next candidate
   b. 📝 Generate book report markdown via Gemini
   c. 💾 Write content/books/<slug>.md and sync to vault
   d. 🔗 Add link to the day's reflection's Books section
   e. 🛑 Stop after the first success (per-run limit = 1)
```

## 🧠 Key Design Decisions

### 1. Amazon variant priority
🥇 Order (configurable in `defaultVariantPriority`):
1. Hardcover
2. Paperback
3. Kindle
4. Audible / Audiobook

🤔 *Why this order?* Hardcover is the canonical edition for non-fiction; paperback is a near-equivalent fallback. Kindle and Audible are still genuine purchases with affiliate revenue, but their ASINs change more often.

🔧 *To change:* edit `defaultVariantPriority` in `Automation.AutoBookReports.AmazonLink`.

### 2. Recent content window
🪟 The Discovery module reads the last **7** reflections by date. Configurable via `recentReflectionWindow` constant.

🤔 *Why 7 days?* Short enough to focus on truly recent references, long enough to catch books mentioned over a typical reading session (most reading spans multiple days).

### 3. Affiliate URL form
🔗 The module emits a full Amazon URL: `https://www.amazon.com/dp/<ASIN>?tag=<tag>`.

🚫 *We do not generate `https://amzn.to/...` short links* — those require manual SiteStripe interaction in a logged-in browser session and have no public API.

🏷️ The associates tag is read from the env var `AMAZON_ASSOCIATES_TAG`. If unset, the task fails fast with a clear error before any inference is spent.

### 4. ASIN lookup strategy
🔬 We use Gemini with Google Search grounding to find the ASIN for a `(title, author, variant)` triple. The pure `Automation.AutoBookReports.AmazonLink` module:
- builds the prompt
- parses Gemini's JSON response into `Either Text AmazonResolution`
- exposes a deterministic ASIN-validity regex

🚧 *Limitation:* without an Amazon Product Advertising API key, this lookup is best-effort. False positives (wrong book) and false negatives (cannot find) are both possible. The candidate is **skipped** when ASIN lookup is uncertain.

🔧 *Future option:* swap the resolver for an API-based one by replacing `resolveAmazonLink` in the orchestrator. The pure parsing/formatting code is reusable.

### 5. Per-run limit
🛡️ At most **1** book report is generated per run, mirroring the rate-limit hygiene of `backfill-blog-images` and `internal-linking`. This keeps inference costs predictable and minimizes blast radius if the system misbehaves.

### 6. Why NOT auto-scheduled?
⚠️ Auto-publishing book pages is a high-trust operation: a wrong ASIN means an affiliate link to the wrong product, and a hallucinated book report is worse than no report. Until the pipeline is vetted on real content, the user runs it manually:

```bash
cabal run run-scheduled -- --task auto-book-reports
```

✅ Once confidence is established, add a `ScheduleEntry AutoBookReports [hour] False` to `staticSchedule` in `Automation.Scheduler`.

## 🔧 Configuration

| 🏷️ Knob | 📂 Where | 🌍 Source | 📝 Default |
|---|---|---|---|
| `AMAZON_ASSOCIATES_TAG` | env var | secret | (none — required) |
| `AUTO_BOOK_REPORTS_MODEL` | env var | optional override | `gemini-2.5-flash` |
| `recentReflectionWindow` | `Discovery.hs` | code constant | 7 |
| `defaultVariantPriority` | `AmazonLink.hs` | code constant | Hardcover, Paperback, Kindle, Audible |
| `maxBooksPerRun` | `AutoBookReports.hs` | code constant | 1 |

## 📊 Logging

🔊 Every step emits a plain-text log line with an emoji prefix so the log is greppable and TTS-friendly:

```
▶️  auto-book-reports
  📂 Found 960 existing books in vault
  📚 Read 7 recent reflections
  🤖 Identifying candidate books with gemini-2.5-flash
  🎯 1 candidate(s): Foo Bar by Baz Qux
  🛒 Looking up Amazon link for: Foo Bar
  ✅ Resolved ASIN B0XXXXX (Hardcover)
  📝 Generating book report
  💾 Wrote books/foo-bar.md
  🔗 Linked into 2026-05-05 reflection
  ✅ auto-book-reports — 1 report generated
```

🐛 Every failure path logs a one-line reason explaining why the candidate was skipped, so the user can manually investigate and fix any false skip.

## 🔬 Testing

🧪 Pure-logic unit tests live in `test/Automation/AutoBookReports/`:

| 🧪 Suite | 🎯 What it tests |
|---|---|
| `DiscoveryTest` | Slug enumeration, recent-window filtering, body extraction |
| `IdentifyTest` | Prompt building, JSON response parsing, edge cases (empty/malformed) |
| `AmazonLinkTest` | Variant priority, ASIN regex, affiliate URL formatting, lookup-response parsing |
| `ReportTest` | Frontmatter assembly, slug generation, body composition, prompt building |
| `ReflectionLinkTest` | Insertion idempotency, section creation when absent, ordering |

🚧 **Untestable in CI** (live Gemini + live Amazon needed):
- ✅ Real ASIN resolution accuracy
- ✅ End-to-end report quality

🔧 To exercise these manually:
```bash
GEMINI_API_KEY=... AMAZON_ASSOCIATES_TAG=... \
  cabal run run-scheduled -- --task auto-book-reports
```

## 🐛 Debugging Guide

If something goes wrong in production, the modular design makes isolation straightforward:

1. **Wrong books identified** → check the prompt and response in the log. Fix `buildIdentificationPrompt` in `Identify.hs`.
2. **Wrong ASIN** → check `🛒 Resolved ASIN` log line. Fix prompt or parser in `AmazonLink.hs`.
3. **Bad report content** → check the post-generation log. Fix `buildReportPrompt` in `Report.hs`.
4. **Reflection link not added** → check `🔗 Linked into` log line. Fix `insertBookLink` in `ReflectionLink.hs`.

🚥 Each pure function has tests, so adding a regression test for any bug is mechanical.

## 🚧 Known Gaps & Open Questions

| ❓ Question | ✅ Resolution | 🔧 How to change |
|---|---|---|
| Use ASIN lookup vs Product Advertising API? | Gemini-grounded for now (no API key in repo) | Replace `resolveAmazonLink` in orchestrator |
| Variant priority? | Hardcover > Paperback > Kindle > Audible | Edit `defaultVariantPriority` |
| Recent window length? | 7 days | Edit `recentReflectionWindow` |
| Max books per run? | 1 | Edit `maxBooksPerRun` |
| Affiliate URL form? | Full URL with `?tag=` | Edit `formatAffiliateUrl` |
| Auto-schedule? | No, manual `--task` only | Add `ScheduleEntry` |
| Where to insert link in reflection? | Existing `## [📚 Books]` section, or insert before first embed section | `ReflectionLink.hs` |
| What emoji to prefix new entries? | 🆕 to distinguish auto-generated | `ReflectionLink.hs` |
| Skip books that already exist as different slugs? | Yes — the slug match is canonical | `Discovery.hs` |
