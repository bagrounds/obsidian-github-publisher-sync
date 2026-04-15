# 🔗 Internal Linking — BFS Wikilink Insertion

## 🎯 Overview

📋 Automatically inserts wikilinks into content files by identifying genuine book references with Gemini AI.
🧭 Uses BFS traversal starting from the most recent reflection to prioritize recently active files.
⏱️ Spends up to 10 inference calls per run to maximize linking coverage within API quota limits.
🛡️ Tracks analysis state in frontmatter to skip already-processed files across sessions.
📖 Supports subtitle-aware matching: books referenced by main title (without subtitle) are correctly detected and linked with the full book title.

## 🏗️ Architecture

### 📦 Components

| 🧩 Component | 📂 Path | 📝 Purpose |
|---|---|---|
| 🔗 Library | `haskell/src/Automation/InternalLinking.hs` | 🔧 BFS traversal, Gemini identification, wikilink insertion, frontmatter tracking |
| 🧪 Tests | `haskell/test/Automation/InternalLinkingTest.hs` | ✅ 160+ tests covering all pure functions and logic |
| ⏰ Scheduler entry | `haskell/src/Automation/Scheduler.hs` | 📅 Internal linking task scheduled in the pipeline |

### 🔄 Data Flow

```
🏗️ run(config: LinkingConfig)
         ↓
📇 buildContentIndex(contentDir) → ContentEntry[] from books/ (with mainTitle for subtitle-bearing titles)
         ↓
🧭 bfsTraversal(contentDir)
   ├─ 🔍 findMostRecentReflection() → start node
   └─ 🔗 extractLinkedPaths() → follow wikilinks + markdown links
         ↓
📄 For each file in BFS order (limit: 10 inference calls per run):
   ├─ 🛡️ alreadyAnalyzed(content) → skip if processed (unless force_analyze_links)
   ├─ 🧹 maskProtectedRegions(content) → hide frontmatter, code, links, headings
   ├─ 🤖 identifyBooksWithGemini(body, entries, path, apiKey, model)
   ├─ 🔍 findLinkCandidates(content, masked, index, existing, path)
   │     computes extractMainTitle on-the-fly; tries full plainTitle first, then subtitle prefix fallback
   └─ ✏️ applyReplacements(content, candidates, validations) — always uses full book title in wikilink
         ↓
💾 Write modified file + recordLinkAnalysis() in frontmatter
```

## 📖 Subtitle-Aware Book Matching

📋 Many book titles include subtitles separated by a colon-space or a dash (e.g., "Domain-Driven Design: Tackling Complexity in the Heart of Software" or "System Design Interview - An Insider's Guide").
🔍 Content authors often reference books by their main title only (e.g., just "Domain-Driven Design" or "Refactoring" or "Antifragile").
🧠 The `extractMainTitle` function extracts the text before the first subtitle separator, trying `: ` first, then falling back to ` - `. The extracted main title must be at least 8 characters long.
🛡️ Single-word main titles like "Antifragile", "Refactoring", and "Debugging" are supported because the Gemini AI identification layer provides false-positive protection, ensuring only genuinely referenced books are linked.
🔗 `findLinkCandidates` computes main titles on-the-fly (no caching in the type), tries matching the full `plainTitle` first, falling back to the extracted main title when the full title is not found in the text.
📖 Wikilinks always use the full title from the book's frontmatter, even when matched via the shorter main title.
🤖 The Gemini prompt lists books with "also known as" annotations for entries with a main title variant, helping the AI recognize partial references.

## 🧭 BFS Traversal

📍 Traversal begins at the most recent reflection file found by scanning `reflections/` for the latest YYYY-MM-DD filename.
🔗 From each visited file, both wikilinks and standard markdown links are extracted and followed.
📂 Traversal spans multiple directories defined in `TRAVERSABLE_DIRS`: books, articles, topics, software, people, products, games, videos, presentations, tools, reflections, chickie-loo, and auto-blog-zero.
📇 Only files in `LINKABLE_DIRS` (currently just books) are eligible for wikilink insertion.
🔧 Wikilink parsing in BFS uses a manual character-by-character parser (not POSIX regex) to correctly extract full link targets, including those with special characters.

