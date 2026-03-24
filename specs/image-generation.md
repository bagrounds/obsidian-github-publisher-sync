# 🖼️ Image Generation — Product & Engineering Design Spec

## 📋 Overview

🎯 The image generation system automatically creates cover images for blog posts across four content series: **reflections**, **ai-blog**, **auto-blog-zero**, and **chickie-loo**.

🏗️ It operates in two modes:
1. **Single-post generation** — triggered by individual blog workflows (auto-blog-zero, chickie-loo) immediately after a post is created
2. **Batch backfill** — a daily scheduled job that generates images for any posts missing them

---

## 🧩 Architecture

```
┌──────────────────────────────────────────────────────┐
│                 GitHub Actions Workflows               │
├──────────────┬──────────────┬────────────────────────┤
│ auto-blog-   │ chickie-     │ backfill-blog-         │
│ zero.yml     │ loo.yml      │ images.yml             │
│ (daily 4PM)  │ (daily 3PM)  │ (daily 10PM PT)        │
└──────┬───────┴──────┬───────┴────────────┬───────────┘
       │              │                    │
       ▼              ▼                    ▼
  generate-blog-  generate-blog-    backfill-blog-
  image.ts        image.ts          images.ts
  (single post)   (single post)     (provider chain)
       │              │                    │
       └──────────────┴────────────────────┘
                      │
                      ▼
              ┌───────────────┐
              │ blog-image.ts │  ← Core library
              └───────┬───────┘
                      │
          ┌───────────┼───────────┬──────────┬──────────┬───────────┐
          ▼           ▼           ▼          ▼          ▼           ▼
    ┌──────────┐ ┌──────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌──────────┐
    │Cloudflare│ │ Hugging  │ │Together│ │Pollinat│ │ Gemini  │ │ Imagen   │
    │ Workers  │ │ Face     │ │ AI     │ │ -ions  │ │ Flash   │ │ API      │
    │ AI       │ │ Inference│ │ (FLUX  │ │ .ai    │ │ (desc+  │ │          │
    │          │ │ API      │ │  free) │ │ (free) │ │  image) │ │          │
    └──────────┘ └──────────┘ └─────────┘ └─────────┘ └─────────┘ └──────────┘
```

---

## 🔄 Pipeline Flow

### 🖼️ Single Post Generation (`processNote`)

```
1. 📖 Read note content from disk
2. ♻️ Check regenerate_image flag
   ├─ true → Remove old embed, delete old image file, clear flag
   └─ false → Continue
3. 🔍 Check if image already embedded
   ├─ yes → Skip (return skipped: true)
   └─ no → Continue
4. 📝 Extract title
   ├─ missing → Skip
   └─ found → Continue
5. 🏷️ Derive image base name from file path
6. 💭 Generate prompt
   ├─ Cached image_prompt in frontmatter? → Use it (no API call)
   ├─ describePrompt available? → Call Gemini describer → Sanitize → Store as image_prompt
   └─ Neither → Build prompt from post content directly
7. 🎨 Generate image via provider (Cloudflare or Gemini)
8. 💾 Save image to attachments directory
9. 📝 Insert embed after H1, update frontmatter metadata
```

### 📦 Batch Backfill (`backfillImages`)

```
1. 📁 Scan all directories from BACKFILL_CONTENT_IDS for candidate files
2. 🗓️ Sort ALL candidates by date descending (cross-directory)
3. 🔗 Build provider chain from all configured providers
4. 🔄 For each candidate (newest first globally):
   a. ⏱️ Attempt generation with retry logic for per-minute rate limits
   b. 🛑 On quota exhaustion → switch to next provider in chain
      ├─ Retry same candidate with new provider
      └─ If no providers remain → stop entirely
   c. ⏭️ Skip and continue on non-quota errors
   d. 🔗 Update "chain" timestamps for all newer files in same directory
   e. 💤 Proactive rate limit delay between successful generations
```

---

## 🏢 Provider Architecture

### 🎯 Provider Resolution Priority

