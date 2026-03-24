---
share: true
date: 2026-03-24
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]

## 🗓️ One Cron to Rule Them All

🎯 Six YAML workflow files, each with their own cron schedule, boilerplate setup steps, and duplicated secret mappings — replaced by a single hourly cron and a TypeScript scheduler that decides what to do.

## 🤔 Why This Matters

📈 As the blog series grew from one to three, and social posting, internal linking, and image backfill joined the party, the `.github/workflows/` directory accumulated six nearly-identical cron workflow files. Each one repeated the same checkout, node setup, cache, and obsidian-headless install steps — differing only in their cron schedule and the script they called.

🧹 The proliferation of YAML meant that adding a new blog series required copying a 100+ line workflow file and tweaking a few values. Changing a shared pattern (like the node cache key) required editing every file. It was YAML programming, and nobody likes programming in YAML.

## 🏗️ The Architecture

🧠 The core insight: **scheduling is data, not configuration**. A pure TypeScript function maps UTC hours to task IDs:

| ⏰ UTC Hour | 🏷️ Task |
|---|---|
| 15 | 🐔 Chickie Loo blog post |
| 16 | 🤖 Auto Blog Zero blog post |
| 17 | 🏛️ Systems for Public Good blog post |
| 6 | 🖼️ Backfill missing blog images |
| 8 | 🔗 Internal linking (BFS wikilinks) |
| 0,2,4,…,22 | 📢 Social media posting |

🔧 The orchestrator (`scripts/run-scheduled.ts`) spawns existing CLI scripts as subprocesses — zero changes to the actual task implementations. Each blog series pipeline chains: pull vault → generate post → generate image → check quota → sync to vault.

## 🧩 Key Design Decisions

### 🐣 Subprocess Isolation

🔒 Each task runs as a child process via `spawnSync`. A failing image generation doesn't crash the orchestrator. A quota check runs even if the previous step failed. This preserves the `continue-on-error` and `if: always()` semantics from the original YAML.

### 📎 GITHUB_OUTPUT Capture

🔗 Blog generation writes `post=chickie-loo/2026-03-24-slug.md` to `$GITHUB_OUTPUT` for downstream steps. The orchestrator creates a temp file, sets it as `GITHUB_OUTPUT` in the subprocess environment, then parses the key-value pairs after completion.

### ⚙️ Per-Series Configuration

📐 Each blog series has its own default model and priority user env var. The orchestrator applies these before spawning the generation script, matching the original per-workflow environment setup:

| 🏷️ Series | 🤖 Default Model | 👤 Priority User Var |
|---|---|---|
| chickie-loo | gemini-3.1-flash-lite-preview | CHICKIE_LOO_PRIORITY_USER |
| auto-blog-zero | gemini-3.1-flash-lite-preview | AUTO_BLOG_ZERO_PRIORITY_USER |
| systems-for-public-good | gemini-2.5-flash | SYSTEMS_FOR_PUBLIC_GOOD_PRIORITY_USER |

## 📊 Before and After

| 📏 Metric | ❌ Before | ✅ After |
|---|---|---|
| 🗂️ Workflow files | 7 (6 cron + 1 deploy) | 2 (1 cron + 1 deploy) |
| 📝 Lines of YAML | ~520 | ~100 |
| 📜 Lines of TypeScript (scheduler) | 0 | ~90 |
| 📜 Lines of TypeScript (orchestrator) | 0 | ~250 |
| 🧪 New tests | 0 | 57 |
| 🔧 Steps to add a new blog series | Copy workflow + edit 5 values | Add 1 schedule entry + 1 config |

## 🧪 Testing

🔬 45 tests verify the scheduler's pure logic — every hour maps to the correct tasks, every task runs at least once per day, no duplicate IDs, no invalid hours. 12 more tests cover CLI parsing and GITHUB_OUTPUT file parsing.

## 🎓 Lesson Learned

📏 YAML is for declaration, not computation. When you find yourself copying and tweaking YAML files to handle scheduling variants, the scheduling logic belongs in code — where it can be typed, tested, and composed.

## 📚 Book Recommendations

### 📗 Similar
- 📘 *A Philosophy of Software Design* by John Ousterhout — reducing complexity by consolidating related logic into cohesive modules
- 📙 *Release It!* by Michael Nygaard — production-ready patterns including scheduling, isolation, and failure handling

### 📕 Contrasting
- 📒 *Infrastructure as Code* by Kief Morris — argues for declarative infrastructure definitions, which this refactoring pushes back against for scheduling concerns

### 📓 Creatively Related
- 📔 *Thinking in Systems* by Donella Meadows — the hourly scheduler is a feedback loop: time triggers evaluation, evaluation triggers action, action produces results that feed into the next cycle