## 🤖 Gemini-Powered Link Suggestion

🧠 The `identifyBooksWithGemini` function sends the file body and a list of book entries to Gemini, asking it to identify which books are genuinely referenced.
📋 The `buildIdentificationPrompt` function constructs a structured prompt with the file content and candidate book titles.
🔗 Only books confirmed by Gemini have their wikilinks inserted at deterministic text positions.
💥 A `QuotaExhaustedError` is thrown when the daily API quota is exhausted, halting the entire pipeline gracefully.

## 🛡️ Skip Tracking and Algorithm Versioning

📋 Each processed file gets frontmatter fields recording the analysis model, timestamp, and algorithm version.
🔢 The `linkingAlgorithmVersion` constant tracks the current algorithm version. When the linking algorithm changes meaningfully (new matching rules, separator support, etc.), this version is bumped.
🔁 The `alreadyAnalyzed` function compares the stored `link_analysis_version` in frontmatter against the current `linkingAlgorithmVersion`. Files analyzed with an older version are automatically re-analyzed.
🔓 Setting `force_analyze_links: true` in frontmatter overrides the version check for manual reprocessing.
📝 Frontmatter fields written by `recordLinkAnalysis`: `link_analysis_model`, `link_analysis_version`, `link_analysis_time`, `force_analyze_links`.

## 📏 Per-Run Limits

⏱️ The `maxInferenceRequests` config controls how many Gemini inference calls are made per run, defaulting to 10. Files that skip (already analyzed or no eligible books) do not count against this limit.
🔄 Rate-limit errors trigger exponential backoff starting at 5 seconds, doubling up to 60 seconds, with up to 3 retries.
📊 Server-provided retry delays from the `Retry-After` header or error details are preferred over computed backoff.

## 🔧 Protected Region Masking

🛡️ Before searching for link candidates, `maskProtectedRegions` replaces sensitive content with whitespace to prevent false matches.
📋 Protected regions include YAML frontmatter, fenced code blocks, existing wikilinks, existing markdown links, and section headings.

## 📊 File Result Reporting

📋 Each processed file produces a `FileResult` with: relativePath, linksAdded count, modified flag, skipped flag, and whether Gemini inference was used.
📊 The overall `RunResult` aggregates: filesVisited, filesModified, totalLinksAdded, filesSkipped, and individual fileResults.

## 🔧 Key Functions

### 🧊 Pure Functions (No I/O)

| 🔧 Function | 📝 Purpose |
|---|---|
| `stripEmojis(text)` | 🧹 Remove emoji characters from text |
| `countWords(text)` | 📏 Count words splitting on whitespace and hyphens |
| `extractMainTitle(plainTitle)` | 📖 Extract main title before subtitle separator (`: `) |
| `escapeRegex(text)` | 🛡️ Escape special regex characters |
| `formatWikilink(entry)` | 🔗 Format ContentEntry as wikilink (delegates to shared `Automation.Wikilink.formatWikilink`) |
| `extractContext(content, position, length, radius)` | 📋 Extract surrounding context for a match position |
| `parseFrontmatter(content)` | 📄 Parse key-value frontmatter pairs |
| `extractLinkedPaths(body, notePath, contentDir)` | 🔗 Extract all linked paths from wikilinks and markdown links |
| `maskProtectedRegions(content)` | 🛡️ Replace frontmatter, code, links, headings with whitespace |
| `contentAlreadyLinksTo(content, entry)` | ✅ Check if file already links to a content entry |
| `findLinkCandidates(content, masked, index, existing, path)` | 🔍 Find positions for potential wikilink insertions |
| `buildIdentificationPrompt(body, entries, path)` | 🧠 Construct Gemini prompt for book identification |
| `extractJsonArray(text)` | 📋 Extract JSON array from Gemini response text |
| `generateDiff(original, modified)` | 📊 Generate minimal diff showing changed lines |
| `applyReplacements(content, candidates, validations)` | ✏️ Apply wikilink replacements end-to-start |
| `alreadyAnalyzed(version, content)` | 🛡️ Check if file was analyzed with the current algorithm version |
| `extractBody(content)` | 📄 Extract body text after frontmatter |
| `isRateLimitError(error)` | 🚦 Detect rate-limit errors |
| `isDailyQuotaError(error)` | 💥 Detect daily quota exhaustion |
| `parseRetryDelay(error)` | ⏱️ Extract retry delay from error |