| Priority | Provider | Required Env Vars | Image Model Default |
|----------|----------|-------------------|---------------------|
| 1️⃣ | Cloudflare Workers AI | `CLOUDFLARE_API_TOKEN` + `CLOUDFLARE_ACCOUNT_ID` | `@cf/black-forest-labs/flux-1-schnell` |
| 2️⃣ | Hugging Face Inference API | `HUGGINGFACE_API_TOKEN` | `black-forest-labs/FLUX.1-schnell` |
| 3️⃣ | Together AI | `TOGETHER_API_TOKEN` | `black-forest-labs/FLUX.1-schnell-Free` |
| 4️⃣ | Pollinations.ai | `POLLINATIONS_ENABLED=true` (no API key needed) | `flux` |
| 5️⃣ | Google Gemini | `GEMINI_API_KEY` | `gemini-3.1-flash-image-preview` |
| 6️⃣ | Google Imagen | `GEMINI_API_KEY` + `IMAGE_GEMINI_MODEL=imagen-*` | N/A (explicit) |

### 🔗 Provider Chain (Fallback Behavior)

🔄 During batch backfill, providers are organized into an ordered chain. When a provider exhausts its quota (429 rate limit or daily quota), the system automatically switches to the next provider and retries the same candidate:

```
Provider 1 (Cloudflare) → quota exhausted → switch to →
Provider 2 (Hugging Face) → quota exhausted → switch to →
Provider 3 (Together AI) → quota exhausted → switch to →
Provider 4 (Pollinations.ai) → quota exhausted → switch to →
Provider 5 (Gemini) → quota exhausted → stop job
```

📋 Key behaviors:
- 🔁 The same candidate that triggered the switch is retried with the new provider
- ➡️ Once switched, all remaining candidates use the new provider (no switching back)
- 📊 Progress events include `provider_switch` with `from` and `to` fields for observability
- 🔙 Backward compatible — `fallbackProviders` defaults to empty, preserving single-provider behavior

### 💭 Description Provider (Optional)

| Provider | Required Env Vars | Model Default | Fallback Model |
|----------|-------------------|---------------|----------------|
| ✨ Gemini Describer | `GEMINI_API_KEY` | `gemini-3.1-flash-lite-preview` | `gemini-2.5-flash` |

🔑 The describer is available whenever `GEMINI_API_KEY` is set, regardless of which image provider is used.

🔄 **Model fallback**: When `gemini-3.1-flash-lite-preview` fails, the describer automatically retries with `gemini-2.5-flash` before propagating the error.

---

## 📊 Frontmatter Schema

### 🏷️ Image Metadata Fields

| Field | Type | Description | Written By |
|-------|------|-------------|------------|
| `image_date` | 📅 ISO 8601 timestamp | When the image was generated | `processNote` |
| `image_model` | 🤖 String | Model used for generation | `processNote` |
| `image_prompt` | 💬 String | Prompt/description sent to image generator (doubles as description cache) | `processNote` |
| `regenerate_image` | ✅ Boolean | Flag to force image regeneration | User (manual), cleared by `processNote` |
| `updated` | 📅 ISO 8601 timestamp | Last modification time | `backfillImages` (chain update) |

### 💾 Description Caching Strategy

🧠 The `image_prompt` field serves double duty — it stores the prompt used for image generation AND acts as the cached description for subsequent runs:

- 💰 Description generation uses **Gemini text inference** quota
- 🎨 Image generation uses **Cloudflare/Gemini image** quota
- 🔄 These are independent rate-limited resources

📋 Behavior:
1. ✅ If `image_prompt` exists in frontmatter → use it directly (zero API calls for description)
2. 🆕 If no `image_prompt` and describer available → call Gemini, sanitize output, store as `image_prompt`
3. 📝 If no describer → build prompt from content directly
4. ♻️ On image regeneration: reuse cached `image_prompt`, only regenerate the image itself

### 🧹 Description Sanitization

🛡️ Gemini-generated descriptions are sanitized before storage via `sanitizeForYaml`:
- 🚫 Removes double quotes, single quotes, backslashes, and backticks
- 📏 Collapses newlines and multiple spaces into single spaces
- ✂️ Trims leading/trailing whitespace
- 🎯 This prevents YAML parsing issues in Obsidian's frontmatter parser

---

## ⏱️ Rate Limiting Strategy

### 🔍 Error Classification

