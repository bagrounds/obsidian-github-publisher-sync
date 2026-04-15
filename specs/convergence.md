# 🔀 Convergence — Product & Engineering Spec

## 🎯 Overview

🔀 Convergence is a cross-series synthesis blog that reads the latest posts from every other blog series on bagrounds.org and finds hidden connections, tensions, and emergent themes. It is the only series with cross-series awareness — all other series write independently.

## 🏗️ Architecture

### 🔗 Cross-Series Context

🔀 Convergence uses the `crossSeries` flag in its JSON config, which triggers the blog generation pipeline to:

1. 📖 Read the latest post from every other blog series
2. 📦 Package each post as a `CrossSeriesPost` (series name, icon, latest post)
3. 📝 Include a "Today Across the Blog" section in the user prompt
4. 🤖 The AI then synthesizes connections across all series

### 📊 Data Flow

```
discoverSeries → parse convergence.json (crossSeries: true)
    ↓
runBlogSeries → detect bscCrossSeries flag
    ↓
readCrossSeriesPosts → read latest post from each other series directory
    ↓
buildBlogContext → include CrossSeriesPost list in BlogContext
    ↓
buildBlogPrompt → add "Today Across the Blog" section to user prompt
    ↓
Gemini API → generate synthesis post
```

### 🧩 Key Types

- `CrossSeriesPost` — A post from another series, containing the series name, icon, and the `BlogPost` record
- `BlogContext.bcxCrossSeriesPosts` — List of cross-series posts included in the generation context
- `BlogSeriesConfig.bscCrossSeries` — Boolean flag enabling cross-series awareness

## ⚙️ Configuration

| 🏷️ Field | 📊 Value | 📝 Description |
|---|---|---|
| `name` | Convergence | Display name |
| `icon` | 🔀 | Series emoji |
| `priorityUser` | bagrounds | Priority comment user |
| `scheduleHourPacific` | 10 | Generates at 10 AM PT |
| `models` | gemini-2.5-flash, gemini-2.5-flash-lite, gemini-3.1-flash-lite-preview | Model chain with Google Search grounding |
| `crossSeries` | true | Enables cross-series context |

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

- ✅ `crossSeries` JSON parsing: true, false, and missing cases
- ✅ `buildCrossSeriesSection`: empty list, single post, multiple posts, body truncation, embed stripping
- ✅ `buildBlogPrompt`: includes/excludes cross-series section based on context
- ✅ `deriveBlogSeriesConfig`: preserves crossSeries flag
- ✅ Property tests: crossSeries field preserved through discovery pipeline

## 📁 Files

| 📄 File | 📝 Purpose |
|---|---|
| `haskell/series/convergence.json` | Series configuration |
| `convergence/AGENTS.md` | System prompt defining synthesis personality |
| `convergence/2026-04-15-the-observer-awakens.md` | Inaugural seed post |
| `haskell/src/Automation/BlogPrompt.hs` | CrossSeriesPost type, buildCrossSeriesSection |
| `haskell/src/Automation/BlogSeries.hs` | readCrossSeriesPosts function |
| `haskell/src/Automation/BlogSeriesConfig.hs` | bscCrossSeries field |
| `haskell/src/Automation/BlogSeriesDiscovery.hs` | dsCrossSeries parsing |
| `specs/convergence.md` | This spec |
