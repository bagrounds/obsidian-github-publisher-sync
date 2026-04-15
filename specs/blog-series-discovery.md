# 🔍 Blog Series Auto-Discovery — Declarative Configuration

## 🎯 Overview

📋 Blog series are defined as individual JSON configuration files in the `haskell/series/` directory.
🔍 The system auto-discovers all `.json` files at startup and derives everything needed to run each series.
🚀 Adding a new blog series requires only creating a single config file — no Haskell source changes.

## 🏗️ Architecture

### 📦 Components

| 🧩 Component | 📂 Path | 📝 Purpose |
|---|---|---|
| 🔍 Discovery | `haskell/src/Automation/BlogSeriesDiscovery.hs` | JSON config parser, validation, convention-based derivation |
| ⚙️ Series Config | `haskell/src/Automation/BlogSeriesConfig.hs` | Runtime-parameterized series metadata and lookup |
| 🗓️ Scheduler | `haskell/src/Automation/Scheduler.hs` | Dynamic schedule built from discovered series |
| 🚀 Runner | `haskell/app/RunScheduled.hs` | Discovers series at startup, builds dynamic task runners |

### 🔄 Data Flow

```
📂 haskell/series/*.json (config files on disk)
         ↓
🔍 discoverSeries(haskellDir) → [DiscoveredSeries]
         ↓
   ├─ deriveBlogSeriesConfig → BlogSeriesConfig (metadata)
   ├─ deriveBlogSeriesRunConfig → BlogSeriesRunConfig (models, env var)
   └─ deriveScheduleEntry → ScheduleEntry (task ID, hours)
         ↓
🗓️ buildSchedule(dynamicEntries) → full schedule (static + dynamic)
         ↓
🚀 taskRunners(context, seriesMap, runConfigs) → Map TaskId (IO ())
```

## 📄 Configuration Schema

📋 Each series is a JSON object in `haskell/series/{series-id}.json`.
🏷️ The series ID is derived from the filename (e.g., `garden-thoughts.json` becomes series ID `garden-thoughts`).
📦 Parsing uses the existing `Automation.Json` module with `FromValue` and the `(.:)` and `(.:?)` operators.

### 📝 Required Fields

| 🏷️ Field | 📊 Type | 📝 Description |
|---|---|---|
| `name` | string | Display name for the series |
| `icon` | string | Emoji icon for the series |
| `scheduleHourPacific` | number | Hour in Pacific time to generate posts (0-23) |
| `models` | array of strings | Gemini model chain (primary model first, fallbacks after) |

### 📝 Optional Fields

| 🏷️ Field | 📊 Type | 📝 Default | 📝 Description |
|---|---|---|---|
| `priorityUser` | string or null | null | GitHub handle whose comments get priority flagging |
| `crossSeries` | boolean | false | When true, includes latest posts from all other series in the generation context for cross-series synthesis |

### 📄 Example Configuration

```json
{
  "name": "Garden Thoughts",
  "icon": "🌱",
  "priorityUser": "bagrounds",
  "scheduleHourPacific": 11,
  "models": ["gemini-2.5-flash", "gemini-2.5-flash-lite"]
}
```

### 🔮 Extensibility Design

📐 The schema is designed for forward-compatible evolution through optional fields with sensible defaults.
🆕 To add a new customization option (e.g., recap frequency, minimum post length, or image generation style), add an optional field to the JSON schema and use `(.:?)` in the `FromValue` instance with a default value.
🔇 Existing config files continue to work unchanged when new optional fields are added because missing keys resolve to `Nothing` via `(.:?)`.
📋 Planned future fields are documented in the Future Considerations section.

## 🔧 Convention-Based Derivation

📐 Most configuration is derived from the series ID to minimize boilerplate.