| Error Type | Detection | Response |
|------------|-----------|----------|
| 📅 Daily quota exhaustion | Message contains `"quota"` AND (`"daily"` or `"per day"` or `"PerDay"`) | 🔄 Switch to next provider in chain (or stop if no providers remain) |
| ⏱️ Per-minute rate limit | Message contains `"429"`, `"RESOURCE_EXHAUSTED"`, or `"quota"` (but not daily) | 🔄 Retry with exponential backoff (up to 3 retries), then switch provider |
| 🚫 Provider unavailable | Message contains `"410"`, `"401"`, `"403"`, `"no longer supported"`, or `"deprecated"` | 🔄 Immediately switch to next provider (no retries — permanent failure) |
| ❌ Other errors | Everything else | ⏭️ Log and skip to next candidate |

### 🔄 Retry Mechanism

```
Attempt 1 → fail (per-minute limit)
  Wait: parsed server delay OR 5s default backoff
Attempt 2 → fail (per-minute limit)
  Wait: parsed server delay OR 10s (doubled)
Attempt 3 → fail (per-minute limit)
  Wait: parsed server delay OR 20s (doubled, capped at 60s)
Attempt 4 → fail → propagate error (exhausted retries)
```

### 🚦 Proactive Rate Limiting

🎯 Rather than reactively hitting limits, the system proactively spaces out API calls:

- ⏲️ Default delay: **4 seconds** between successful image generations
- ⚙️ Configurable via `minDelayMs` parameter in `BackfillConfig`
- 🧪 Tests can inject `sleep: async () => {}` to skip delays

---

## 📅 Backfill Prioritization

### 🎯 Cross-Directory Date-Based Ordering

🗓️ All candidates from all `BACKFILL_CONTENT_IDS` directories are collected and sorted by date descending:

```
Example with 5 directories (derived from BACKFILL_CONTENT_IDS):
  reflections/2026-03-15.md                → date: 2026-03-15
  ai-blog/2026-03-20-post.md               → date: 2026-03-20
  auto-blog-zero/2026-03-21-x.md           → date: 2026-03-21
  chickie-loo/2026-03-19-y.md              → date: 2026-03-19
  systems-for-public-good/2026-03-22-z.md  → date: 2026-03-22

Processing order (newest first):
  1. systems-for-public-good/2026-03-22-z.md  (most recent)
  2. auto-blog-zero/2026-03-21-x.md
  3. ai-blog/2026-03-20-post.md
  4. chickie-loo/2026-03-19-y.md
  5. reflections/2026-03-15.md                (oldest)
```

### 🔗 Chain Updates

🔄 When an image is generated for a post, all newer files in the **same directory** receive an `updated:` timestamp:

```
Directory: chickie-loo/
  2026-03-22-newest.md  (has image) ← gets updated: timestamp
  2026-03-21-middle.md  (has image) ← gets updated: timestamp
  2026-03-20-target.md  (NO image)  ← image generated + updated: timestamp
```

🎯 This propagates "freshness" signals for content feeds and sort ordering.

---

## 📁 File Naming Convention

### 🏷️ Image Base Name Derivation

📂 Image names are derived from the note's **file path** (not the title):

```
Note path: /repo/chickie-loo/2026-03-22-weekly-recap.md
Image name: chickie-loo-2026-03-22-weekly-recap.jpg
```

🛡️ This prevents naming collisions between directories that might have similar titles.

### 🔢 Conflict Resolution

🔄 If the base name already exists, suffixes are appended:
- `chickie-loo-2026-03-22-weekly-recap.jpg` (first)
- `chickie-loo-2026-03-22-weekly-recap-2.jpg` (second)
- `chickie-loo-2026-03-22-weekly-recap-3.jpg` (third)

---

## 🔧 Configuration Reference

### 🔐 Secrets (GitHub Actions)

| Variable | Required | Purpose |
|----------|----------|---------|
| `CLOUDFLARE_API_TOKEN` | ⚡ Optional | Cloudflare Workers AI authentication |
| `CLOUDFLARE_ACCOUNT_ID` | ⚡ Optional | Cloudflare account identifier |
| `HUGGINGFACE_API_TOKEN` | ⚡ Optional | Hugging Face Inference API authentication |
| `GEMINI_API_KEY` | ✅ Required | Google Gemini API key (description + fallback image) |
| `GCP_SERVICE_ACCOUNT_KEY` | ⚡ Optional | GCP service account for quota monitoring |
| `OBSIDIAN_AUTH_TOKEN` | ✅ Required | Obsidian vault sync authentication |
| `OBSIDIAN_VAULT_NAME` | ✅ Required | Obsidian vault name for sync |

### ⚙️ Config Variables (GitHub Actions)

