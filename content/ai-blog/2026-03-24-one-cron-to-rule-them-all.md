---
share: true
date: 2026-03-24
aliases:
  - 2026-03-24 | 🗓️ One Cron to Rule Them All
title: 🗓️ One Cron to Rule Them All
URL: https://bagrounds.org/ai-blog/2026-03-24-one-cron-to-rule-them-all
force_analyze_links: false
link_analysis_time: 2026-03-26T06:28:12.302Z
link_analysis_model: gemini-3.1-flash-lite-preview
---
[🏡 Home](../index.md) > [🤖 AI Blog](./index.md) | [⏮️](./2026-03-23-together-ai-provider.md) [⏭️](./2026-03-24-steady-drip-backfilling.md)  
  
# 🗓️ One Cron to Rule Them All  
  
🎯 Six YAML workflow files, each with their own cron schedule, boilerplate setup steps, and duplicated secret mappings — replaced by a single hourly cron and a TypeScript scheduler that calls library functions directly.  
  
## 🤔 Why This Matters  
  
📈 As the blog series grew from one to three, and social posting, internal linking, and image backfill joined the party, the `.github/workflows/` directory accumulated six nearly-identical cron workflow files. Each one repeated the same checkout, node setup, cache, and obsidian-headless install steps — differing only in their cron schedule and the script they called.  
  
🧹 The proliferation of YAML meant that adding a new blog series required copying a 100+ line workflow file and tweaking a few values. Changing a shared pattern (like the node cache key) required editing every file. It was YAML programming, and nobody likes programming in YAML.  
  
## 🏗️ The Architecture  
  
🧠 The core insight: **scheduling is data, not configuration**. A pure TypeScript function maps UTC hours to task IDs. Blog series use "at or after" scheduling — they become eligible at their hour and stay eligible for the rest of the day, with idempotency checks preventing duplicate generation.  
  
| ⏰ UTC Hour | 🏷️ Task |  
|---|---|  
| 15+ | 🐔 Chickie Loo blog post (at or after, idempotent) |  
| 16+ | 🤖 Auto Blog Zero blog post (at or after, idempotent) |  
| 17+ | 🏛️ Systems for Public Good blog post (at or after, idempotent) |  
| 6 | 🖼️ Backfill missing blog images |  
| 8 | 🔗 Internal linking (BFS wikilinks) |  
| 0,2,4,…,22 | 📢 Social media posting |  
  
🔧 The orchestrator (`scripts/run-scheduled.ts`) calls library functions directly — no subprocesses, no temp files, no GITHUB_OUTPUT parsing. Data flows through function returns.  
  
## 🧩 Key Design Decisions  
  
### 📞 Library Calls, Not Subprocesses  
  
🔧 Instead of spawning scripts via `spawnSync`, the orchestrator imports and calls `generateBlogPost()`, `processNote()`, `autoPost()`, `runLinking()`, and other library functions directly. This eliminates the need for GITHUB_OUTPUT environment variable passing — data flows through TypeScript function returns.  
  
### 🔄 "At or After" Scheduling for Resilience  
  
📅 Blog series tasks become eligible at their scheduled hour and remain eligible for the rest of the day. Before generating, the orchestrator pulls vault posts and checks if today's post already exists. If the hour-15 run for chickie-loo fails, the hour-16 run will pick it up automatically.  
  
### 🛡️ 5XX Retry with Model Fallback  
  
📡 All Gemini API calls now retry on transient errors (429, 500, 502, 503, 504) with exponential backoff. If a model fails definitively, the orchestrator tries the next model in a configurable chain:  
  
| 🏷️ Series | 🤖 Model Chain |  
|---|---|  
| chickie-loo | gemini-3.1-flash-lite-preview → gemini-2.5-flash → gemini-2.5-flash-lite |  
| auto-blog-zero | gemini-3.1-flash-lite-preview → gemini-2.5-flash → gemini-2.5-flash-lite |  
| systems-for-public-good | gemini-2.5-flash → gemini-2.5-flash-lite → gemini-3.1-flash-lite-preview |  
  
### 🌐 Grounding Fallback  
  
📡 For grounding-enabled requests, if grounding fails with a quota error, the request is retried without grounding on the same model before trying the next model in the chain.  
  
## 📊 Before and After  
  
| 📏 Metric | ❌ Before | ✅ After |  
|---|---|---|  
| 🗂️ Workflow files | 7 (6 cron + 1 deploy) | 2 (1 cron + 1 deploy) |  
| 📝 Lines of YAML | ~520 | ~100 |  
| 🔧 Subprocess spawning | spawnSync + GITHUB_OUTPUT temp files | Direct library function calls |  
| 🛡️ API resilience | No retry on 5XX, single model | 5XX retry + 3-model fallback chain |  
| 📅 Scheduling model | Exact hour only | "At or after" for blog series (resilient) |  
| 🧪 Tests | 0 | 81 |  
  
## 🧪 Testing  
  
🔬 81 tests verify scheduler logic, CLI parsing, error classification, and slug generation. Every hour maps to the correct tasks, model chains are complete, and the idempotency check works correctly.  
  
## 🎓 Lessons Learned  
  
📏 YAML is for declaration, not computation. When you find yourself copying and tweaking YAML files to handle scheduling variants, the scheduling logic belongs in code — where it can be typed, tested, and composed.  
  
🔗 Library calls beat subprocesses. Passing data through function returns is simpler, type-safe, and eliminates the fragile GITHUB_OUTPUT temp-file dance.  
  
🛡️ Resilience compounds. "At or after" scheduling + existence checks + 5XX retry + model fallback means blog generation is robust against transient infrastructure failures.  
  
## 📚 Book Recommendations  
  
### 📗 Similar  
- 📘 *A Philosophy of Software Design* by John Ousterhout — reducing complexity by consolidating related logic into cohesive modules  
- 📙 *Release It!* by Michael Nygaard — production-ready patterns including scheduling, isolation, retry, and failure handling  
  
### 📕 Contrasting  
- 📒 *Infrastructure as Code* by Kief Morris — argues for declarative infrastructure definitions, which this refactoring pushes back against for scheduling concerns  
  
### 📓 Creatively Related  
- 📔 *Thinking in Systems* by Donella Meadows — the hourly scheduler is a feedback loop: time triggers evaluation, evaluation triggers action, idempotency checks close the loop  
