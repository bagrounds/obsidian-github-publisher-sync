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
  (single post)   (single post)     (all directories)
       │              │                    │
       └──────────────┴────────────────────┘
                      │
                      ▼
              ┌───────────────┐
              │ blog-image.ts │  ← Core library
              └───────┬───────┘
                      │
          ┌───────────┼───────────┐
          ▼           ▼           ▼
    ┌──────────┐ ┌─────────┐ ┌──────────┐
    │Cloudflare│ │ Gemini  │ │ Imagen   │
    │ Workers  │ │ Flash   │ │ API      │
    │ AI       │ │ (desc+  │ │          │
    │          │ │  image) │ │          │
    └──────────┘ └─────────┘ └──────────┘
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
   ├─ Cached image_description in frontmatter? → Use it (no API call)
   ├─ describePrompt available? → Call Gemini describer → Cache in frontmatter
   └─ Neither → Build prompt from post content directly
7. 🎨 Generate image via provider (Cloudflare or Gemini)
8. 💾 Save image to attachments directory
9. 📝 Insert embed after H1, update frontmatter metadata
```

### 📦 Batch Backfill (`backfillImages`)

```
1. 📁 Scan all directories for candidate files
2. 🗓️ Sort ALL candidates by date descending (cross-directory)
3. 🔄 For each candidate (newest first globally):
   a. ⏱️ Attempt generation with retry logic for per-minute rate limits
   b. 🛑 Stop entirely on daily quota exhaustion
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
| 2️⃣ | Google Gemini | `GEMINI_API_KEY` | `gemini-3.1-flash-image-preview` |
| 3️⃣ | Google Imagen | `GEMINI_API_KEY` + `IMAGE_GEMINI_MODEL=imagen-*` | N/A (explicit) |

### 💭 Description Provider (Optional)

| Provider | Required Env Vars | Model Default |
|----------|-------------------|---------------|
| ✨ Gemini Describer | `GEMINI_API_KEY` | `gemini-3.1-flash-lite-preview` |

🔑 The describer is available whenever `GEMINI_API_KEY` is set, regardless of which image provider is used.

---

## 📊 Frontmatter Schema

### 🏷️ Image Metadata Fields

| Field | Type | Description | Written By |
|-------|------|-------------|------------|
| `image_date` | 📅 ISO 8601 timestamp | When the image was generated | `processNote` |
| `image_model` | 🤖 String | Model used for generation | `processNote` |
| `image_prompt` | 💬 String | Prompt sent to image generator | `processNote` |
| `image_description` | 📝 String | Cached Gemini-generated visual description | `processNote` (only when describer used) |
| `regenerate_image` | ✅ Boolean | Flag to force image regeneration | User (manual), cleared by `processNote` |
| `updated` | 📅 ISO 8601 timestamp | Last modification time | `backfillImages` (chain update) |

### 💾 Description Caching Strategy

🧠 The `image_description` field decouples description generation from image generation:

- 💰 Description generation uses **Gemini text inference** quota
- 🎨 Image generation uses **Cloudflare/Gemini image** quota
- 🔄 These are independent rate-limited resources

📋 Behavior:
1. ✅ If `image_description` exists in frontmatter → use it directly (zero API calls for description)
2. 🆕 If no `image_description` and describer available → call Gemini, cache result in frontmatter
3. 📝 If no describer → build prompt from content directly (no `image_description` stored)
4. ♻️ On image regeneration: reuse cached description, only regenerate the image itself

---

## ⏱️ Rate Limiting Strategy

### 🔍 Error Classification

| Error Type | Detection | Response |
|------------|-----------|----------|
| 📅 Daily quota exhaustion | Message contains `"quota"` AND (`"daily"` or `"per day"` or `"PerDay"`) | 🛑 Stop the entire job immediately |
| ⏱️ Per-minute rate limit | Message contains `"429"`, `"RESOURCE_EXHAUSTED"`, or `"quota"` (but not daily) | 🔄 Retry with exponential backoff (up to 3 retries) |
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

🗓️ All candidates from all directories are collected and sorted by date descending:

```
Example with 4 directories:
  reflections/2026-03-15.md        → date: 2026-03-15
  ai-blog/2026-03-20-post.md       → date: 2026-03-20
  auto-blog-zero/2026-03-21-x.md   → date: 2026-03-21
  chickie-loo/2026-03-19-y.md      → date: 2026-03-19

Processing order (newest first):
  1. auto-blog-zero/2026-03-21-x.md  (most recent)
  2. ai-blog/2026-03-20-post.md
  3. chickie-loo/2026-03-19-y.md
  4. reflections/2026-03-15.md        (oldest)
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
| `GEMINI_API_KEY` | ✅ Required | Google Gemini API key (description + fallback image) |
| `GCP_SERVICE_ACCOUNT_KEY` | ⚡ Optional | GCP service account for quota monitoring |
| `OBSIDIAN_AUTH_TOKEN` | ✅ Required | Obsidian vault sync authentication |
| `OBSIDIAN_VAULT_NAME` | ✅ Required | Obsidian vault name for sync |

### ⚙️ Config Variables (GitHub Actions)

| Variable | Default | Purpose |
|----------|---------|---------|
| `CLOUDFLARE_IMAGE_MODEL` | `@cf/black-forest-labs/flux-1-schnell` | Cloudflare image model |
| `IMAGE_GEMINI_MODEL` | `gemini-3.1-flash-image-preview` | Gemini image generation model |
| `PROMPT_DESCRIBER_MODEL` | `gemini-3.1-flash-lite-preview` | Gemini description model |

---

## 🐛 Known Issues & Potential Bugs

### 1️⃣ syncAttachmentsDir Skips Updated Files

📍 `blog-image.ts:syncAttachmentsDir` only copies files that **don't exist** in the vault. If an image is regenerated with a different name (which is the current behavior since `resolveUniqueImageName` generates unique names), the old image remains orphaned in the vault.

🎯 Impact: Low — orphaned files waste storage but don't cause functional issues. The new image gets synced correctly.

### 2️⃣ Chain Timestamp Updates May Cause Unnecessary Syncs

📍 `backfillImages` updates `updated:` timestamps on ALL files in the chain, even if they haven't meaningfully changed. This triggers `syncMarkdownDir` to re-sync those files to the vault.

🎯 Impact: Medium — increased sync bandwidth and potential write amplification on the Obsidian vault.

### 3️⃣ extractFrontmatterValue Limited to Simple Single-Line Values

📍 `extractFrontmatterValue` uses regex `^${key}:\s(.+)$` which only captures single-line values. YAML multiline strings, flow sequences, or deeply nested values would be missed.

🎯 Impact: Low — all image-related frontmatter values are single-line strings.

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

## 🧪 Testing Strategy

### 📊 Test Coverage (172 tests, 36 suites)

| Category | Tests | Description |
|----------|-------|-------------|
| 🔍 Image detection | 11 | Obsidian wiki, Markdown, various formats |
| 🏷️ Name generation | 16 | Kebab-case, path-based, conflict resolution |
| 📝 Content processing | 10 | Frontmatter stripping, embed removal, syntax cleaning |
| 📋 Frontmatter operations | 21 | Extraction, quoting, updates, regeneration |
| 🖼️ processNote | 11 | Generation, skipping, metadata, describer, description caching |
| 📦 backfillImages | 14 | Chain updates, missing dirs, errors, prioritization, rate limits |
| 🔌 Provider resolution | 10 | Cloudflare, Gemini, Imagen, describer |
| ⏱️ Rate limiting | 12 | isDailyQuotaError, parseRetryDelay, retry logic, proactive delays |

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
