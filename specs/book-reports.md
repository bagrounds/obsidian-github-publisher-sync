# 📚 Book Reports Automation

> Auto-generate a book report page for a book that has been **plain-text recommended** in an existing book report's recommendations section but does not yet have a `books/<slug>.md` page in the Obsidian vault. Designed to be **resumable**, **inference-frugal**, and **idempotent**.

## 🎯 Goal

Convert this manual flow:

> "Another book report mentioned a book by name in its recommendations section. I should write a report on it, find the canonical Amazon link with the right edition priority, drop in an affiliate URL, and link the report back from today's reflection."

into an automation that runs at most **once per Pacific day** and produces at most **one** book report per run.

## 🧭 Pipeline (vertical slice)

```
existing book reports ─► Discovery (pure)  ─► Pending (frontmatter)  ─► Amazon (Gemini, 1 call)
                                                                              │
                                                                              ▼
                                                                      Report (Gemini, 1 call)
                                                                              │
                                                                              ▼
                                                                  ReflectionUpdate + DailyChanges
```

Every step is owned by one module, every module has a dedicated test suite, and only the top-level `Automation.BookReports` module performs IO.

## 🧱 Module layout

| Module | Concern | Pure? |
|---|---|---|
| `Automation.BookReports.Types` | Domain types (`BookTitle`, `BookAuthor`, `BookSlug`, `Asin`, `AmazonVariant`) with smart constructors | ✅ |
| `Automation.BookReports.Discovery` | Scan **existing book reports** for plain-text bullet recommendations like `* 📖 **Title** by Author: …` whose slug is not yet a book page | ✅ |
| `Automation.BookReports.PendingState` | Read/write resumability fields in the books index frontmatter | ❌ (file IO only) |
| `Automation.BookReports.Amazon` | Gemini-grounded ASIN lookup, ASIN extraction from URL, affiliate URL builder | ✅ (prompt + parse) |
| `Automation.BookReports.Report` | Single-call report prompt, frontmatter assembly, body composition | ✅ |
| `Automation.BookReports.ReflectionUpdate` | Idempotent insertion of the wikilink under `## [📚 Books]` (creates section if absent) | ✅ |
| `Automation.BookReports` | IO orchestration | ❌ |

## 💾 Resumability — frontmatter is the single source of truth

State lives in **`<vault>/books/index.md`** frontmatter:

```yaml
---
book_report_pending: "Sapiens: A Brief History of Humankind"
book_report_asin: "0451524934"
book_report_last_generated: "2026-05-05"
---
```

Lifecycle on each run:

1. **Read** `book_report_pending` and `book_report_asin`. If `book_report_last_generated` equals today *and* there is no pending work, **skip** — we already produced today's report.
2. If `book_report_pending` is set, **resume**: skip discovery, reuse the cached `book_report_asin` if present, otherwise call Gemini for ASIN.
3. After the Gemini ASIN call succeeds, **persist** `book_report_asin` immediately so the next attempt does not re-spend that inference.
4. After the report is written and the reflection is updated, **clear** `book_report_pending` and `book_report_asin`, and set `book_report_last_generated = today`.

This guarantees:

- Catastrophic failure (network drop, OOM, rate limit) never re-spends a successful Gemini call.
- The same book is never published twice in one Pacific day.
- The user can manually clear `book_report_pending` to abandon a run.

## 🔍 Discovery — pure string parsing, zero inference

`BookReports.Discovery` scans **existing book report pages** (`<vault>/books/*.md`, excluding `index.md`). The recommendations sections of those reports are full of bullet lines that name other books in plain text — that is exactly the population of "good ideas we don't yet have a report for".

For every line in every existing book report it looks for bullets matching either of:

- `* 📖 **Title** by Author: optional description` (bold-title form)
- `* 📖 Title by Author: optional description` (plain form)

Lines that already contain a markdown link `](` or a wikilink `[[` are **skipped** — those refer to books that already have pages. The extracted title is emoji-stripped, slugified via `slugFromTitle`, and emitted as a candidate when its slug is not already in `<vault>/books/`.

This replaces both the previous Gemini-based identification step and the earlier broken-link search through reflections. Candidates are grounded in real recommendations, not hallucinations or accidental references.

## 🛒 Amazon — one Gemini call, validated output

`BookReports.Amazon.buildAmazonResolutionPrompt` asks Gemini (with Google Search grounding enabled) for a single canonical ASIN, preferring **Hardcover > Paperback > Kindle > Audible** (`defaultVariantPriority`). The response is parsed into `AmazonResolution { resolvedAsin, resolvedVariant }`. The ASIN must:

- Match `^[A-Z0-9]{10}$` (validated by `mkAsin`)
- Be parseable from the URL the model returned alongside the JSON (cross-checked via `extractAsinFromUrl`)
- Have a recognised variant (`variantFromText`)

If any check fails, the run **stops** without publishing — better no report than a wrong link.

### 🔑 Optional: Amazon Product Advertising API

