# ⏰ Scheduled Tasks — Consolidated Task Scheduler

## 🎯 Overview

📋 All recurring automation tasks run through a single hourly GitHub Actions cron job.
🧠 A TypeScript scheduler determines which tasks to execute based on the current **Pacific** hour.
🚫 Zero scheduling logic lives in YAML — the workflow file is purely declarative.
🔄 Blog series and reflection-title use "at or after" scheduling with idempotency checks for resilience.

## 🏗️ Architecture

### 📦 Components

| 🧩 Component | 📂 Path | 📝 Purpose |
|---|---|---|
| 📚 Scheduler | `scripts/lib/scheduler.ts` / `haskell/src/Automation/Scheduler.hs` | 🧠 Pure functions: given Pacific hour → task IDs to run |
| 🎯 Orchestrator | `scripts/run-scheduled.ts` / `haskell/app/RunScheduled.hs` | 🔧 Single entry point that calls library functions directly |
| ⚙️ Workflow | `.github/workflows/scheduled.yml` | 🕐 Hourly cron, declarative YAML only |

### 🔀 Haskell Implementation

🏗️ The Haskell orchestrator (RunScheduled.hs) is the active implementation used in CI.
🐳 The executable is pre-built by the `haskell.yml` CI workflow (using the `haskell:9.14.1` Docker container) and uploaded as an artifact with 90 day retention.
⬇️ The scheduled workflow downloads the pre-built binary from the latest successful Haskell CI run — no compilation at runtime.
✅ Fully implemented task runners: blog-series (all 3), ai-fiction, reflection-title.
⚠️ Stubbed task runners (log and skip): backfill-blog-images, internal-linking, social-posting.
🔙 Rolling back to TypeScript is a workflow file revert: restore `npx tsx scripts/run-scheduled.ts`.
📦 The TypeScript implementation remains fully functional and tested (1298 tests).

### 🔄 Data Flow

```
⏰ GitHub Actions cron (hourly)
         ↓
📜 npx tsx scripts/run-scheduled.ts
         ↓
🧠 getScheduledTasks(nowPacificHour())
         ↓
📋 For each task (direct library calls, no subprocesses):
   ├── 🐔 blog-series:chickie-loo      → check exists → pull → generate → image → sync
   ├── 🤖 blog-series:auto-blog-zero   → check exists → pull → generate → image → sync
   ├── 🏛️ blog-series:systems-for-public-good → check exists → pull → generate → image → sync
   ├── 🤖🐲 ai-fiction                  → pull vault → check fiction → generate → push vault
   ├── 🪞 reflection-title             → pull vault → check title → generate → push vault
   ├── 🖼️ backfill-blog-images         → pull → backfill → sync
   ├── 🔗 internal-linking             → pull vault → link → push vault
   └── 📢 social-posting               → discover → post
```

## ⏰ Schedule

📌 All times are declared in **Pacific time**. The scheduler converts to
Pacific before making decisions via `nowPacificHour()`.

### 📝 Blog Series — "At or After" Scheduling

🔄 Blog series tasks become eligible at their scheduled Pacific hour and remain eligible for the rest of the day. The orchestrator checks whether today's post already exists before generating, making the system resilient to partial failures.

| 🕐 Earliest Pacific Hour | 🏷️ Task ID | 📝 Description |
|---|---|---|
| 7 AM | `blog-series:chickie-loo` | 🐔 Chickie Loo daily post |
| 8 AM | `blog-series:auto-blog-zero` | 🤖 Auto Blog Zero daily post |
| 9 AM | `blog-series:systems-for-public-good` | 🏛️ Systems for Public Good daily post |

### 🪞 Reflection & Fiction — "At or After" Scheduling

🌙 The ai-fiction and reflection-title tasks both use the `atOrAfter` flag, becoming eligible at 10 PM Pacific and remaining eligible until 11:59 PM Pacific. The ai-fiction task generates a short emoji-rich fiction passage themed on the day's content. The reflection-title task generates a creative emoji-enriched title. AI fiction runs first so that the title generator can incorporate fiction themes. Also titles yesterday's reflection if it's still untitled.

| 🕐 Earliest Pacific Hour | 🏷️ Task ID | 📝 Description |
|---|---|---|
| 10 PM | `ai-fiction` | 🤖🐲 Generate themed fiction for today's reflection |
| 10 PM | `reflection-title` | 🪞 Generate creative title for today's reflection |

### 🔧 Other Tasks — Exact Hour Matching

