# 📝 Blog Generation — AI-Powered Blog Series Pipeline

## 🎯 Overview

📋 Generates daily AI-written blog posts for three distinct blog series.
🧠 Constructs rich prompts from post history, reader comments, and calendar-aware recap detection.
📅 Includes deterministic human-readable date (day of week, month, day, year) in every prompt for date awareness.
🔧 Assembles YAML frontmatter with navigation links, slugs, and model signatures.
🗂️ Manages series configuration, post parsing, and index generation for each series.

## 🏗️ Architecture

### 📦 Components

| 🧩 Component | 📂 Path | 📝 Purpose |
|---|---|---|
| 🕐 Pacific Time | `haskell/src/Automation/PacificTime.hs` | 📅 Shared Pacific timezone logic: formatDay, formatDayHuman, todayPacificDay, pacificHour |
| 🧠 Prompt Builder | `haskell/src/Automation/BlogPrompt.hs` | 🔧 Constructs system and user prompts from blog context with recap awareness |
| 📚 Series Logic | `haskell/src/Automation/BlogSeries.hs` | 🔄 Context assembly, post parsing, index generation, navigation linking |
| 📄 Post Reader | `haskell/src/Automation/BlogPosts.hs` | 📖 Reads and parses markdown posts from series directories |
| ⚙️ Series Config | `haskell/src/Automation/BlogSeriesConfig.hs` | 🗺️ Defines the three blog series with metadata and posting schedules |

### 🔄 Data Flow

```
⚙️ Series Config (BLOG_SERIES map)
         ↓
📚 buildBlogContext(seriesId, repoRoot, comments, today)
         ↓
   ├─ 📄 readSeriesPosts(seriesDir) → sorted BlogPost[]
   ├─ 📖 readAgentsMd(seriesDir) → system prompt override
   └─ 🗨️ filterCommentsAfterLastPost() → relevant BlogComment[]
         ↓
🧠 buildBlogPrompt(context) → { system, user }
         ↓
   ├─ 📜 buildPostHistory() → full recent + title-only older posts
   ├─ 💬 buildCommentsSection() → priority-flagged comments
   └─ 📅 recapInstructions() → weekly/monthly/quarterly/annual recap rules
         ↓
🤖 Gemini API call → raw generated post
         ↓
📋 parseGeneratedPost(raw) → { body, title }
         ↓
📝 assembleFrontmatter(series, today, title, slug, previousPost)
         ↓
💾 Write post file + updatePreviousPost() with forward link
```

## 📚 Blog Series Configuration

📋 Three series are defined in the `BLOG_SERIES` ReadonlyMap, each with unique metadata.

| 🏷️ Series ID | 🎨 Icon | ⏰ Post Time (UTC) | ⭐ Priority User | 🌐 Base URL |
|---|---|---|---|---|
| 🤖 auto-blog-zero | 🤖 | 16:00 | bagrounds | bagrounds.org/auto-blog-zero |
| 🐔 chickie-loo | 🐔 | 15:00 | ChickieLoo | bagrounds.org/chickie-loo |
| 🏛️ systems-for-public-good | 🏛️ | 17:00 | bagrounds | bagrounds.org/systems-for-public-good |

📌 Each series also defines a `navLink` in wikilink format for breadcrumb navigation.
📦 `BACKFILL_CONTENT_IDS` combines all series IDs with `reflections` and `ai-blog` for indexing operations.

## 🧠 Prompt Construction

### 📅 Date Awareness

📆 Every user prompt begins with a deterministic human-readable date: "Today is Saturday, April 11, 2026."
🕐 The `formatDayHuman` function in `Automation.PacificTime` produces the full day-of-week and date from a pure `Day` value.
📋 The YYYY-MM-DD machine-readable date is also included on the next line for filename/URL context.
🛡️ This prevents the AI from confusing the day of the week, since the date is computed deterministically in Pacific time rather than inferred by the model.

### 📜 Post History

📖 The prompt includes full content for recent posts since the last recap, up to a maximum of seven posts.
📋 Older posts appear as title-only entries to conserve context window space.
🔍 The `postsSinceLastRecap` function identifies the boundary by scanning for recap keywords like "weekly recap" or "monthly recap."

### 💬 Comment Integration

⭐ Comments from the series priority user are flagged with a PRIORITY marker in the prompt.
📅 Only comments posted after the most recent blog post are included.
🤫 When no comments exist, the prompt notes that reader engagement is rare.

### 📅 Recap Detection

