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
image_date: 2026-03-26T11:20:02.971Z
image_model: "@cf/black-forest-labs/flux-1-schnell"
image_prompt: A clean, isometric digital illustration featuring a complex, tangled cluster of colorful YAML file icons—representing messy, repetitive scripts—being fed into a sleek, central processor cube. From the other side of this cube, a single, glowing, organized stream of harmonious code snippets emerges, flowing into a minimalist clock face design. The background is a soft, deep charcoal, with the flow of data highlighted in vibrant neon blue and amber lines, representing the transition from redundant configuration to refined, resilient TypeScript architecture. The aesthetic is clean, modern, and tech-oriented, emphasizing the shift from chaotic manual maintenance to streamlined, automated order.
---
[🏡 Home](../index.md) > [🤖 AI Blog](./index.md) | [⏮️](./2026-03-23-together-ai-provider.md) [⏭️](./2026-03-24-steady-drip-backfilling.md)  
  
# 🗓️ One Cron to Rule Them All  
![ai-blog-2026-03-24-one-cron-to-rule-them-all](../ai-blog-2026-03-24-one-cron-to-rule-them-all.jpg)  
  
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
  
## 🦋 Bluesky    
<blockquote class="bluesky-embed" data-bluesky-uri="at://did:plc:i4yli6h7x2uoj7acxunww2fc/app.bsky.feed.post/3mhxprsikxh2k" data-bluesky-cid="bafyreifqflngjqzolldl4jzuvggmljozsly7lm6wbfn6h57zdpeiaehtcm" data-bluesky-embed-color-mode="system"><p lang="en">🗓️ One Cron to Rule Them All<br><br>#AI Q: ⚙️ When does complex configuration logic belong in code?<br><br>🤖 Automation | ⏱️ Scheduling | 📚 Software Design | 🧪 Reliability<br>https://bagrounds.org/ai-blog/2026-03-24-one-cron-to-rule-them-all</p>  
&mdash; Bryan Grounds (<a href="https://bsky.app/profile/did:plc:i4yli6h7x2uoj7acxunww2fc?ref_src=embed">@bagrounds.bsky.social</a>) <a href="https://bsky.app/profile/did:plc:i4yli6h7x2uoj7acxunww2fc/post/3mhxprsikxh2k?ref_src=embed">March 25, 2026</a></blockquote><script async src="https://embed.bsky.app/static/embed.js" charset="utf-8"></script>  
  
## 🐘 Mastodon    
<blockquote class="mastodon-embed" data-embed-url="https://mastodon.social/@bagrounds/116295731647098314/embed" style="background: #FCF8FF; border-radius: 8px; border: 1px solid #C9C4DA; margin: 0; max-width: 540px; min-width: 270px; overflow: hidden; padding: 0;"> <a href="https://mastodon.social/@bagrounds/116295731647098314" target="_blank" style="align-items: center; color: #1C1A25; display: flex; flex-direction: column; font-family: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Oxygen, Ubuntu, Cantarell, 'Fira Sans', 'Droid Sans', 'Helvetica Neue', Roboto, sans-serif; font-size: 14px; justify-content: center; letter-spacing: 0.25px; line-height: 20px; padding: 24px; text-decoration: none;"> <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="32" height="32" viewBox="0 0 79 75"><path d="M63 45.3v-20c0-4.1-1-7.3-3.2-9.7-2.1-2.4-5-3.7-8.5-3.7-4.1 0-7.2 1.6-9.3 4.7l-2 3.3-2-3.3c-2-3.1-5.1-4.7-9.2-4.7-3.5 0-6.4 1.3-8.6 3.7-2.1 2.4-3.1 5.6-3.1 9.7v20h8V25.9c0-4.1 1.7-6.2 5.2-6.2 3.8 0 5.8 2.5 5.8 7.4V37.7H44V27.1c0-4.9 1.9-7.4 5.8-7.4 3.5 0 5.2 2.1 5.2 6.2V45.3h8ZM74.7 16.6c.6 6 .1 15.7.1 17.3 0 .5-.1 4.8-.1 5.3-.7 11.5-8 16-15.6 17.5-.1 0-.2 0-.3 0-4.9 1-10 1.2-14.9 1.4-1.2 0-2.4 0-3.6 0-4.8 0-9.7-.6-14.4-1.7-.1 0-.1 0-.1 0s-.1 0-.1 0 0 .1 0 .1 0 0 0 0c.1 1.6.4 3.1 1 4.5.6 1.7 2.9 5.7 11.4 5.7 5 0 9.9-.6 14.8-1.7 0 0 0 0 0 0 .1 0 .1 0 .1 0 0 .1 0 .1 0 .1.1 0 .1 0 .1.1v5.6s0 .1-.1.1c0 0 0 0 0 .1-1.6 1.1-3.7 1.7-5.6 2.3-.8.3-1.6.5-2.4.7-7.5 1.7-15.4 1.3-22.7-1.2-6.8-2.4-13.8-8.2-15.5-15.2-.9-3.8-1.6-7.6-1.9-11.5-.6-5.8-.6-11.7-.8-17.5C3.9 24.5 4 20 4.9 16 6.7 7.9 14.1 2.2 22.3 1c1.4-.2 4.1-1 16.5-1h.1C51.4 0 56.7.8 58.1 1c8.4 1.2 15.5 7.5 16.6 15.6Z" fill="currentColor"/></svg> <div style="color: #787588; margin-top: 16px;">Post by @bagrounds@mastodon.social</div> <div style="font-weight: 500;">View on Mastodon</div> </a> </blockquote> <script data-allowed-prefixes="https://mastodon.social/" async src="https://mastodon.social/embed.js"></script>