| 🏷️ Derived Value | 📐 Convention | 📝 Example for `garden-thoughts` |
|---|---|---|
| Base URL | `https://bagrounds.org/{id}` | `https://bagrounds.org/garden-thoughts` |
| Author | `[[{id}]]` | `[[garden-thoughts]]` |
| Nav Link | `[[index\|Home]] > [[{id}/index\|{icon} {name}]]` | `[[index\|Home]] > [[garden-thoughts/index\|🌱 Garden Thoughts]]` |
| Content Directory | `content/{id}/` | `content/garden-thoughts/` |
| Task ID | `blog-series:{id}` | `blog-series:garden-thoughts` |
| Env Var | `{ID_UPPER}_PRIORITY_USER` | `GARDEN_THOUGHTS_PRIORITY_USER` |

## 🆕 How to Add a New Blog Series

📋 To add a new fully automated blog series, follow the [Blog Series Launch Checklist](blog-series-launch-checklist.md). 🚀 The checklist covers all files to create, all documentation to update, and what the automation handles automatically.

📐 The technical minimum is a single JSON config file, but a complete launch PR also includes an AGENTS.md system prompt, an inaugural seed post, a product spec, and documentation updates to the README, blog-generation spec, and scheduled-tasks spec.

### 1️⃣ Create the config file

📄 Create `haskell/series/{series-id}.json` with the required fields.
📝 The filename determines the series ID.

### 2️⃣ Create the content directory with AGENTS.md and seed post

📂 Create the directory `{series-id}/` in the repo root.
📖 Add an `AGENTS.md` file with the series system prompt defining identity, voice, editorial standards, and post structure.
📰 Add an inaugural seed post to give the automation context for subsequent posts.

### 3️⃣ Update documentation

📝 See the [launch checklist](blog-series-launch-checklist.md) for the complete list of documentation files that must be updated (README, blog-generation spec, scheduled-tasks spec).

### 🔧 What happens automatically

🔍 The system discovers the config file at startup.
📐 Derives the base URL, author link, nav link, and environment variable name.
🗓️ Registers a schedule entry for the configured hour.
🤖 Registers a task runner with the configured model chain.
📋 Syncs the AGENTS.md file from the repo to the vault on every run.
📇 Generates and writes an index.md file to the vault if one does not already exist.
🧠 Shared prompt construction, date awareness, recap detection, and navigation linking work automatically.
🖼️ Image generation and backfill work automatically.

### 🚫 What you do NOT need to change

🚫 No changes to `BlogSeriesConfig.hs` — discovery replaces the hardcoded map.
🚫 No changes to `Scheduler.hs` — dynamic schedule entries are built from configs.
🚫 No changes to `RunScheduled.hs` — dynamic task runners are built from configs.
🚫 No changes to any `TaskId` type — `BlogSeries Text` handles all series dynamically.

## 🧪 Testing

🔬 `BlogSeriesDiscoveryTest.hs` contains tests across four suites:
- 📄 Parsing: valid JSON configs, null and missing priority users, error cases
- 📐 Derivation: author, base URL, nav link, env var, task ID, schedule entry
- ✅ Validation: missing fields, empty models, optional fields
- 🔬 Properties: wikilink wrapping, URL prefixing, env var format, ID preservation

🔬 Existing tests in `BlogSeriesConfigTest.hs`, `SchedulerTest.hs`, and `BlogSeriesTest.hs` were updated to work with the runtime-parameterized API.

## ⚠️ Error Handling

📋 Discovery errors are reported with clear context:
- 📄 JSON parse errors include the file path and parse error message
- ⚠️ Validation errors include the file path and description of the missing or invalid field
- ❌ If any config file fails to parse or validate, the application exits with a nonzero status

## 🔮 Future Considerations

📋 Hardcoded assumptions that could be elevated to per-series configuration:
- 📜 Post history strategy (number of full posts vs title-only posts in the prompt)
- 📅 Recap frequency (currently fixed weekly/monthly/quarterly/annual schedule)
- 📏 Minimum post length threshold (currently 200 characters)
- 🧠 System prompt template (currently shared or per-series via AGENTS.md)
- 🖼️ Image generation style or model preferences
- 📊 Maximum context window usage targets
