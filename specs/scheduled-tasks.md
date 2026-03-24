# ⏰ Scheduled Tasks — Consolidated Task Scheduler

## 🎯 Overview

📋 All recurring automation tasks run through a single hourly GitHub Actions cron job.
🧠 A TypeScript scheduler determines which tasks to execute based on the current UTC hour.
🚫 Zero scheduling logic lives in YAML — the workflow file is purely declarative.

## 🏗️ Architecture

### 📦 Components

| 🧩 Component | 📂 Path | 📝 Purpose |
|---|---|---|
| 📚 Scheduler | `scripts/lib/scheduler.ts` | 🧠 Pure functions: given UTC hour → task IDs to run |
| 🧪 Tests | `scripts/lib/scheduler.test.ts` | ✅ 45 tests covering scheduling logic and invariants |
| 🎯 Orchestrator | `scripts/run-scheduled.ts` | 🔧 Single entry point that spawns task pipelines as subprocesses |
| 🧪 Tests | `scripts/run-scheduled.test.ts` | ✅ 12 tests covering CLI parsing and output capture |
| ⚙️ Workflow | `.github/workflows/scheduled.yml` | 🕐 Hourly cron, declarative YAML only |

### 🔄 Data Flow

```
⏰ GitHub Actions cron (hourly)
         ↓
📜 npx tsx scripts/run-scheduled.ts
         ↓
🧠 getScheduledTasks(currentHourUtc)
         ↓
📋 For each task:
   ├── 🐔 blog-series:chickie-loo      → pull → generate → image → sync
   ├── 🤖 blog-series:auto-blog-zero   → pull → generate → image → sync
   ├── 🏛️ blog-series:systems-for-public-good → pull → generate → image → sync
   ├── 🖼️ backfill-blog-images         → pull → backfill → sync
   ├── 🔗 internal-linking             → pull vault → link → push vault
   └── 📢 social-posting               → discover → post
```

## ⏰ Schedule

| 🕐 UTC Hour | 🏷️ Task ID | 📝 Description |
|---|---|---|
| 15 | `blog-series:chickie-loo` | 🐔 Chickie Loo daily post (7 AM PT) |
| 16 | `blog-series:auto-blog-zero` | 🤖 Auto Blog Zero daily post (8 AM PT) |
| 17 | `blog-series:systems-for-public-good` | 🏛️ Systems for Public Good daily post (9 AM PT) |
| 6 | `backfill-blog-images` | 🖼️ Backfill missing blog images (10 PM PT prev day) |
| 8 | `internal-linking` | 🔗 BFS wikilink insertion (~midnight PT) |
| 0,2,4,6,8,10,12,14,16,18,20,22 | `social-posting` | 📢 Auto-post to X/Bluesky/Mastodon (every 2 hours) |

### 📊 Overlapping Hours

| 🕐 Hour | 🏷️ Tasks (in execution order) |
|---|---|
| 6 | 🖼️ backfill-blog-images → 📢 social-posting |
| 8 | 🔗 internal-linking → 📢 social-posting |
| 16 | 🤖 blog-series:auto-blog-zero → 📢 social-posting |

🔢 Tasks execute sequentially within an hour. Blog/infrastructure tasks run before social posting to ensure new content is available for discovery.

## 🔧 Blog Series Runtime Configuration

📐 Each blog series has per-series defaults that the orchestrator applies before spawning the generation script:

| 🏷️ Series | 🤖 Default Model | 👤 Priority User Env Var |
|---|---|---|
| `chickie-loo` | `gemini-3.1-flash-lite-preview` | `CHICKIE_LOO_PRIORITY_USER` |
| `auto-blog-zero` | `gemini-3.1-flash-lite-preview` | `AUTO_BLOG_ZERO_PRIORITY_USER` |
| `systems-for-public-good` | `gemini-2.5-flash` | `SYSTEMS_FOR_PUBLIC_GOOD_PRIORITY_USER` |

🔄 The `BLOG_GEMINI_MODEL` GitHub variable overrides all defaults when set.

## 🔌 Subprocess Architecture

🏗️ The orchestrator spawns existing CLI scripts as child processes via `spawnSync`:

- 🔒 **Process isolation** — Each script runs in its own process; failures don't crash the orchestrator
- 🌍 **Environment inheritance** — Child processes inherit `process.env` with optional per-task overrides
- 📎 **GITHUB_OUTPUT capture** — For chained steps (e.g., generate → image → sync), the orchestrator creates a temp file, sets it as `GITHUB_OUTPUT`, and parses outputs after the subprocess completes
- ⚠️ **continue-on-error** — Image generation and quota checks use `continueOnError: true` to match original workflow behavior
- 🛡️ **Task isolation** — Each task is wrapped in try/catch; a failing task does not prevent subsequent tasks from running

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

🔬 57 tests across 7 suites:

### 📚 Scheduler Tests (45 tests)

- ⏰ Per-hour task resolution (24 hours × valid IDs)
- 📊 Overlapping schedule verification
- 🔢 Execution order preservation
- 🛡️ Schedule invariants (valid hours, no duplicates)
- 🔧 Blog series run config completeness
- ✅ Task ID validation
- 🔍 Series ID extraction

### 🎯 Orchestrator Tests (12 tests)

- 🖥️ CLI argument parsing (--hour, --task, both, edge cases)
- 📎 GITHUB_OUTPUT file parsing (single, multiple, equals in values, empty, missing)

## ➕ Adding a New Scheduled Task

1. 📋 Define the task's CLI script in `scripts/`
2. 🏷️ Add a `TaskId` variant to `scripts/lib/scheduler.ts`
3. ⏰ Add a `ScheduleEntry` to the `SCHEDULE` array
4. 🔧 Add a runner function and register it in `TASK_RUNNERS` in `scripts/run-scheduled.ts`
5. 🧪 Tests will automatically verify the new task appears in the 24-hour cycle
