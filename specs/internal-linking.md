# 🔗 Internal Linking — BFS Wikilink Insertion

## 🎯 Overview

📋 Automatically inserts wikilinks into content files by identifying genuine book references with Gemini AI.
🧭 Uses BFS traversal starting from the most recent reflection to prioritize recently active files.
⏱️ Processes one file per run to stay within API quota limits.
🛡️ Tracks analysis state in frontmatter to skip already-processed files across sessions.

## 🏗️ Architecture

### 📦 Components

| 🧩 Component | 📂 Path | 📝 Purpose |
|---|---|---|
| 🔗 Library | `scripts/lib/internal-linking.ts` | 🔧 BFS traversal, Gemini identification, wikilink insertion, frontmatter tracking |
| 🧪 Tests | `scripts/lib/internal-linking.test.ts` | ✅ 50+ tests covering all pure functions and logic |
| ⏰ Scheduler entry | `scripts/lib/scheduler.ts` | 📅 Internal linking task scheduled in the pipeline |

### 🔄 Data Flow

```
🏗️ run(config: LinkingConfig)
         ↓
📇 buildContentIndex(contentDir) → ContentEntry[] from books/
         ↓
🧭 bfsTraversal(contentDir)
   ├─ 🔍 findMostRecentReflection() → start node
   └─ 🔗 extractLinkedPaths() → follow wikilinks + markdown links
         ↓
📄 For each file in BFS order (limit: 1 per run):
   ├─ 🛡️ alreadyAnalyzed(content) → skip if processed (unless force_analyze_links)
   ├─ 🧹 maskProtectedRegions(content) → hide frontmatter, code, links, headings
   ├─ 🤖 identifyBooksWithGemini(body, entries, path, apiKey, model)
   ├─ 🔍 findLinkCandidates(content, masked, index, existing, path)
   └─ ✏️ applyReplacements(content, candidates, validations)
         ↓
💾 Write modified file + recordLinkAnalysis() in frontmatter
```

## 🧭 BFS Traversal

📍 Traversal begins at the most recent reflection file found by scanning `reflections/` for the latest YYYY-MM-DD filename.
🔗 From each visited file, both wikilinks and standard markdown links are extracted and followed.
📂 Traversal spans multiple directories defined in `TRAVERSABLE_DIRS`: books, articles, topics, software, people, products, games, videos, presentations, tools, reflections, chickie-loo, and auto-blog-zero.
📇 Only files in `LINKABLE_DIRS` (currently just books) are eligible for wikilink insertion.

## 🤖 Gemini-Powered Link Suggestion

🧠 The `identifyBooksWithGemini` function sends the file body and a list of book entries to Gemini, asking it to identify which books are genuinely referenced.
📋 The `buildIdentificationPrompt` function constructs a structured prompt with the file content and candidate book titles.
🔗 Only books confirmed by Gemini have their wikilinks inserted at deterministic text positions.
💥 A `QuotaExhaustedError` is thrown when the daily API quota is exhausted, halting the entire pipeline gracefully.

## 🛡️ Skip Tracking

📋 Each processed file gets frontmatter fields recording the analysis model and timestamp.
🔁 The `alreadyAnalyzed` function checks for these fields to skip previously processed files.
🔓 Setting `force_analyze_links: true` in frontmatter overrides the skip check for reprocessing.

## 📏 Per-Run Limits

⏱️ The `maxInferenceRequests` config controls how many Gemini API calls are made per run, defaulting to one file per execution.
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
| `escapeRegex(text)` | 🛡️ Escape special regex characters |
| `formatWikilink(entry)` | 🔗 Format ContentEntry as wikilink |
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
| `alreadyAnalyzed(content)` | 🛡️ Check if file was previously analyzed |
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

## 🧪 Testing

🔬 Tests in `scripts/lib/internal-linking.test.ts` with 50+ test cases across 12+ suites covering:
- 🧹 `stripEmojis`: emoji removal, preservation of non-emoji text, edge cases
- 🛡️ `escapeRegex`: special character escaping
- 🔗 `formatWikilink`: wikilink formatting from content entries
- 📋 `extractContext`: context window extraction around match positions
- 📄 `parseFrontmatter`: key-value parsing, quoted values, missing markers
- 📇 `buildContentIndex`: directory scanning, title extraction, filtering
- 🔗 `extractLinkedPaths`: wikilink and markdown link extraction
- 🔍 `findMostRecentReflection`: date-based file discovery
- 🧭 `bfsTraversal`: link-following traversal across directories
- 🛡️ `maskProtectedRegions`: frontmatter, code, link, heading masking