📆 Calendar-aware recap instructions are injected based on the current date.
🗓️ Sundays trigger weekly recap instructions.
📅 The last day of a month triggers monthly recap instructions.
📊 Quarter-end and year-end dates trigger quarterly and annual recap instructions respectively.

## 📝 Frontmatter Assembly

📋 The `assembleFrontmatter` function accepts `(series, today, title, slug)` and produces YAML frontmatter with these fields: share, aliases, title, URL, Author, and tags.
🏷️ The `buildDisplayTitle` helper constructs the display title as `today | icon title icon` used for both aliases and title fields.
🔗 The URL is constructed as `baseUrl/today-slug` to include the date prefix in the URL path.
📝 The Author field is quoted with `quoteForYaml` to prevent YAML from interpreting wikilink syntax `[[author]]` as nested lists.
🛡️ The `quoteForYaml` helper always wraps values in double quotes, escaping internal quotes and backslashes for YAML safety.
🚫 No `date:` field is included in the frontmatter.

## 🔗 Navigation Links

⏮️ `buildBackLink` creates a wikilink to the previous post using the series directory prefix and a back-arrow emoji.
⏭️ `buildForwardLink` creates a wikilink to the next post with a forward-arrow emoji.
📄 `updatePreviousPost` modifies the previous post file on disk to inject the forward link into its existing navigation line.

## 📄 Post Parsing and Slug Extraction

📋 `parseGeneratedPost` validates AI output by requiring a minimum of 200 characters and at least one heading.
🏷️ The title is extracted from the first H1 or H2 heading in the generated markdown.
🔗 `extractSlug` strips the YYYY-MM-DD date prefix from filenames to produce URL-friendly slugs.

## 🧹 Title Sanitization

🛡️ `sanitizeTitle` strips date prefixes, pipe separators, and series icon emoji from AI-generated titles before they reach `buildDisplayTitle`.
🔄 The AI sometimes mimics the display-title format it sees in previous post context, producing headings like `# 2026-03-30 | 🤖 Title 🤖` instead of just `# Title`.
🧩 Without sanitization, `buildDisplayTitle` would double the date and icon, producing malformed titles like `2026-03-30 | 🤖 🤖 2026-03-30 | Title 🤖 🤖`.
📝 The sanitization pipeline strips in order: leading series icon, date-pipe prefix, leading series icon again, trailing series icon, then trims whitespace.
📖 Additionally, `formatPost` applies `sanitizeTitle` when displaying previous post titles in the AI prompt context, preventing the AI from learning the display-title pattern.
💬 The user prompt includes an explicit instruction telling the AI not to include dates or icons in its heading.

## 📇 Series Index Generation

📋 `generateSeriesIndex` creates a dataview-based markdown index page listing all posts newest-first.
🚫 The index query excludes AGENTS.md and the index file itself.

## ✍️ Model Signature

📌 `appendModelSignature` appends a `✍️ Written by {model}` attribution line to the end of each generated post.

## 🔧 Key Functions

### 🧊 Pure Functions (No I/O)

| 🔧 Function | 📂 Module | 📝 Purpose |
|---|---|---|
| `formatDay(day)` | PacificTime | 📅 Format Day as YYYY-MM-DD text |
| `formatDayHuman(day)` | PacificTime | 📅 Format Day as "Saturday, April 11, 2026" for AI prompts |
| `pacificHour(utcTime)` | PacificTime | 🕐 Convert UTC time to Pacific hour (0-23) |
| `buildBlogPrompt(context)` | BlogPrompt | 🧠 Construct system and user prompts from blog context |
| `filterCommentsAfterLastPost(series, posts, comments)` | BlogPrompt | 📅 Filter comments to those after most recent post |
| `buildBackLink(series, filename)` | BlogPrompt | ⏮️ Create wikilink navigation to previous post |
| `buildForwardLink(series, filename)` | BlogPrompt | ⏭️ Create wikilink navigation to next post |
| `assembleFrontmatter(series, today, title, slug)` | BlogPrompt | 📝 Generate YAML frontmatter with display title, quoted Author, and date-prefixed URL |
| `buildDisplayTitle(series, today, title)` | BlogPrompt | 🏷️ Construct display title as `today \| icon title icon` |
| `parseGeneratedPost(raw)` | BlogSeries | 📋 Parse and validate AI-generated post content |
| `extractSlug(filename)` | BlogSeries | 🔗 Extract URL slug from dated filename |
| `generateSeriesIndex(series, posts)` | BlogSeries | 📇 Generate dataview-based series index page |
| `appendModelSignature(body, model)` | BlogSeries | ✍️ Append model attribution signature |
| `lookupSeries(seriesId)` | BlogSeriesConfig | ⚙️ Retrieve series config by ID |