| 🕐 Pacific Hour | 🏷️ Task ID | 📝 Description |
|---|---|---|
| Every hour | `backfill-blog-images` | 🖼️ Backfill 1 missing blog image per hour |
| Every hour | `internal-linking` | 🔗 BFS wikilink insertion for 1 note per hour |
| 0,2,4,6,8,10,12,14,16,18,20,22 | `social-posting` | 📢 Auto-post to X/Bluesky/Mastodon (every 2 hours) |

### 🛡️ Social Media Safety Gate

🚫 Reflection notes are blocked from social media posting until they have a creative title. The `isUntitledReflection()` function returns true when a reflection's title is just the bare date, preventing untitled reflections from being posted.

## 🔧 Blog Series Model Fallback Chain

📐 Each blog series has an ordered chain of Gemini models to try. On failure, the orchestrator tries the next model with 5XX retry and grounding fallback:

| 🏷️ Series | 🤖 Model Chain (in order) | 👤 Priority User Env Var |
|---|---|---|
| `chickie-loo` | gemini-3.1-flash-lite-preview → gemini-3-flash-preview | `CHICKIE_LOO_PRIORITY_USER` |
| `auto-blog-zero` | gemini-3.1-flash-lite-preview → gemini-3-flash-preview | `AUTO_BLOG_ZERO_PRIORITY_USER` |
| `systems-for-public-good` | gemini-2.5-flash → gemini-2.5-flash-lite → gemini-3.1-flash-lite-preview | `SYSTEMS_FOR_PUBLIC_GOOD_PRIORITY_USER` |

🔒 chickie-loo and auto-blog-zero are restricted to Gemini 3+ models for highest quality blog posts.
🌐 systems-for-public-good leads with gemini-2.5-flash because it needs Google Search grounding (free tier, 500 RPD) to reference current events. Grounding is not available on the free tier for Gemini 3+ models.
⚠️ Grounding with Google Search is not available on the free tier for 3+ models.

🔄 The `BLOG_GEMINI_MODEL` GitHub variable prepends to the chain when set.

## ♻️ Blog Post Regeneration

🔄 Users can request regeneration of a blog post by setting `regenerate_post: true` in the post's YAML frontmatter from Obsidian. On the next hourly run, the scheduler detects the flag, removes the old post, and generates a fresh one.

### 📋 How It Works

1. 📱 In Obsidian, toggle the `regenerate_post` property to `true` on the post to regenerate
2. 🔄 Obsidian syncs the change to the vault
3. ⏰ On the next hourly cron run, `findPostToRegenerate()` detects the flag
4. 🗑️ The old post is removed from the local repo
5. ✨ A new post is generated with a fresh title and slug (without `regenerate_post` in its frontmatter)
6. 🔗 The previous post's forward link is updated to point to the new filename (replacing the stale link)
7. 📓 The daily reflection's post link is replaced with the new filename
8. 🗑️ The old file is deleted from the Obsidian vault
9. 📤 The new post, updated previous post, and vault changes are synced back to Obsidian

### 🛡️ Safety Properties

🚫 Newly generated posts never include `regenerate_post`, preventing infinite regeneration loops.
📅 Only today's post can be regenerated — the flag is ignored on posts from other dates.
🔒 The flag is only checked in the YAML frontmatter block, not in the body content.
🔗 Forward links from the previous post are replaced rather than duplicated.
📓 Daily reflection links are replaced rather than duplicated when the filename changes.

## 🛡️ API Resilience

### ⏱️ Inter-Task Rate Limit Protection

🔒 When multiple tasks are scheduled at the same hour, a 30-second delay is inserted between each task to prevent per-minute API rate limit collisions across Gemini and other services.

### 📊 Dashboard Links (Not Quota Checks)

🔗 Instead of calling Gemini/GCP APIs to check quota capacity (which produced noisy logs with no actionable information), the orchestrator logs links to inference service dashboards at scheduler start for manual inspection:

| 🏷️ Service | 🔗 Dashboard |
|---|---|
| Gemini API | https://aistudio.google.com/apikey |
| GCP Quotas | https://console.cloud.google.com/iam-admin/quotas |
| Cloudflare AI | https://dash.cloudflare.com/?to=/:account/ai/workers-ai |
| Hugging Face | https://huggingface.co/settings/billing |
| Together AI | https://api.together.ai/settings/billing |

### 🔇 Aggregate Skip Logging

📊 During image backfill, the `collectCandidates` function emits a single `candidates_collected` summary event instead of per-file `already_has_image` events. During internal linking, `skipped_already_analyzed` events are suppressed — skip counts are reported in the final completion summary via `filesSkipped`.

### 📝 Plain Text Logging

