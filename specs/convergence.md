# 🔀 Convergence — Product & Engineering Spec

## 🎯 Overview

🔀 Convergence is a synthesis blog that reads the latest posts from every other blog series on bagrounds.org and finds a single idea that emerges from holding all those independent perspectives together — an insight not wholly present in any one series, but visible only from the vantage point of reading them all. It uses the SQL-like context query engine to pull in posts from explicitly named directories, while each other series reads only its own history.

## 🏗️ Architecture

### 🔗 Cross-Series Context via Context Queries

🔀 Convergence configures contextSources in its JSON config with two queries that drive the generation pipeline:

1. 📖 The first query reads from the convergence directory with a limit of 7, providing continuity with its own recent posts.
2. 📖 The second query reads from the five other series directories (auto-blog-zero, chickie-loo, the-noise, positivity-bias, systems-for-public-good) with limitPerSource of 1, getting the latest post from each.
3. 📦 The engine returns uniform ContextPost records. The buildBlogContext function partitions them by source directory — posts from the convergence directory become self posts, and all others become cross-series posts annotated with series name and icon from the config map.
4. 📝 A "Today Across the Blog" section is included in the user prompt with the cross-series posts as raw material.
5. 🤖 The AI then identifies a single synthetic idea from this raw material and writes a focused essay on it without naming or referencing the source series.

### 📊 Data Flow

- 🔍 discoverSeries parses convergence.json and its contextSources array.
- ⚙️ evaluateQueries resolves each query against the content directory, reading posts from the listed directories, applying WHERE filters, sorting by ORDER BY, and capping with LIMIT or limitPerSource. It returns uniform ContextPost records tagged with source directory.
- 📋 buildBlogContext partitions ContextPost results into self posts (from the convergence directory) and cross-series posts (from other directories, annotated with metadata from the series config map).
- 📝 buildBlogPrompt adds a "Today Across the Blog" section to the user prompt with a neutral data label. All behavioral instructions about how to use the cross-series posts belong in AGENTS.md, which is the single source of truth for AI behavior.
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
- ⏰ scheduleHourPacific is 16 (generates at 4 PM Pacific time).
- 🤖 models is gemini-2.5-flash with gemini-2.5-flash-lite and gemini-3.1-flash-lite-preview as fallbacks.
- 🗂️ contextSources has two queries: one reading from the convergence directory with limit 7, and one reading from the five other series directories with limitPerSource 1.

## 📐 Post Structure

🏗️ Every post is a focused essay on a single synthetic idea — one that emerges from reading all series but is not wholly present in any individual post.

1. 🌱 The Opening states the synthetic idea plainly so the reader immediately knows what the essay is about.
2. 🔬 The Development explores the idea through multiple angles, examples, and implications across at least 3 to 4 substantial sections.
3. 🌅 The Closing explains why the idea matters and leaves the reader with a generative question or provocation.

## 📅 Schedule

⏰ Convergence generates daily at 4:00 PM Pacific time. 🔀 It is scheduled after most other series (6 through 9 AM) to ensure fresh cross-series context is available.

## 📝 Editorial Standards

- 🧬 Every post must articulate a single synthetic idea not wholly present in any individual source blog.
- 🚫 Posts must not name, describe, or summarize the other blog series — the source blogs are scaffolding for the AI, not content for the reader.
- 🌱 The synthetic idea must be genuinely emergent: visible only from reading multiple independent voices, not from reading any single one.
- 🧱 Every paragraph should advance understanding of the central idea; do not pad with generic observations.
- 🌊 Write at the depth the topic deserves — if the idea has layers, explore them.

## 📅 Periodic Recaps

- 📆 Sunday: a synthetic essay on a single idea emerging from the week's cross-series posts.
- 📆 Last day of month: a synthetic essay on a single idea that crystallized this month.
- 📆 Last day of quarter: a synthetic essay on the deepest idea of the quarter.
- 📆 December 31: the definitive annual synthetic essay — the most important idea that only became visible across a full year of independent voices.

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
- 📄 convergence/AGENTS.md defines the synthesis-first personality system prompt.
- 📄 convergence/2026-04-15-the-observer-awakens.md is the inaugural seed post.
- 📄 haskell/src/Automation/ContextQuery.hs has the ContextQuery types, ContextPost, and evaluateQueries engine.
- 📄 haskell/src/Automation/BlogPrompt.hs has CrossSeriesPost and buildCrossSeriesSection for prompt formatting.
- 📄 haskell/src/Automation/BlogSeries.hs has buildBlogContext with query evaluation, partitioning, and metadata annotation.
- 📄 haskell/src/Automation/BlogSeriesConfig.hs has the bscContextQueries field.
- 📄 haskell/src/Automation/BlogSeriesDiscovery.hs handles contextSources parsing.
- 📄 specs/convergence.md is this spec.
