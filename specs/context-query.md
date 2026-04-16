# 🔎 Context Query Engine — Product & Engineering Spec

## 🎯 Overview

🔎 The context query engine is a declarative, SQL-like system for specifying which blog posts flow into each series' AI generation prompt. 📐 Instead of hard-coding context-building logic, each series declares its context requirements as a list of typed queries in its JSON config file. 🗄️ Queries use familiar SQL concepts: FROM (directory paths), WHERE (filter conditions), ORDER BY (sorting), and LIMIT (result capping).

## 🏗️ Architecture

### 🧩 Query Language Types

📐 The query language is built from composable algebraic data types.

- 🏷️ Field represents a post attribute that can be used in ORDER BY and WHERE clauses. Three variants exist: Filename, Date, and Title.
- 🔀 SortDirection has two constructors: Ascending and Descending.
- 📊 OrderBy combines a Field and a SortDirection to control result ordering.
- 🔍 WhereOperator supports three comparison modes: GreaterOrEqual, LessOrEqual, and Contains (case-insensitive substring match).
- 🔎 WhereCondition combines a field, an operator, and a text value for filtering.
- 📋 ContextQuery is the top-level query record with five fields: directories (list of directory paths), conditions (list of filter conditions), orderBy (sort specification), limit (global cap), and limitPerSource (per-directory cap).
- 📦 ContextPost is the uniform result type returned by the engine. Each post carries its sourceDirectory and the BlogPost data.

### 📊 JSON Schema

📝 Queries are specified in the optional contextSources array in series JSON config files.

- 🗂️ from is a JSON array of strings, each a content directory path relative to the content root. For example, auto-blog-zero or chickie-loo.
- 🔎 where is an optional array of condition objects. Each condition has three fields: field (one of filename, date, or title), operator (one of >=, <=, or contains), and value (the comparison text).
- 📊 orderBy is an optional string naming the field to sort by: filename, date, or title. When omitted, defaults to filename.
- 🔀 ascending is an optional boolean. When true, results are sorted in ascending order. When omitted or false, results are sorted in descending order (newest first).
- 🔢 limit is an optional number capping total results across all sources.
- 🔢 limitPerSource is an optional number capping results per source directory independently.

### 🔄 Default Behavior

📝 When contextSources is absent from a series config, the engine generates a default query that reads from the series' own directory with a limit of 7, ordered by filename descending. 🔄 For a series with id "auto-blog-zero", this is equivalent to writing the following query in JSON: from is the array containing "auto-blog-zero", limit is 7. This preserves backward compatibility with all existing configs that have no contextSources field.

### ⚙️ Query Engine

📐 The evaluateQueries function evaluates a list of queries against the content directory structure. 📤 It returns a flat list of ContextPost records, each tagged with its source directory.

📐 The engine is purely concerned with reading, filtering, sorting, and limiting. It does not partition results or annotate with series metadata. The consumer (such as buildBlogContext in BlogSeries) handles partitioning into self posts versus cross-series posts and looking up series metadata from the config map.

### 🔍 WHERE Clause Evaluation

📐 WHERE conditions filter posts after reading from disk. All conditions must match for a post to be included (AND semantics).

- ➡️ GreaterOrEqual compares the field value lexicographically against the threshold. Useful for date ranges since dates are formatted as YYYY-MM-DD.
- ⬅️ LessOrEqual compares in the opposite direction.
- 🔎 Contains performs case-insensitive substring matching. Useful for filtering by title keywords.

### 📊 Sorting

📐 ORDER BY sorts results after filtering. The orderBy field names the sort field (filename, date, or title), and the ascending boolean controls direction. The default is filename descending, which gives newest-first ordering since filenames are date-prefixed.

### 🔢 Limiting

📐 Two kinds of limits can be applied:

- 🔢 limit caps the total number of results globally after sorting.
- 🔢 limitPerSource caps results per source directory before merging. Useful for getting one latest post from each of several series.

### 🧩 Composability

📐 Multiple queries in the same config are evaluated independently and their results concatenated. 🔧 This allows expressing arbitrary combinations of sources, filters, and limits.

## 📐 Module Design

📐 The Automation.ContextQuery module is self-contained with its own types and engine. 🔗 It imports only from Automation.BlogPosts (for BlogPost and readSeriesPosts) and Automation.Json (for JSON parsing). 📦 The engine returns uniform ContextPost records without any knowledge of "self" versus "cross-series" distinctions. That classification is a prompt concern handled by the consumer.

📐 The CrossSeriesPost type lives in Automation.BlogPrompt, where it belongs — it is a prompt formatting concept, not a query concept. The buildBlogContext function in BlogSeries partitions ContextPost results by source directory and annotates cross-series posts with metadata from the BlogSeriesConfig map.

## 🧪 Testing

- ✅ Field parsing: all variants (filename, date, title) plus error case for unknown fields
- ✅ Field round-trip: fieldFromText composed with fieldToText preserves identity via property test
- ✅ JSON parsing: simple FROM with limit, multiple directories, orderBy as field name, ascending flag (true and false), limitPerSource, WHERE clauses, invalid fields, invalid operators, arrays, empty arrays
- ✅ WHERE clause evaluation: date range filtering with >= and <=, title contains with case insensitivity, multiple conditions ANDed together
- ✅ Default queries: produces one query targeting the series' own directory with limit 7
- ✅ Evaluation with real temporary directories: own directory reads, limit enforcement, cross-directory reads, limitPerSource per directory, global limit across directories, ORDER BY date ascending, source directory tagging, multiple queries combined, empty queries, missing directories

## 📁 Files

- 📄 haskell/src/Automation/ContextQuery.hs contains the types, JSON parsing, and query engine.
- 📄 haskell/src/Automation/BlogPrompt.hs contains the CrossSeriesPost type (a prompt formatting concern).
- 📄 haskell/test/Automation/ContextQueryTest.hs contains unit tests and property tests.
- 📄 specs/context-query.md is this spec.
- 📄 specs/blog-series-discovery.md documents contextSources in the JSON schema.
- 📄 specs/convergence.md documents Convergence's use of context queries.