🔤 All orchestrator and library logging uses human-readable plain text with emoji prefixes instead of JSON structured events. JSON `{...}` objects were masked as `***` by GitHub Actions' secret redaction. Plain text log lines include:
- 🎨 Image generation actions with file names and provider
- 📖 Book identification results with identified books
- ✏️ Link insertion details with matched text and targets
- 📊 Aggregate counts for candidates, visited files, skips

### 🎯 Per-Run Limits

📊 Backfill tasks are deliberately limited to minimize inference costs and rate limit pressure:

| 🏷️ Task | 📈 Limit | 📝 Rationale |
|---|---|---|
| `backfill-blog-images` | 1 image per run | 🖼️ Each image requires ~2 inference calls (describe + generate) |
| `internal-linking` | 1 inference request per run | 🔗 Traverses all reachable files via BFS but only calls Gemini for 1 un-analyzed file per hour |

🔄 With hourly scheduling, this achieves up to 24 images and 24 notes processed per day while staying well within free-tier rate limits.

### 🔄 5XX Retry with Exponential Backoff

📡 All Gemini API calls retry on transient errors (429, 500, 502, 503, 504) with exponential backoff (2s, 4s, 8s). Up to 3 retries per model.

### 🔀 Model Fallback Chain

🔗 If a model fails definitively (non-retriable error after retries), the orchestrator tries the next model in the chain. Each model gets its own retry budget.

### 🌐 Grounding Fallback

📡 For grounding-enabled requests, if grounding fails with a quota error, the request is retried without grounding on the same model before moving to the next model.

## 📚 Library-First Architecture

🏗️ The orchestrator calls library functions directly — no subprocess spawning, no temp files, no GITHUB_OUTPUT parsing:

- 📞 **Direct function calls** — `generateBlogPost()`, `processNote()`, `autoPost()`, `runLinking()`, etc.
- 📦 **Return values** — Data flows through function returns, not environment variables
- 🛡️ **Task isolation** — Each task is wrapped in try/catch; failures don't prevent subsequent tasks
- ⚠️ **Graceful degradation** — Image generation failures are caught and logged, not fatal

## 🖥️ CLI Interface

```bash
# Run tasks for current Pacific hour (Haskell — active in CI)
cd haskell && cabal run run-scheduled

# Run tasks for current Pacific hour (TypeScript — fallback)
npx tsx scripts/run-scheduled.ts

# Simulate a specific Pacific hour (for testing)
cd haskell && cabal run run-scheduled -- --hour 15

# Run a specific task regardless of schedule
cd haskell && cabal run run-scheduled -- --task social-posting
cd haskell && cabal run run-scheduled -- --task blog-series:chickie-loo
```

### 📡 Workflow Dispatch

🔧 The `workflow_dispatch` trigger supports the same overrides:
- `task` — Run a specific task instead of consulting the schedule
- `hour` — Simulate a specific Pacific hour

### 📋 Run Summary

📊 At the end of every orchestrator run, a human-readable summary block is printed showing each task's status:

```
--- Run Summary ---
  ✅ backfill-blog-images
  ✅ internal-linking
  ❌ social-posting — GEMINI_API_KEY not set
  📊 2/3 succeeded
-------------------
```

🔍 This makes it easy to scroll to the bottom of CI logs and immediately see what happened.

## 🧪 Testing

🔬 81 tests across 10 suites:

### 📚 Scheduler Tests

- ⏰ "At or after" scheduling for blog series (eligible at and after scheduled hour)
- 🚫 Blog series NOT eligible before scheduled hour
- ⏰ Exact hour matching for non-blog tasks
- 📊 Overlapping schedule verification
- 🛡️ Schedule invariants (valid hours, no duplicates)
- 🔧 Blog series model chain completeness and ordering
- ✅ Task ID validation, series ID extraction
- 📂 blogPostExistsForToday filesystem checks

### 🎯 Orchestrator Tests

- 🖥️ CLI argument parsing (--hour, --task, both, edge cases)

### 📝 Blog Generation Tests

- 🔄 isRetriableError (5XX, 429, UNAVAILABLE, INTERNAL)
- ❌ Non-retriable errors (400, 403, 404)
- 📊 isQuotaError (429, RESOURCE_EXHAUSTED, quota)
- 🔤 generateSlug

## ➕ Adding a New Scheduled Task

1. 📋 Define the task's library function
2. 🏷️ Add a `TaskId` variant to `scripts/lib/scheduler.ts`
3. ⏰ Add a `ScheduleEntry` to the `SCHEDULE` array
4. 🔧 Add a runner function and register it in `TASK_RUNNERS` in `scripts/run-scheduled.ts`
5. 🧪 Tests will automatically verify the new task appears in the 24-hour cycle
