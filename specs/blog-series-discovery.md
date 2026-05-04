# 🔍 Blog Series Configuration — Declarative Haskell Configs

## 🎯 Overview

📋 Blog series are defined as individual Haskell modules in `haskell/src/Automation/Series/`.
🔍 The central registry `haskell/src/Automation/Series.hs` combines all series into a sorted list at compile time.
🚀 Adding a new blog series requires creating a Haskell module and registering it in the central registry.

## 🏗️ Architecture

### 📦 Components

| 🧩 Component | 📂 Path | 📝 Purpose |
|---|---|---|
| 🗂️ Series Registry | `haskell/src/Automation/Series.hs` | Exports `allSeries :: [DiscoveredSeries]` sorted by ID |
| 🗂️ Series Modules | `haskell/src/Automation/Series/*.hs` | One module per series, each exporting a `series :: DiscoveredSeries` value |
| 🔍 Derivation | `haskell/src/Automation/BlogSeriesDiscovery.hs` | `DiscoveredSeries` type and convention-based derivation functions |
| ⚙️ Series Config | `haskell/src/Automation/BlogSeriesConfig.hs` | Runtime-parameterized series metadata and lookup |
| 🗓️ Scheduler | `haskell/src/Automation/Scheduler.hs` | Dynamic schedule built from discovered series |
| 🚀 Runner | `haskell/app/RunScheduled.hs` | Uses `allSeries` at startup to build dynamic task runners |

### 🔄 Data Flow

```
📦 Automation.Series.allSeries :: [DiscoveredSeries] (compile-time)
         ↓
   ├─ deriveBlogSeriesConfig → BlogSeriesConfig (metadata)
   ├─ deriveBlogSeriesRunConfig → BlogSeriesRunConfig (models, env var)
   └─ deriveScheduleEntry → ScheduleEntry (task ID, hours)
         ↓
🗓️ buildSchedule(dynamicEntries) → full schedule (static + dynamic)
         ↓
🚀 taskRunners(context, seriesMap, runConfigs) → Map TaskId (IO ())
```

## 📄 Configuration — DiscoveredSeries Fields

📋 Each series module defines a `DiscoveredSeries` value with the following fields.

### 📝 Required Fields

| 🏷️ Field | 📊 Type | 📝 Description |
|---|---|---|
| `seriesId` | `Text` | Unique kebab-case identifier matching the content directory name |
| `seriesName` | `Text` | Display name for the series |
| `seriesIcon` | `Text` | Emoji icon for the series |
| `scheduleTime` | `TimeOfDay` | Pacific time to generate posts (use `TimeOfDay hour 0 0`) |
| `modelChain` | `NonEmpty Gemini.Model` | Primary model followed by fallbacks |
| `contextQueries` | `[ContextQuery]` | Posts to include as generation context |
| `searchGrounding` | `Bool` | Whether to use Google Search grounding |

### 📝 Optional Fields

- 🏷️ `priorityUser` is `Maybe Text`. Use `Just "handle"` or `Nothing`. It specifies the GitHub handle whose comments get priority flagging.
- 🗂️ `contextQueries` accepts `defaultContextQueries seriesId` for the standard 7 most-recent-posts behaviour, or a custom `[ContextQuery]` list for cross-series context (see Convergence for an example).

### 📄 Example Module

📄 The following Haskell shows a minimal series configuration.

```haskell
module Automation.Series.GardenThoughts (series) where

import Data.List.NonEmpty (NonEmpty ((:|)))
import Data.Time.LocalTime (TimeOfDay (..))

import qualified Automation.Gemini as Gemini
import Automation.BlogSeriesDiscovery (DiscoveredSeries (..))
import Automation.ContextQuery (defaultContextQueries)

series :: DiscoveredSeries
series = DiscoveredSeries
  { seriesId        = "garden-thoughts"
  , seriesName      = "Garden Thoughts"
  , seriesIcon      = "🌱"
  , priorityUser    = Just "bagrounds"
  , scheduleTime    = TimeOfDay 11 0 0
  , modelChain      = Gemini.Gemini25Flash :| [Gemini.Gemini25FlashLite]
  , contextQueries  = defaultContextQueries "garden-thoughts"
  , searchGrounding = False
  }
```

