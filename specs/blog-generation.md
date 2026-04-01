# 📝 Blog Generation — AI-Powered Blog Series Pipeline

## 🎯 Overview

📋 Generates daily AI-written blog posts for three distinct blog series.
🧠 Constructs rich prompts from post history, reader comments, and calendar-aware recap detection.
🔧 Assembles YAML frontmatter with navigation links, slugs, and model signatures.
🗂️ Manages series configuration, post parsing, and index generation for each series.

## 🏗️ Architecture

### 📦 Components

| 🧩 Component | 📂 Path | 📝 Purpose |
|---|---|---|
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

## 📇 Series Index Generation

📋 `generateSeriesIndex` creates a dataview-based markdown index page listing all posts newest-first.
🚫 The index query excludes AGENTS.md and the index file itself.

## ✍️ Model Signature

📌 `appendModelSignature` appends a `✍️ Written by {model}` attribution line to the end of each generated post.

## 🔧 Key Functions

### 🧊 Pure Functions (No I/O)

| 🔧 Function | 📝 Purpose |
|---|---|
| `buildBlogPrompt(context)` | 🧠 Construct system and user prompts from blog context |
| `filterCommentsAfterLastPost(comments, posts, postTime)` | 📅 Filter comments to those after most recent post |
| `buildBackLink(series, previousPost)` | ⏮️ Create wikilink navigation to previous post |
| `buildForwardLink(series, nextFilename)` | ⏭️ Create wikilink navigation to next post |
| `assembleFrontmatter(series, today, title, slug)` | 📝 Generate YAML frontmatter with display title, quoted Author, and date-prefixed URL |
| `buildDisplayTitle(series, today, title)` | 🏷️ Construct display title as `today \| icon title icon` |
| `todayPacific()` | 📅 Return today's date in YYYY-MM-DD Pacific time |
| `parseGeneratedPost(raw)` | 📋 Parse and validate AI-generated post content |
| `extractSlug(filename)` | 🔗 Extract URL slug from dated filename |
| `generateSeriesIndex(series, posts)` | 📇 Generate dataview-based series index page |
| `appendModelSignature(body, model)` | ✍️ Append model attribution signature |
| `lookupSeries(seriesId)` | ⚙️ Retrieve series config by ID |

### 💾 I/O Functions

| 🔧 Function | 📝 Purpose |
|---|---|
| `readSeriesPosts(seriesDir)` | 📄 Read and parse all markdown posts from series directory |
| `readAgentsMd(seriesDir)` | 📖 Read AGENTS.md system prompt override |
| `buildBlogContext(seriesId, repoRoot, comments, today)` | 📚 Assemble complete blog context from config and disk |
| `updatePreviousPost(seriesDir, previousPost, series, nextFilename)` | 🔗 Update previous post file with forward navigation link |

## 🧪 Testing

🔬 Tests in `haskell/test/Automation/BlogSeriesTest.hs` with 44 test cases across 8 suites covering:
- 📄 `readSeriesPosts`: empty directory, newest-first sorting, index/AGENTS exclusion, date extraction
- 📖 `readAgentsMd`: present and missing AGENTS.md handling
- 📚 `buildBlogContext`: unknown series error, complete context assembly
- 🧠 `buildBlogPrompt`: system prompt sources, post and comment inclusion, recap instructions
- ⏮️ `buildBackLink`: wikilink format, extension stripping, series prefix
- 📝 `assembleFrontmatter`: deterministic output, nav links, YAML quoting
- 📇 `generateSeriesIndex`: dataview query generation
- 🔗 `extractSlug`: date prefix stripping
- 📋 `parseGeneratedPost`: validation and title extraction
- ✍️ `appendModelSignature`: attribution formatting