| Variable | Default | Purpose |
|----------|---------|---------|
| `CLOUDFLARE_IMAGE_MODEL` | `@cf/black-forest-labs/flux-1-schnell` | Cloudflare image model |
| `HUGGINGFACE_IMAGE_MODEL` | `black-forest-labs/FLUX.1-schnell` | Hugging Face image model |
| `IMAGE_GEMINI_MODEL` | `gemini-3.1-flash-image-preview` | Gemini image generation model |
| `PROMPT_DESCRIBER_MODEL` | `gemini-3.1-flash-lite-preview` | Gemini description model |

### 🤗 Hugging Face Setup Guide

📋 To set up Hugging Face as a fallback image generation provider:

1. 🌐 Create a free account at [huggingface.co](https://huggingface.co/join)
2. ⚙️ Navigate to **Settings** → **Access Tokens** (https://huggingface.co/settings/tokens)
3. 🔑 Click **Create new token** with the following settings:
   - **Name**: `obsidian-image-gen` (or any descriptive name)
   - **Type**: Fine-grained
   - **Permissions**: Select **Make calls to the serverless Inference API** under Inference
4. 📋 Copy the token (starts with `hf_`)
5. 🔐 In your GitHub repository, go to **Settings** → **Secrets and variables** → **Actions**
6. ➕ Click **New repository secret**, name it `HUGGINGFACE_API_TOKEN`, paste the token
7. ⚙️ (Optional) To use a different model, add a repository variable `HUGGINGFACE_IMAGE_MODEL`

🆓 **Free tier**: No credit card required. The free tier provides limited compute (~$0.10/month equivalent). Image generation is more compute-intensive than text, so expect a few dozen images per day. Rate limits return HTTP 429.

🎯 **Default model**: `black-forest-labs/FLUX.1-schnell` — the same model family used by Cloudflare, ensuring consistent image quality across providers.

---

## 🐛 Known Issues & Potential Bugs

### 1️⃣ syncAttachmentsDir Skips Updated Files

📍 `blog-image.ts:syncAttachmentsDir` only copies files that **don't exist** in the vault. If an image is regenerated with a different name (which is the current behavior since `resolveUniqueImageName` generates unique names), the old image remains orphaned in the vault.

🎯 Impact: Low — orphaned files waste storage but don't cause functional issues. The new image gets synced correctly.

### 2️⃣ Chain Timestamp Updates May Cause Unnecessary Syncs

📍 `backfillImages` updates `updated:` timestamps on ALL files in the chain, even if they haven't meaningfully changed. This triggers `syncMarkdownDir` to re-sync those files to the vault.

🎯 Impact: Medium — increased sync bandwidth and potential write amplification on the Obsidian vault.

### 3️⃣ ~~extractFrontmatterValue Limited to Simple Single-Line Values~~ (Fixed)

📍 Previously used regex to parse and edit YAML, which exists on a different level of Chomsky's hierarchy (YAML is context-free, regex is regular).

✅ Fix: Replaced all regex-based YAML handling with `js-yaml` library using `JSON_SCHEMA`. See Fixed Bugs below.

### 4️⃣ Future Reflection Filtering Only Applies to Reflections Directory

📍 The `date > today` skip logic only applies when `id === "reflections"`. If other directories contained future-dated posts, they would be processed.

🎯 Impact: Low — only reflections have future-dated posts by convention.

### 5️⃣ Cloudflare Error Responses May Not Match Quota Detection Patterns

📍 `isQuotaError` checks for "429", "RESOURCE_EXHAUSTED", and "quota" in error messages. Cloudflare API errors may use different patterns (e.g., HTTP 429 status without these keywords in the message body).

🎯 Impact: Medium — Cloudflare rate limits might not be properly detected, causing the job to fail instead of retrying or stopping gracefully.

### 6️⃣ Image Embed Insertion Assumes H1 Exists

📍 `insertImageEmbed` returns content unchanged if no H1 is found. However, `processNote` doesn't check if the embed was actually inserted — it proceeds to save metadata even though the image won't be visible.

🎯 Impact: Low — `extractTitle` already ensures a title exists, and posts without H1 generally also lack a frontmatter title, so they'd be skipped earlier.

---

## ✅ Fixed Bugs

### 🔧 Regex-Based YAML Parsing Replaced with `js-yaml` (Fixed)

📍 All frontmatter functions (`extractFrontmatterValue`, `updateFrontmatterFields`, `updateFrontmatterTimestamp`) used regex patterns to parse and edit YAML. This was fundamentally incorrect — YAML is a context-free grammar while regex is a regular grammar (different levels of Chomsky's hierarchy). This caused duplicate fields, mishandled empty values, and fragile special character handling.

🔍 Root cause: The original implementation treated frontmatter as line-oriented text instead of structured data, despite `js-yaml` already being in the project's dependencies.

✅ Fix: Replaced all regex-based YAML handling with `js-yaml` using `JSON_SCHEMA`:
- 📋 `splitFrontmatter` separates the YAML block from body content
- 📖 `yaml.load()` with `JSON_SCHEMA` parses into a proper object (avoids date auto-coercion)
- ✏️ Fields are merged via object spread (`{ ...doc, ...fields }`)
- 💾 `yaml.dump()` with `JSON_SCHEMA` serializes back to valid YAML
- 🔄 Null values converted to empty YAML keys for Obsidian compatibility (`tags:` instead of `tags: null`)

### 🔧 Redundant `image_description` Field (Fixed)

📍 The `image_description` frontmatter field was a redundant copy of `image_prompt`. Both contained identical content — the Gemini-generated visual description.

🔍 Root cause: The caching logic added a new field instead of recognizing that `image_prompt` already served as the cache.

✅ Fix: Removed `image_description` entirely. `image_prompt` now serves as both the prompt sent to the image generator and the cached description for subsequent runs.

### 🔧 Unquoted Special Characters in Descriptions (Fixed)

📍 Gemini-generated descriptions could contain quotes, backslashes, and other YAML-breaking characters.

🔍 Root cause: Descriptions were stored directly from Gemini's response without sanitization.

✅ Fix: Added `sanitizeForYaml` that strips quotes, backslashes, backticks, and collapses whitespace before storage. Combined with proper `js-yaml` serialization, this provides defense in depth.

---

## 🧪 Testing Strategy

### 📊 Test Coverage (211 tests, 42 suites)

| Category | Tests | Description |
|----------|-------|-------------|
| 🔍 Image detection | 11 | Obsidian wiki, Markdown, various formats |
| 🏷️ Name generation | 16 | Kebab-case, path-based, conflict resolution |
| 📝 Content processing | 10 | Frontmatter stripping, embed removal, syntax cleaning |
| 📋 Frontmatter operations | 23 | YAML parsing, updates, regeneration, sanitization, arrays, empty values, colons |
| 🖼️ processNote | 11 | Generation, skipping, metadata, describer, prompt caching, sanitization |
| 📦 backfillImages | 14 | Chain updates, missing dirs, errors, prioritization, rate limits |
| 🔌 Provider resolution | 18 | Cloudflare, Gemini, Imagen, HuggingFace, describer, multi-provider chain |
| ⏱️ Rate limiting | 12 | isDailyQuotaError, parseRetryDelay, retry logic, proactive delays |
| 🔗 Provider chain fallback | 7 | Quota switch, multi-provider chain, backward compat, progress events |
| 🚫 Provider unavailable | 12 | isProviderUnavailableError detection, 410/401/403 switch, no-retry, all-unavailable stop |

### 🎯 Key Test Properties

- ✅ All tests use in-memory file systems (temp directories)
- ✅ No real API calls — generators and describers are mocked
- ✅ Sleep functions are injectable for fast test execution
- ✅ Event tracking via `onProgress` callback for behavior verification

---

## 🗺️ Future Considerations

### 🔮 Potential Improvements

1. 🔄 **Shared rate limit module** — Extract `isDailyQuotaError`, `parseRetryDelay`, and retry logic into a shared `gemini-rate-limit.ts` module used by both `blog-image.ts` and `internal-linking.ts`
2. 📊 **Quota-aware scheduling** — Check remaining quota before starting backfill and skip if insufficient
3. 🗑️ **Orphan image cleanup** — Periodic job to remove attachment files not referenced by any post
4. 🔄 **Parallel generation** — Generate images for posts in different directories concurrently (with shared rate limiter)
5. 📈 **Progress persistence** — Track backfill state across runs to avoid re-scanning completed directories
6. 🏪 **Additional providers** — The provider chain architecture makes it easy to add new providers. To add one: implement an `ImageGenerator` function, add a `makeXxxGenerator` factory, and add a block to `resolveImageProviders` that checks for the provider's env vars
