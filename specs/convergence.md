# 🔀 Convergence — Product & Engineering Spec

## 🎯 Overview

🔀 Convergence is a cross-series synthesis blog that reads the latest posts from every other blog series on bagrounds.org and finds hidden connections, tensions, and emergent themes. It uses the context query engine to pull in posts from all other series, while each other series reads only its own history.

## 🏗️ Architecture

### 🔗 Cross-Series Context via Context Queries

🔀 Convergence configures `contextSources` in its JSON config with two queries that drive the generation pipeline:

1. 📖 `{ "from": "self", "latest": 7 }` — Read up to 7 of its own recent posts for continuity
2. 📖 `{ "from": "others", "latestPerSeries": 1 }` — Read the latest post from every other series
3. 📦 Non-self posts are packaged as `CrossSeriesPost` records (series name, icon, latest post)
4. 📝 A "Today Across the Blog" section is included in the user prompt
5. 🤖 The AI then synthesizes connections across all series

### 📊 Data Flow

```
discoverSeries → parse convergence.json (contextSources array)
    ↓
evaluateQueries → resolve Self and OtherSeries queries against content directories
    ↓
buildBlogContext → populate bcxPreviousPosts (self) and bcxCrossSeriesPosts (others)
    ↓
buildBlogPrompt → add "Today Across the Blog" section to user prompt
    ↓
Gemini API → generate synthesis post
```

### 🧩 Key Types

- `ContextQuery` — A declarative query specifying scope and selection strategy for context posts
- `CrossSeriesPost` — A post from another series, containing the series name, icon, and the `BlogPost` record
- `BlogContext.bcxCrossSeriesPosts` — List of cross-series posts included in the generation context
- `BlogSeriesConfig.bscContextQueries` — List of context queries from the JSON config

## ⚙️ Configuration

| 🏷️ Field | 📊 Value | 📝 Description |
|---|---|---|
| `name` | Convergence | Display name |
| `icon` | 🔀 | Series emoji |
| `priorityUser` | bagrounds | Priority comment user |
| `scheduleHourPacific` | 10 | Generates at 10 AM PT |
| `models` | gemini-2.5-flash, gemini-2.5-flash-lite, gemini-3.1-flash-lite-preview | Model chain with Google Search grounding |
| `contextSources` | self latest 7 and others latestPerSeries 1 | Queries for own history plus latest from all other series |

## 📐 Post Structure

🏗️ Every post follows three layers:

1. **The Landscape** — Brief orientation on what each series recently wrote
2. **The Synthesis** — Deep analysis of convergences, tensions, and emergent themes across series
3. **The Questions** — Questions that can only arise from reading all series together

## 📅 Schedule

| ⏰ Time | 📋 Task |
|---|---|
| 10:00 AM PT | Generate daily Convergence post |

🔀 Scheduled after most other series (6-9 AM) to ensure fresh cross-series context is available.

## 📝 Editorial Standards

- 🔬 Every claimed connection must be substantiated with specific references to the source series
- 🧩 Connections must go deeper than surface-level topic overlap — explain the mechanism, the implication, the underlying pattern
- ⚡ Tensions and contradictions are as valuable as convergences — do not shy away from documenting disagreements between series
- 🌱 Emergent themes must be genuinely emergent — patterns that no individual series intended or could see from its local perspective
- 🪞 Meta-awareness of the recursive nature (AI reading AI) is encouraged but should serve insight, not novelty

## 📅 Periodic Recaps

- 📆 **Sunday** — Weekly synthesis of cross-series themes
- 📆 **Last day of month** — Monthly ecosystem evolution analysis
- 📆 **Last day of quarter** — Quarterly trajectory analysis
- 📆 **Dec 31** — Annual definitive synthesis

## 🧪 Testing

- ✅ Context query JSON parsing: `contextSources` arrays with self, others, all, and specific series scopes
- ✅ `evaluateQueries`: self returns self posts, others excludes self, specific series targets correctly, limits respected
- ✅ `buildCrossSeriesSection`: empty list, single post, multiple posts, body truncation, embed stripping
- ✅ `buildBlogPrompt`: includes/excludes cross-series section based on context
- ✅ `deriveBlogSeriesConfig`: preserves context queries through discovery pipeline
- ✅ Property tests: scope round-trips, SpecificSeries round-trips via parseScope/scopeToText

## 📁 Files

| 📄 File | 📝 Purpose |
|---|---|
| `haskell/series/convergence.json` | Series configuration with contextSources |
| `convergence/AGENTS.md` | System prompt defining synthesis personality |
| `convergence/2026-04-15-the-observer-awakens.md` | Inaugural seed post |
| `haskell/src/Automation/ContextQuery.hs` | ContextQuery types, evaluateQueries engine, CrossSeriesPost |
| `haskell/src/Automation/BlogPrompt.hs` | buildCrossSeriesSection prompt formatting |
| `haskell/src/Automation/BlogSeries.hs` | buildBlogContext with query evaluation |
| `haskell/src/Automation/BlogSeriesConfig.hs` | bscContextQueries field |
| `haskell/src/Automation/BlogSeriesDiscovery.hs` | contextSources parsing |
| `specs/convergence.md` | This spec |
