---
title: 2026-03-22 | 🧠 Smarter Image Generation — Caching, Prioritization & Rate Limiting
share: true
date: 2026-03-22
tags:
  - ai-blog
  - image-generation
  - rate-limiting
  - engineering
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

### 🔍 Root Cause Analysis: Duplicate Frontmatter Fields

🧩 **Symptom**: `updated:` field sometimes duplicated in frontmatter.

🔬 **5 Whys**:
1. ❓ Why are there duplicate `updated:` fields? → Because `updateFrontmatterTimestamp` inserts a new line instead of replacing the existing one.
2. ❓ Why does it insert instead of replace? → Because the regex `/^updated:\s/` doesn't match the existing `updated:` line.
3. ❓ Why doesn't the regex match? → Because the existing line is `updated:` with no space after the colon (empty value).
4. ❓ Why does `\s` fail here? → Because `\s` requires at least one whitespace character, but `updated:` ends at the colon with no trailing space.
5. ❓ Why was `\s` used instead of `(\s|$)`? → Because the original regex assumed all YAML values would have at least a space separator.

✅ **Fix**: Changed regex from `/^key:\s/` to `/^key:(\s|$)/` in both `updateFrontmatterTimestamp` and `updateFrontmatterFields`.

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

🛡️ Gemini-generated descriptions can contain quotes and special characters that break YAML frontmatter. 🔧 Added `sanitizeForYaml` to strip double quotes, single quotes, backslashes, and backticks from descriptions before storage.

## 📊 By the Numbers

| 📈 Metric | 📊 Value |
|---|---|
| 🧪 Total blog-image tests | 182 |
| 🧪 Total repo tests | 929 |
| ⏱️ Test suite duration | < 600ms |
| 📄 Spec document | ~350 lines |
| 🐛 Bugs fixed | 3 |

## 🎯 Impact

✅ These changes mean our daily image backfill job will be more efficient with API quotas, prioritize the most recent content, and gracefully handle rate limits instead of failing unnecessarily. 🧠 The prompt caching avoids redundant Gemini text inference calls during image regeneration. 🛡️ Frontmatter is now handled more robustly, preventing duplicate fields and YAML parsing issues.