A follow-up enhancement (not yet implemented) will use the [Amazon Product Advertising API 5.0](https://webservices.amazon.com/paapi5/documentation/) when credentials are present, providing higher-fidelity ASIN lookup. The required env vars will be `AMAZON_PA_ACCESS_KEY`, `AMAZON_PA_SECRET_KEY`, and `AMAZON_PA_PARTNER_TAG`. To obtain credentials:

1. Sign up for the [Amazon Associates program](https://affiliate-program.amazon.com/) and accumulate the qualifying sales required to retain access.
2. From your Associates dashboard, request access to the Product Advertising API.
3. Generate an access key + secret key under "Manage your tracking IDs".

Until then, Gemini-grounded resolution is the only path.

## ✍️ Report — one Gemini call, fully styled

`BookReports.Report` composes a prompt that produces the **entire** report body in one inference call:

- `# 📜 Title` H1
- `📌 TL;DR` (2-3 sentences)
- `🤖 AI Summary` (chapter or theme overview)
- `🧠 Evaluation` (strengths, weaknesses)
- `🌱 Topics for Further Understanding`
- `❓ FAQ`
- `📚 Book Recommendations` with `Similar` / `Contrasting` / `Related` sub-sections
- `💬 What Do You Think?`

The system instruction enforces emoji-rich Obsidian-flavored markdown, no italicized book titles, and TTS-friendly prose. The orchestrator wraps the body with frontmatter (containing `auto_generated`, `auto_generated_by`, `auto_generated_on`), navigation breadcrumbs, the affiliate URL, and the standard "As an Amazon Associate I earn from qualifying purchases" disclosure.

## 🔗 Reflection update — wikilinks, idempotent, with daily changes

`BookReports.ReflectionUpdate.insertOrUpdateBooksSection` adds the line:

```
- 🆕📚 [[books/<slug>|<title>]] 🤖
```

…under `## [[books/index|📚 Books]]`. If that section is missing, the function inserts it before any trailing section (Updates / Changes / social embeds). Running twice is a no-op.

The orchestrator additionally calls `Automation.DailyUpdates.addUpdateLinksToReflection` with a fresh `BookReportGenerated` detail so the report shows up in the daily changes table column (📚) just like images, internal links, and platform postings.

## ⚙️ Configuration

| Knob | Location | Default |
|---|---|---|
| `AMAZON_ASSOCIATES_TAG` | env (required) | — |
| `BOOK_REPORT_MODEL` | env (optional) | `gemini-2.5-flash` (with `gemini-3.1-flash-lite-preview` fallback) |
| `defaultVariantPriority` | `Types.hs` | `[Hardcover, Paperback, Kindle, Audible]` |
| `maxBooksPerRun` | `BookReports.hs` | 1 |

## 🧪 Test coverage

| Module | Test module | Notes |
|---|---|---|
| Types | `BookReports.TypesTest` | Smart constructors, slug normalisation property tests, variant round-trip |
| Discovery | `BookReports.DiscoveryTest` | Bold-bullet, plain-bullet, already-linked skip, known-slug skip, source path preservation |
| PendingState | `BookReports.PendingStateTest` | Round-trip, clear, complete-today (uses `temporary` for fixtures) |
| Amazon | `BookReports.AmazonTest` | Affiliate URL, ASIN URL extraction, JSON parse with code fences |
| Report | `BookReports.ReportTest` | Prompt covers all sections, frontmatter wrapping, attribution line |
| ReflectionUpdate | `BookReports.ReflectionUpdateTest` | Section creation, append, idempotence |

Live ASIN accuracy and report quality require a real Gemini key + Amazon and are intentionally **not** part of CI; exercise from the workflow_dispatch UI.

## 🚦 Manual invocation

The task is registered in `staticSchedule` with an **empty `hoursPacific`** so it never auto-runs. Invoke it from a phone via the GitHub Actions **Run workflow** button on `scheduled.yml` and pass `book-reports` to the `task` input. Locally:

```bash
GEMINI_API_KEY=… AMAZON_ASSOCIATES_TAG=… \
  cabal run run-scheduled -- --task book-reports
```

## 🐛 Debug map — log line → owning module

| Log line prefix | Module |
|---|---|
| `▶️  book-reports`, `📅 Pacific date`, `📒 Pending state` | `Automation.BookReports` |
| `📂 Vault books directory`, `📚 Known book slugs`, `📅 Reflections in window`, `🎯 Candidates discovered`, `📝 Selected candidate`, `🐌 Slug` | `Automation.BookReports` (orchestration) |
| `🛒 Asking Gemini for canonical Amazon ASIN`, `📥 Gemini ASIN response`, `✅ Resolved ASIN` | `Automation.BookReports` + `BookReports.Amazon` |
| `✍️  Generating report body`, `📝 Writing report` | `Automation.BookReports` + `BookReports.Report` |
| `📓 Inserted wikilink`, `📊 Recorded book report in daily changes` | `Automation.BookReports` + `BookReports.ReflectionUpdate` + `Automation.DailyUpdates` |
| `⚠️ AMAZON_ASSOCIATES_TAG not set`, `⏭️ already been generated today` | `Automation.BookReports` (gate) |
