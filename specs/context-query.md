# 🔎 Context Query Engine — Product & Engineering Spec

## 🎯 Overview

🔎 The context query engine is a declarative system for specifying which blog posts flow into each series' AI generation prompt. 📐 Instead of hard-coding context-building logic, each series declares its context requirements as a list of typed queries in its JSON config file.

## 🏗️ Architecture

### 🧩 Query Language Types

📐 Three algebraic data types model the query language.

| 🏷️ Type | 📝 Description |
|---|---|
| `ContextScope` | Where to look: `Self`, `OtherSeries`, `AllSeries`, or `SpecificSeries <id>` |
| `SelectionStrategy` | How many to take: `Latest N` (total) or `LatestPerSeries N` (per series) |
| `ContextQuery` | Combines a scope and a selection strategy |

### 📊 JSON Schema

📝 Queries are specified in the optional `contextSources` array in series JSON config files.

| 🏷️ Field | 📊 Type | 📝 Description |
|---|---|---|
| `from` | string | Scope: `"self"`, `"others"`, `"all"`, or `"series:<id>"` |
| `latest` | number | Maximum total posts across the scope (mutually exclusive with `latestPerSeries`) |
| `latestPerSeries` | number | Maximum posts per series within scope (mutually exclusive with `latest`) |

📝 Exactly one of `latest` or `latestPerSeries` must be specified per query object.

### 🔄 Default Behavior

📝 When `contextSources` is absent from a series config, the default is:

```json
[{"from": "self", "latest": 7}]
```

🔄 This preserves backward compatibility with all existing configs.

### ⚙️ Query Engine

📐 The `evaluateQueries` function evaluates a list of queries against the content directory structure. 📤 It returns two lists:

1. **Self posts** — Posts from the current series (used in the "Recent Posts" prompt section)
2. **Cross-series posts** — Posts from other series (used in the "Today Across the Blog" prompt section)

📐 Classification depends on whether the resolved series matches the current series.

### 🔀 Scope Resolution

| 📍 Scope | 📝 Behavior |
|---|---|
| `Self` | Reads from the current series directory only |
| `OtherSeries` | Reads from every series directory except the current one |
| `AllSeries` | Reads from all series directories including the current one |
| `SpecificSeries <id>` | Reads from exactly one named series directory |

### 📊 Selection Strategies

| 📊 Strategy | 📝 Behavior |
|---|---|
| `Latest N` | Sorts all posts by filename descending, takes the top N |
| `LatestPerSeries N` | Takes the top N from each series independently |

### 🧩 Composability

📐 Multiple queries in the same config are evaluated independently and their results concatenated. 🔧 This allows expressing arbitrary combinations of sources and limits.

## 📐 Module Design

📐 The `Automation.ContextQuery` module is self-contained with its own types and engine. 🔗 It imports only from `Automation.BlogPosts` (for `BlogPost` and `readSeriesPosts`) and `Automation.Json` (for JSON parsing). 📦 A `SeriesInfo` type carries minimal metadata (id, name, icon) needed by the engine, keeping it decoupled from the full `BlogSeriesConfig` and avoiding circular dependencies.

## 🧪 Testing

- ✅ Scope parsing: all four scope variants plus error cases
- ✅ Scope round-trip: `parseScope . scopeToText` preserves identity
- ✅ JSON parsing: valid queries, arrays, missing fields, conflicting fields, invalid scopes
- ✅ Default queries: single self-latest-7 query
- ✅ Evaluation with real temporary directories: self, others, all, specific, combined, empty, missing, metadata

## 📁 Files

| 📄 File | 📝 Purpose |
|---|---|
| `haskell/src/Automation/ContextQuery.hs` | Types, JSON parsing, query engine |
| `haskell/test/Automation/ContextQueryTest.hs` | Unit tests and property tests |
| `specs/context-query.md` | This spec |
| `specs/blog-series-discovery.md` | Documents `contextSources` in the JSON schema |
| `specs/convergence.md` | Documents Convergence's use of context queries |
