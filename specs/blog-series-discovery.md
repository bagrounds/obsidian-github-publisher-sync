# 🔍 Blog Series Auto-Discovery — Declarative Configuration

## 🎯 Overview

📋 Blog series are defined as individual Dhall configuration files in the `haskell/series/` directory.
🔍 The system auto-discovers all `.dhall` files at startup and derives everything needed to run each series.
🚀 Adding a new blog series requires only creating a single config file — no Haskell source changes.

## 🏗️ Architecture

### 📦 Components

| 🧩 Component | 📂 Path | 📝 Purpose |
|---|---|---|
| 🔍 Discovery | `haskell/src/Automation/BlogSeriesDiscovery.hs` | Dhall config parser, validation, convention-based derivation |
| ⚙️ Series Config | `haskell/src/Automation/BlogSeriesConfig.hs` | Runtime-parameterized series metadata and lookup |
| 🗓️ Scheduler | `haskell/src/Automation/Scheduler.hs` | Dynamic schedule built from discovered series |
| 🚀 Runner | `haskell/app/RunScheduled.hs` | Discovers series at startup, builds dynamic task runners |

### 🔄 Data Flow

```
📂 haskell/series/*.dhall (config files on disk)
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

## 📄 Configuration Format

📋 Each series is a Dhall record in `haskell/series/{series-id}.dhall`.
🏷️ The series ID is derived from the filename (e.g., `garden-thoughts.dhall` becomes series ID `garden-thoughts`).

### 📝 Required Fields

| 🏷️ Field | 📊 Type | 📝 Description |
|---|---|---|
| `name` | Text | Display name for the series |
| `icon` | Text | Emoji icon for the series |
| `scheduleHourPacific` | Natural | Hour in Pacific time to generate posts (0-23) |
| `models` | List Text | Gemini model chain (primary model first, fallbacks after) |
| `postTimeUtc` | Text | UTC time for post metadata (e.g., "16:00") |

### 📝 Optional Fields

| 🏷️ Field | 📊 Type | 📝 Default | 📝 Description |
|---|---|---|---|
| `priorityUser` | Optional Text | None | GitHub handle whose comments get priority flagging |

### 📄 Example Configuration

```dhall
{ name = "Garden Thoughts"
, icon = "🌱"
, priorityUser = Some "bagrounds"
, scheduleHourPacific = 11
, models = [ "gemini-2.5-flash", "gemini-2.5-flash-lite" ]
, postTimeUtc = "19:00"
}
```

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

📋 To add a new fully automated blog series, create a single file.

### 1️⃣ Create the config file

📄 Create `haskell/series/{series-id}.dhall` with the required fields.
📝 The filename determines the series ID.

### 2️⃣ Create the content directory

📂 Create the directory `content/{series-id}/` in the Obsidian vault.
📖 Optionally add an `AGENTS.md` file with a custom system prompt.

### 🔧 What happens automatically

🔍 The system discovers the config file at startup.
📐 Derives the base URL, author link, nav link, and environment variable name.
🗓️ Registers a schedule entry for the configured hour.
🤖 Registers a task runner with the configured model chain.
📇 Generates an index page on the first run.
🧠 Shared prompt construction, date awareness, recap detection, and navigation linking work automatically.
🖼️ Image generation and backfill work automatically.

### 🚫 What you do NOT need to change

🚫 No changes to `BlogSeriesConfig.hs` — discovery replaces the hardcoded map.
🚫 No changes to `Scheduler.hs` — dynamic schedule entries are built from configs.
🚫 No changes to `RunScheduled.hs` — dynamic task runners are built from configs.
🚫 No changes to any `TaskId` type — `BlogSeries Text` handles all series dynamically.

## 🧪 Testing

🔬 `BlogSeriesDiscoveryTest.hs` contains 42 tests across 4 suites:
- 📄 Parsing: valid configs, None/Some priority users, comments, error cases
- 📐 Derivation: author, base URL, nav link, env var, task ID, schedule entry
- ✅ Validation: missing fields, empty models, optional fields
- 🔬 Properties: wikilink wrapping, URL prefixing, env var format, ID preservation

🔬 Existing tests in `BlogSeriesConfigTest.hs`, `SchedulerTest.hs`, and `BlogSeriesTest.hs` were updated to work with the runtime-parameterized API.

## ⚠️ Error Handling

📋 Discovery errors are reported with clear context:
- 📄 Parse errors include the file path and Parsec error message
- ⚠️ Validation errors include the file path and description of the missing or invalid field
- ❌ If any config file fails to parse or validate, the application exits with a nonzero status

## 🔄 Migration to Official Dhall Library

📦 The config files use valid Dhall syntax, but the parser is currently a temporary Parsec-based implementation.
🚫 The official `dhall` Haskell library (1.42.3, latest on Hackage) cannot build with GHC 9.14.1 due to an upper bound on `template-haskell` (requires `< 2.24`, but GHC 9.14.1 ships 2.24.0.0).
🔧 PR [dhall-haskell#2704](https://github.com/dhall-lang/dhall-haskell/pull/2704) (merged Feb 2026) adds GHC 9.14 support but has not been released to Hackage.

### ✅ Validation Against Official Parser

🔬 All three config files have been validated against the official Dhall parser (python-dhall 0.1.16, which wraps the Rust dhall-rust implementation of the Dhall standard).
📊 All 18 fields across all 3 config files produce identical parsed values between the official parser and our Parsec bridge.
🧪 Validated variants: `Some` values, record syntax with leading commas, emoji in string literals, multi-word names, and multi-element model lists.

### ⚠️ Known Risks and Mitigations

🔍 Risk 1: the Parsec parser does not handle Dhall escape sequences (backslash-n, backslash-t, and so on) in double-quoted strings.
🛡️ Mitigation: none of our config values require escape sequences. Names, icons, model identifiers, and time strings are all plain ASCII or emoji. The parser actively rejects backslashes, so any attempt to use them would be a loud parse error rather than a silent mismatch.

🔍 Risk 2: the Parsec parser rejects unknown field names instead of ignoring them. The official Dhall library with a `FromDhall` instance would silently ignore extra fields.
🛡️ Mitigation: this is actually stricter than necessary and catches typos. When migrating, we should decide whether to keep this strictness (via a custom `Dhall.Decoder`) or adopt Dhall's default lenient behavior.

🔍 Risk 3: the Parsec parser does not support Dhall language features beyond simple records: no `let` bindings, no imports, no type annotations, no string interpolation, no multiline strings (Dhall single-quoted syntax).
🛡️ Mitigation: our configs intentionally use the simplest possible Dhall subset. If a future config needs advanced features, it would fail loudly at parse time, signaling it is time to complete the migration.

🔍 Risk 4: the official Dhall library will add significant transitive dependencies (megaparsec, cborg, serialise, aeson, and others), increasing build time and binary size.
🛡️ Mitigation: evaluate the build time impact before merging and consider whether the benefits justify the cost for our simple record configs.

### 📋 Migration Plan

1. 🔍 Monitor Hackage for a dhall release with GHC 9.14 support (dhall 1.43+ or a revised 1.42.x)
2. 📦 Add `dhall` as a build dependency in `automation.cabal`
3. 🔄 Replace `parseDhallConfig` with `Dhall.input Dhall.auto` using a Dhall `FromDhall` instance for `DiscoveredSeries`
4. 🧹 Remove the Parsec parser code from `BlogSeriesDiscovery.hs`
5. ✅ No config file changes needed — the files are already valid Dhall
6. 🧪 Keep the existing 42 tests as regression tests — they validate the parsed output, not the parser itself

## 🔮 Future Considerations

📋 Hardcoded assumptions that could be elevated to per-series configuration:
- 📜 Post history strategy (number of full posts vs title-only posts in the prompt)
- 📅 Recap frequency (currently fixed weekly/monthly/quarterly/annual schedule)
- 📏 Minimum post length threshold (currently 200 characters)
- 🧠 System prompt template (currently shared or per-series via AGENTS.md)
- 🖼️ Image generation style or model preferences
- 📊 Maximum context window usage targets
