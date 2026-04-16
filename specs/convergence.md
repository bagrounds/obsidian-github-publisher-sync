# 🔀 Convergence — Product & Engineering Spec

## 🎯 Overview

🔀 Convergence is a cross-series synthesis blog that reads the latest posts from every other blog series on bagrounds.org and finds hidden connections, tensions, and emergent themes. It uses the SQL-like context query engine to pull in posts from explicitly named directories, while each other series reads only its own history.

## 🏗️ Architecture

### 🔗 Cross-Series Context via Context Queries

🔀 Convergence configures contextSources in its JSON config with two queries that drive the generation pipeline:

1. 📖 The first query reads from the convergence directory with a limit of 7, providing continuity with its own recent posts.
2. 📖 The second query reads from the five other series directories (auto-blog-zero, chickie-loo, the-noise, positivity-bias, systems-for-public-good) with limitPerSource of 1, getting the latest post from each.
3. 📦 The engine returns uniform ContextPost records. The buildBlogContext function partitions them by source directory — posts from the convergence directory become self posts, and all others become cross-series posts annotated with series name and icon from the config map.
4. 📝 A "Today Across the Blog" section is included in the user prompt.
5. 🤖 The AI then synthesizes connections across all series.

### 📊 Data Flow

- 🔍 discoverSeries parses convergence.json and its contextSources array.
- ⚙️ evaluateQueries resolves each query against the content directory, reading posts from the listed directories, applying WHERE filters, sorting by ORDER BY, and capping with LIMIT or limitPerSource. It returns uniform ContextPost records tagged with source directory.
- 📋 buildBlogContext partitions ContextPost results into self posts (from the convergence directory) and cross-series posts (from other directories, annotated with metadata from the series config map).
- 📝 buildBlogPrompt adds a "Today Across the Blog" section to the user prompt.
- 🤖 The Gemini API generates the synthesis post.

### 🧩 Key Types

- 📋 ContextQuery is a SQL-like query with directories (directory paths), conditions (filter conditions), orderBy (field name), ascending (optional direction flag), limit (global cap), and limitPerSource (per-directory cap).
- 📦 ContextPost is the uniform result type from the engine, carrying sourceDirectory and the BlogPost.
- 🌐 CrossSeriesPost (in BlogPrompt) carries annotated metadata (series name, icon, post) for prompt formatting.
- 📝 BlogContext.bcxCrossSeriesPosts is the list of annotated cross-series posts included in the generation context.

## ⚙️ Configuration

- 🏷️ name is Convergence.
- 🏷️ icon is the 🔀 emoji.
- 🏷️ priorityUser is bagrounds.
- ⏰ scheduleHourPacific is 10 (generates at 10 AM Pacific time).
- 🤖 models is gemini-2.5-flash with gemini-2.5-flash-lite and gemini-3.1-flash-lite-preview as fallbacks.
- 🗂️ contextSources has two queries: one reading from the convergence directory with limit 7, and one reading from the five other series directories with limitPerSource 1.

## 📐 Post Structure

🏗️ Every post follows three layers:

1. 🌍 The Landscape offers a brief orientation on what each series recently wrote.
2. 🔬 The Synthesis provides deep analysis of convergences, tensions, and emergent themes across series.
3. ❓ The Questions pose questions that can only arise from reading all series together.

## 📅 Schedule

⏰ Convergence generates daily at 10:00 AM Pacific time. 🔀 It is scheduled after most other series (6 through 9 AM) to ensure fresh cross-series context is available.

## 📝 Editorial Standards

- 🔬 Every claimed connection must be substantiated with specific references to the source series.
- 🧩 Connections must go deeper than surface-level topic overlap by explaining the mechanism, the implication, and the underlying pattern.
- ⚡ Tensions and contradictions are as valuable as convergences; documenting disagreements between series is encouraged.
- 🌱 Emergent themes must be genuinely emergent: patterns that no individual series intended or could see from its local perspective.
- 🪞 Meta-awareness of the recursive nature (AI reading AI) is encouraged but should serve insight, not novelty.

## 📅 Periodic Recaps

- 📆 Sunday: weekly synthesis of cross-series themes.
- 📆 Last day of month: monthly ecosystem evolution analysis.
- 📆 Last day of quarter: quarterly trajectory analysis.
- 📆 December 31: annual definitive synthesis.

## 🧪 Testing

- ✅ Context query JSON parsing: contextSources arrays with directory paths, limits, and limitPerSource.
- ✅ evaluateQueries: own directory returns self posts, other directories return cross-series posts, limits respected per source and globally.
- ✅ WHERE clause evaluation: date range filtering, title contains, multiple conditions ANDed.
- ✅ buildCrossSeriesSection: empty list, single post, multiple posts, body truncation, embed stripping.
- ✅ buildBlogPrompt: includes or excludes cross-series section based on context.
- ✅ deriveBlogSeriesConfig: preserves context queries through discovery pipeline.
- ✅ Property tests: Field round-trips via fieldFromText and fieldToText.

## 📁 Files

- 📄 haskell/series/convergence.json contains the series configuration with contextSources.
- 📄 convergence/AGENTS.md defines the synthesis personality system prompt.
- 📄 convergence/2026-04-15-the-observer-awakens.md is the inaugural seed post.
- 📄 haskell/src/Automation/ContextQuery.hs has the ContextQuery types, ContextPost, and evaluateQueries engine.
- 📄 haskell/src/Automation/BlogPrompt.hs has CrossSeriesPost and buildCrossSeriesSection for prompt formatting.
- 📄 haskell/src/Automation/BlogSeries.hs has buildBlogContext with query evaluation, partitioning, and metadata annotation.
- 📄 haskell/src/Automation/BlogSeriesConfig.hs has the bscContextQueries field.
- 📄 haskell/src/Automation/BlogSeriesDiscovery.hs handles contextSources parsing.
- 📄 specs/convergence.md is this spec.