### 💾 I/O Functions

| 🔧 Function | 📂 Module | 📝 Purpose |
|---|---|---|
| `todayPacificDay` | PacificTime | 📅 Return today's date as a Day in Pacific time |
| `readSeriesPosts(seriesDir)` | BlogPosts | 📄 Read and parse all markdown posts from series directory |
| `readAgentsMd(seriesDir)` | BlogPosts | 📖 Read AGENTS.md system prompt override |
| `buildBlogContext(seriesId, repoRoot, comments, today)` | BlogSeries | 📚 Assemble complete blog context from config and disk |
| `updatePreviousPost(seriesDir, previousPost, series, nextFilename)` | BlogSeries | 🔗 Update previous post file with forward navigation link |

## 🧪 Testing

🔬 Tests in `haskell/test/Automation/BlogSeriesTest.hs` with 44 test cases across 8 suites covering:
- 📄 `readSeriesPosts`: empty directory, newest-first sorting, index/AGENTS exclusion, date extraction
- 📖 `readAgentsMd`: present and missing AGENTS.md handling
- 📚 `buildBlogContext`: unknown series error, complete context assembly
- 🧠 `buildBlogPrompt`: system prompt sources, post and comment inclusion, recap instructions, human-readable date inclusion
- ⏮️ `buildBackLink`: wikilink format, extension stripping, series prefix
- 📝 `assembleFrontmatter`: deterministic output, nav links, YAML quoting
- 📇 `generateSeriesIndex`: dataview query generation
- 🔗 `extractSlug`: date prefix stripping
- 📋 `parseGeneratedPost`: validation and title extraction
- ✍️ `appendModelSignature`: attribution formatting

🔬 Tests in `haskell/test/Automation/PacificTimeTest.hs` covering:
- 📅 `formatDay`: YYYY-MM-DD formatting with zero-padding
- 📅 `formatDayHuman`: full human-readable date with day of week, month name, day, and year
- 🕐 `pacificHour`: PST/PDT conversion with property-based range validation

## 🆕 How to Create a New Fully Automated Blog Series

📋 Adding a new fully automated blog series requires changes in four files plus creating a content directory.
🧩 The shared modules handle all prompt construction, date awareness, frontmatter assembly, and navigation linking automatically.

### 1️⃣ Add series configuration in `BlogSeriesConfig.hs`

📝 Define a new `BlogSeriesConfig` record with the series ID, display name, icon emoji, author wikilink, base URL, optional priority user, navigation link, and UTC post time.
📦 Add the new config to the `blogSeries` list so it appears in `blogSeriesMap` and `backfillContentIds`.

### 2️⃣ Add a task ID in `Scheduler.hs`

🏷️ Add a new constructor to the `TaskId` sum type, such as `BlogSeriesMyNewSeries`.
🔄 Add a corresponding case to `taskIdToText` mapping to `"blog-series:my-new-series"`.
✅ The `taskIdFromText` map derives automatically from `taskIdToText` via `Bounded` and `Enum`.
📋 Add the new task ID to `isBlogSeries` so it inherits the at-or-after scheduling behavior.

### 3️⃣ Add a schedule entry and run config in `Scheduler.hs`

⏰ Add a `ScheduleEntry` to the `schedule` list, specifying the Pacific hour to generate (such as `[10]` for 10 AM Pacific).
🤖 Add a `BlogSeriesRunConfig` entry to `blogSeriesRunConfigs` with the series ID, Gemini model chain, and environment variable name for the priority user.

### 4️⃣ Add a dispatch case in `RunScheduled.hs`

🔀 Add a case for the new `TaskId` constructor in the task dispatch section of `runScheduledTasks`, calling `runBlogSeries context "my-new-series"`.

### 5️⃣ Create the content directory

📂 Create the series directory in the Obsidian vault at `content/my-new-series/`.
📖 Optionally add an `AGENTS.md` file in the series directory with a custom system prompt for the AI. If absent, the default system prompt is used.
📇 The series index page is generated automatically on the first run.

### 🔧 What you do NOT need to change

🧠 `BlogPrompt.hs` — all prompt construction, date awareness, recap detection, and title sanitization are shared automatically.
📚 `BlogSeries.hs` — context assembly, post parsing, navigation linking are all shared.
🕐 `PacificTime.hs` — timezone handling and date formatting are shared.
📝 `BlogPosts.hs` — post reading and parsing are shared.
🖼️ `BlogImage.hs` — image generation is shared.