### 📋 Cross-Series Context Queries

📐 Series that draw context from multiple other series define their `contextQueries` explicitly using `ContextQuery` values. 📋 The Convergence series reads recent posts from its own directory and one latest post from each of the other five series.

```haskell
contextQueries =
  [ ContextQuery
      { directories    = ["convergence"]
      , conditions     = []
      , orderBy        = OrderBy Filename Descending
      , limit          = Just 7
      , limitPerSource = Nothing
      }
  , ContextQuery
      { directories    = ["auto-blog-zero", "chickie-loo", "the-noise", "positivity-bias", "systems-for-public-good"]
      , conditions     = []
      , orderBy        = OrderBy Filename Descending
      , limit          = Nothing
      , limitPerSource = Just 1
      }
  ]
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

📋 To add a new fully automated blog series, follow the [Blog Series Launch Checklist](blog-series-launch-checklist.md). 🚀 The checklist covers all files to create, all documentation to update, and what the automation handles automatically.

📐 The technical minimum is a new Haskell module and a one-line addition to the central registry, but a complete launch PR also includes an AGENTS.md system prompt, an inaugural seed post, a product spec, and documentation updates to the README, blog-generation spec, and scheduled-tasks spec.

### 1️⃣ Create the series Haskell module

📄 Create `haskell/src/Automation/Series/{PascalCaseId}.hs` following the example above.
📝 The `seriesId` field determines the series ID and must match the content directory name.

### 2️⃣ Register in the central registry

📝 Add `import qualified Automation.Series.{PascalCaseId} as {PascalCaseId}` and `{PascalCaseId}.series` to the list in `haskell/src/Automation/Series.hs`.
📦 Add both `Automation.Series.{PascalCaseId}` entries to the `exposed-modules` list in `haskell/automation.cabal`.

### 3️⃣ Create the content directory with AGENTS.md and seed post

📂 Create the directory `{series-id}/` in the repo root.
📖 Add an `AGENTS.md` file with the series system prompt defining identity, voice, editorial standards, and post structure.
📰 Add an inaugural seed post to give the automation context for subsequent posts.

### 4️⃣ Update documentation

📝 See the [launch checklist](blog-series-launch-checklist.md) for the complete list of documentation files that must be updated (README, blog-generation spec, scheduled-tasks spec).

### 🔧 What happens automatically

🔍 The system includes the series at compile time via `allSeries`.
📐 Derives the base URL, author link, nav link, and environment variable name.
🗓️ Registers a schedule entry for the configured hour.
🤖 Registers a task runner with the configured model chain.
📋 Syncs the AGENTS.md file from the repo to the vault on every run.
📇 Generates and writes an index.md file to the vault if one does not already exist.
🧠 Shared prompt construction, date awareness, recap detection, and navigation linking work automatically.
🖼️ Image generation and backfill work automatically.

## 🧪 Testing

🔬 `BlogSeriesDiscoveryTest.hs` contains tests across three suites:
- 📐 Derivation: author, base URL, nav link, env var, task ID, schedule entry, `deriveBlogSeriesConfig`, `deriveBlogSeriesRunConfig`
- 🗂️ Context queries: `deriveBlogSeriesConfig` preserves explicit and empty context query lists
- 🔬 Properties: wikilink wrapping, URL prefixing, env var format, ID and icon and name preservation

🔬 Existing tests in `BlogSeriesConfigTest.hs`, `SchedulerTest.hs`, and `BlogSeriesTest.hs` continue to use `DiscoveredSeries` values directly via `deriveBlogSeriesConfig`.

## 🔮 Future Considerations

📋 Hardcoded assumptions that could be elevated to per-series configuration:
- 📜 Post history strategy (number of full posts vs title-only posts in the prompt)
- 📅 Recap frequency (currently fixed weekly/monthly/quarterly/annual schedule)
- 📏 Minimum post length threshold (currently 200 characters)
- 🧠 System prompt template (currently shared or per-series via AGENTS.md)
- 🖼️ Image generation style or model preferences
- 📊 Maximum context window usage targets