### 💾 I/O Functions

| 🔧 Function | 📝 Purpose |
|---|---|
| `buildContentIndex(contentDir)` | 📇 Build index of content entries from books directory |
| `findMostRecentReflection(contentDir)` | 🔍 Find most recent reflection by date |
| `bfsTraversal(contentDir)` | 🧭 BFS from most recent reflection following links |
| `identifyBooksWithGemini(body, entries, path, apiKey, model)` | 🤖 Use Gemini to identify genuine book references |
| `processFile(relativePath, contentDir, index, config)` | 📄 Process single file through the full linking pipeline |
| `updateFrontmatterFields(filePath, fields)` | 📝 Set frontmatter fields on file |
| `updateFrontmatterTimestamp(filePath, timestamp)` | ⏰ Update "updated" field in frontmatter |
| `recordLinkAnalysis(filePath, model, timestamp)` | 📋 Record analysis metadata in frontmatter |
| `run(config)` | 🔄 Orchestrate full pipeline: index, BFS, process, report |

## 📊 Logging

📋 The linking pipeline logs at two levels: per-file decisions and a run-level summary.

🔍 Per-file logging (only for files not already analyzed):
- ⏭️ No eligible books: all books are already linked or file is a self-reference
- 🤖 Checking N eligible books with Gemini: file is being analyzed
- ❌ Gemini error: API call failed (includes error message)
- ⏭️ Gemini found no book references: AI determined no books are genuinely referenced
- ⏭️ Gemini identified N books but no linkable positions found: AI found references but regex could not locate text positions (e.g., protected by masking)
- ✏️ N links applied: successful link insertion

📊 Run-level summary includes: total files visited, already analyzed count, files checked with Gemini, files modified, and total links added.

## 🧪 Testing

🔬 Tests across `haskell/test/Automation/InternalLinkingTest.hs` and `haskell/test/Automation/InternalLinking/` covering:
- 🧹 `stripEmojis`: emoji removal, preservation of non-emoji text, edge cases
- 🛡️ `escapeRegex`: special character escaping
- 🔗 `formatContentEntryWikilink`: wikilink formatting from content entries (delegates to shared `Automation.Wikilink.formatWikilink`)
- 📋 `extractContext`: context window extraction around match positions
- 📖 `extractMainTitle`: colon-space separator, dash separator, single-word main titles, minimum length requirement, edge cases
- 📄 `parseFrontmatter`: key-value parsing, quoted values, missing markers
- 📇 `buildContentIndex`: directory scanning, title extraction, filtering
- 🔗 `extractLinkedPaths`: wikilink and markdown link extraction
- 🔍 `findMostRecentReflection`: date-based file discovery
- 🧭 `bfsTraversal`: link-following traversal across directories
- 🛡️ `maskProtectedRegions`: frontmatter, code, link, heading masking
- 📖 Subtitle matching: single-word main titles, dash-separated subtitles, full title preference, full title in wikilink, protected region respect
- 🤖 `buildIdentificationPrompt`: also-known-as annotations for subtitle entries, single-word main titles, dash-separated subtitles
