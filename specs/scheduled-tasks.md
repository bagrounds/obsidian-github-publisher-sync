# ⏰ Scheduled Tasks — Consolidated Task Scheduler

## 🎯 Overview

📋 All recurring automation tasks run through a single hourly GitHub Actions cron job.
🧠 A TypeScript scheduler determines which tasks to execute based on the current UTC hour.
🚫 Zero scheduling logic lives in YAML — the workflow file is purely declarative.
🔄 Blog series use "at or after" scheduling with idempotency checks for resilience.

## 🏗️ Architecture

### 📦 Components

| 🧩 Component | 📂 Path | 📝 Purpose |
|---|---|---|
| 📚 Scheduler | `scripts/lib/scheduler.ts` | 🧠 Pure functions: given UTC hour → task IDs to run |
| 🎯 Orchestrator | `scripts/run-scheduled.ts` | 🔧 Single entry point that calls library functions directly |
| ⚙️ Workflow | `.github/workflows/scheduled.yml` | 🕐 Hourly cron, declarative YAML only |

### 🔄 Data Flow

```
⏰ GitHub Actions cron (hourly)
         ↓
📜 npx tsx scripts/run-scheduled.ts
         ↓
🧠 getScheduledTasks(currentHourUtc)
         ↓
📋 For each task (direct library calls, no subprocesses):
   ├── 🐔 blog-series:chickie-loo      → check exists → pull → generate → image → sync
   ├── 🤖 blog-series:auto-blog-zero   → check exists → pull → generate → image → sync
   ├── 🏛️ blog-series:systems-for-public-good → check exists → pull → generate → image → sync
   ├── 🖼️ backfill-blog-images         → pull → backfill → sync
   ├── 🔗 internal-linking             → pull vault → link → push vault
   └── 📢 social-posting               → discover → post
```

## ⏰ Schedule

### 📝 Blog Series — "At or After" Scheduling

🔄 Blog series tasks become eligible at their scheduled hour and remain eligible for the rest of the day. The orchestrator checks whether today's post already exists before generating, making the system resilient to partial failures.

| 🕐 Earliest UTC Hour | 🏷️ Task ID | 📝 Description |
|---|---|---|
| 15 | `blog-series:chickie-loo` | 🐔 Chickie Loo daily post (7 AM PT) |
| 16 | `blog-series:auto-blog-zero` | 🤖 Auto Blog Zero daily post (8 AM PT) |
| 17 | `blog-series:systems-for-public-good` | 🏛️ Systems for Public Good daily post (9 AM PT) |

### 🔧 Other Tasks — Exact Hour Matching

| 🕐 UTC Hour | 🏷️ Task ID | 📝 Description |
|---|---|---|
| 6 | `backfill-blog-images` | 🖼️ Backfill missing blog images (10 PM PT prev day) |
| 8 | `internal-linking` | 🔗 BFS wikilink insertion (~midnight PT) |
| 0,2,4,6,8,10,12,14,16,18,20,22 | `social-posting` | 📢 Auto-post to X/Bluesky/Mastodon (every 2 hours) |

## 🔧 Blog Series Model Fallback Chain

📐 Each blog series has an ordered chain of Gemini models to try. On failure, the orchestrator tries the next model with 5XX retry and grounding fallback:

| 🏷️ Series | 🤖 Model Chain (in order) | 👤 Priority User Env Var |
|---|---|---|
| `chickie-loo` | gemini-3.1-flash-lite-preview → gemini-2.5-flash → gemini-2.5-flash-lite | `CHICKIE_LOO_PRIORITY_USER` |
| `auto-blog-zero` | gemini-3.1-flash-lite-preview → gemini-2.5-flash → gemini-2.5-flash-lite | `AUTO_BLOG_ZERO_PRIORITY_USER` |
| `systems-for-public-good` | gemini-2.5-flash → gemini-2.5-flash-lite → gemini-3.1-flash-lite-preview | `SYSTEMS_FOR_PUBLIC_GOOD_PRIORITY_USER` |

🔄 The `BLOG_GEMINI_MODEL` GitHub variable prepends to the chain when set.

## 🛡️ API Resilience

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
# Run tasks for current UTC hour
npx tsx scripts/run-scheduled.ts

# Simulate a specific hour (for testing)
npx tsx scripts/run-scheduled.ts --hour 15

# Run a specific task regardless of schedule
npx tsx scripts/run-scheduled.ts --task social-posting
npx tsx scripts/run-scheduled.ts --task blog-series:chickie-loo
```

### 📡 Workflow Dispatch

🔧 The `workflow_dispatch` trigger supports the same overrides:
- `task` — Run a specific task instead of consulting the schedule
- `hour` — Simulate a specific UTC hour

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
