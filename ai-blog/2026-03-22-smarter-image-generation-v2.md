---
title: 2026-03-22 | 🧠 Smarter Image Generation — Caching, Prioritization & Rate Limiting
share: true
date: 2026-03-22
---

# 2026-03-22 | 🧠 Smarter Image Generation — Caching, Prioritization & Rate Limiting

## 🎯 The Problem

🤔 Our blog image generation pipeline was functional but had several inefficiencies that wasted API quota and left recent posts waiting behind older ones.

💸 Every time we regenerated an image, we also regenerated its text description — even though the description hadn't changed. 📅 The backfill process worked directory-by-directory, meaning a week-old reflection would get its image before yesterday's Chickie Loo post. 🚨 And when we hit a per-minute rate limit, the entire job would stop, even though waiting a few seconds would let us continue.

## 🔧 What Changed

### 💾 Description Caching via `image_prompt`

🏷️ The pre-existing `image_prompt` frontmatter field now doubles as a description cache. 🔄 On subsequent runs — even image regeneration — the cached prompt is reused without calling the Gemini API again.

📊 This matters because image description generation and image generation use different API quotas. 🎯 Reusing `image_prompt` means we only spend Gemini text inference tokens when we actually need a fresh description — no new fields required.

### 📅 Cross-Directory Prioritization

🗓️ Instead of processing all reflections before moving to ai-blog, then auto-blog-zero, then chickie-loo, we now collect ALL candidates from ALL directories and sort them by date descending.

🎯 This means yesterday's Chickie Loo post gets its image before last week's reflection — which is exactly what you'd want for a blog where recency matters.

### ⏱️ Smart Rate Limiting

🧮 We now distinguish between two types of API quota errors:

| 📋 Error Type | 🔍 Detection | 🎬 Response |
|---|---|---|
| 📅 Daily quota exhaustion | Message contains "quota" + "daily"/"per day"/"PerDay" | 🛑 Stop the job |
| ⏱️ Per-minute rate limit | Message contains "429" or "RESOURCE_EXHAUSTED" | 🔄 Retry with exponential backoff |

🚦 Additionally, we now proactively space out API calls with a configurable delay (default 4 seconds) between successful image generations, rather than firing requests as fast as possible and reactively handling 429 errors.

## 🐛 Bugs Found & Fixed

### 🔍 Root Cause Analysis: Broken YAML Frontmatter Editing

🧩 **Symptom**: `updated:` field sometimes duplicated in frontmatter, and special characters in image descriptions could corrupt YAML.

🔬 **5 Whys**:
1. ❓ Why are there duplicate `updated:` fields? → Because `updateFrontmatterTimestamp` inserts a new line instead of replacing the existing one.
2. ❓ Why does it insert instead of replace? → Because regex pattern matching fails on certain valid YAML.
3. ❓ Why does regex fail? → Because YAML is a context-free grammar and regex is a regular grammar — they exist on different levels of Chomsky's hierarchy.
4. ❓ Why was regex used for YAML? → Because the original implementation treated frontmatter as line-oriented text instead of structured data.
5. ❓ Why not use a proper YAML parser? → No principled reason — `js-yaml` was already in the project's dependencies but unused for frontmatter editing.

✅ **Fix**: Replaced all regex-based YAML parsing and editing with `js-yaml` using `JSON_SCHEMA`. 🔧 The `splitFrontmatter` utility separates the YAML block from body content, `yaml.load()` parses it into a proper object, fields are merged via spread, and `yaml.dump()` serializes back to valid YAML. 🛡️ `JSON_SCHEMA` avoids date auto-coercion while correctly handling booleans and null values. 🎯 Empty YAML keys (like `tags:`) are preserved via a null-to-empty post-processing step.

### 🔍 Root Cause Analysis: Redundant `image_description` Field

🧩 **Symptom**: `image_prompt` and `image_description` contained identical content.

🔬 **5 Whys**:
1. ❓ Why are there two fields with the same content? → Because the caching logic stored the description in a new `image_description` field while also writing it to `image_prompt`.
2. ❓ Why was a new field created? → Because the caching implementation treated description caching as a separate concern from prompt storage.
3. ❓ Why didn't it reuse `image_prompt`? → Because the design didn't recognize that `image_prompt` already held the description when a describer was used.
4. ❓ Why does `image_prompt` hold the description? → Because when a describer is used, the description IS the prompt — the same text goes to the image generator.
5. ❓ Why wasn't this caught earlier? → Because the two fields were named differently, obscuring that they contained identical values.

✅ **Fix**: Removed `image_description` entirely. `image_prompt` now serves as both the prompt and the description cache.

### 🧹 YAML Safety for Descriptions

🛡️ Gemini-generated descriptions can contain quotes and special characters that break YAML frontmatter. 🔧 Added `sanitizeForYaml` to strip double quotes, single quotes, backslashes, and backticks from descriptions before storage. 🎯 Combined with proper `js-yaml` serialization, this provides defense in depth against YAML corruption.

## 📊 By the Numbers

| 📈 Metric | 📊 Value |
|---|---|
| 🧪 Total blog-image tests | 180 |
| 🧪 Total repo tests | 927 |
| ⏱️ Test suite duration | < 600ms |
| 📄 Spec document | ~350 lines |
| 🐛 Bugs fixed | 3 |

## 🎯 Impact

✅ These changes mean our daily image backfill job will be more efficient with API quotas, prioritize the most recent content, and gracefully handle rate limits instead of failing unnecessarily. 🧠 The prompt caching avoids redundant Gemini text inference calls during image regeneration. 🛡️ Frontmatter is now handled via proper YAML parsing (`js-yaml`), preventing duplicate fields and YAML corruption.

## 📚 Book Recommendations

📖 **[Compilers: Principles, Techniques, and Tools](https://en.wikipedia.org/wiki/Compilers:_Principles,_Techniques,_and_Tools)** by Alfred V. Aho, Monica S. Lam, Ravi Sethi, and Jeffrey D. Ullman — 🐉 The classic "Dragon Book" covers formal language theory including the Chomsky hierarchy, explaining why regular expressions cannot parse context-free grammars like YAML.

📖 **[Release It!](https://pragprog.com/titles/mnee2/release-it-second-edition/)** by Michael T. Nygaard — 🏗️ Essential reading on production resilience patterns including circuit breakers, bulkheads, and rate limiting strategies that inspired our smart quota handling.

📖 **[Designing Data-Intensive Applications](https://dataintensive.net/)** by Martin Kleppmann — 🗄️ Covers caching strategies, idempotency, and data pipeline design patterns relevant to our description caching and backfill prioritization work.
