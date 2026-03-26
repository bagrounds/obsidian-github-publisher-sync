---
share: true
aliases:
  - 🔄 Smarter Publishing & 🤖🐲 AI Fiction for Daily Reflections
title: 🔄 Smarter Publishing & 🤖🐲 AI Fiction for Daily Reflections
image_date: 2026-03-26T04:33:09.470Z
image_model: "@cf/black-forest-labs/flux-1-schnell"
image_prompt: A clean, isometric-style illustration featuring a glowing, translucent smartphone floating in the center. From the screen, a stream of organized, luminous data blocks flows upward into a digital garden, representing the transition from messy, scattered breadcrumbs to a refined, indexed list. To the right, a stylized, friendly metallic dragon made of geometric circuit lines breathes a soft, colorful mist of ink onto an open digital notebook page, symbolizing the automated fiction generation. The background is a soft, deep gradient - shifting from a technical slate blue to a warm, creative twilight purple. The overall aesthetic is minimalist, sleek, and high-tech, using soft ambient lighting to highlight the clean structure of the data and the whimsical, imaginative nature of the AI-generated storytelling.
force_analyze_links: false
link_analysis_time: 2026-03-26T04:33:48.823Z
link_analysis_model: gemini-3.1-flash-lite-preview
updated: 2026-03-26T04:48:40.846Z
---
[🏡 Home](../index.md) > [🤖 AI Blog](./index.md) | [⏮️](./2026-03-25-automated-ai-blog-vault-sync.md) [⏭️](./2026-03-25-reflection-title-generation.md)  
# 🔄 Smarter Publishing & 🤖🐲 AI Fiction for Daily Reflections  
![ai-blog-2026-03-26-daily-updates-and-ai-fiction](../ai-blog-2026-03-26-daily-updates-and-ai-fiction.jpg)  
  
## 🎯 Two Changes, One Theme  
  
📱 Daily reflections are the hub of this Obsidian vault - every blog post, book note, and social media embed lands there.  
🔧 Today we shipped two features that make reflections smarter: a cleaner notification system for file changes and automated fiction generation.  
  
## 🔄 The Updates Section: Replacing the Breadcrumb Trail  
  
### 🧭 The Old Way  
  
📍 Previously, when an automated task modified a file (backfilling an image, inserting a wiki link), the system propagated an `updated` timestamp along BFS paths back to the reflection.  
🐌 This "breadcrumb trail" strategy touched many files across the vault just to signal that something changed.  
📱 On Obsidian mobile, discovering what changed required searching for recently-updated timestamps - not exactly a glanceable experience.  
  
### ✨ The New Way  
  
📋 Now, a `## 🔄 Updates` section at the bottom of each daily reflection collects wiki links to every file modified that day.  
👀 One glance at the reflection reveals every file touched by automation - image backfill, internal linking, social posting.  
🧩 The implementation is refreshingly simple: `buildUpdateLink` formats a wiki link, `addUpdateLinks` inserts it into the reflection content.  
  
### 🛡️ Idempotency by Design  
  
🔁 If a link already exists in the Updates section, it's silently skipped.  
📌 If the section doesn't exist yet, it's created at the end of the file.  
🔄 Re-running the same task with the same files produces zero changes - safe for the hourly scheduler's relentless cadence.  
  
### 📊 Before and After  
  
| 📏 Aspect | ❌ Breadcrumb Trail | ✅ Updates Section |  
|---|---|---|  
| 📍 Signal location | `updated` timestamp scattered across vault files | Single section in today's reflection |  
| 📂 Files touched | Many (BFS path propagation) | One (the reflection note) |  
| 📱 Mobile discoverability | Search required | Glanceable list |  
| 🔧 Implementation complexity | BFS traversal + timestamp comparison | Append wiki link + duplicate check |  
  
## 🤖🐲 AI Fiction: Automated Storytelling  
  
### 💡 The Idea  
  
🌅 Every evening at 10 PM Pacific, after the day's readings and blog posts have accumulated in the reflection, a short fiction passage is generated.  
🧠 The fiction abstracts themes from the day's content - it's not a summary, but an impressionistic riff on whatever the day held.  
🎯 Each sentence starts with an emoji, no quotation marks are allowed, and the whole passage stays under 100 words.  
  
### 🧹 Stripping for Focus  
  
📄 Before the reflection reaches Gemini, the `stripForPrompt` function removes noise:  
- 📋 YAML frontmatter  
- 🐦 Social media embed sections  
- 🔄 The Updates section itself  
  
🎯 What remains is the substantive content - books, blog posts, notes, and thoughts - the raw material for fiction.  
  
### 📍 Placement Matters  
  
📌 The fiction section lands just before embed sections and the Updates section.  
👀 This keeps it visible as authored content rather than buried under social media embeds.  
🏗️ The `applyFiction` function handles the insertion logic, respecting the reflection's existing structure.  
  
### 🤖 Model Chain  
  
🔗 Fiction generation uses the same resilient model chain pattern as reflection titles:  
  
| 🔢 Priority | 🤖 Model |  
|---|---|  
| 1️⃣ | gemini-2.5-flash |  
| 2️⃣ | gemini-2.5-flash-lite |  
| 3️⃣ | gemini-3.1-flash-lite-preview |  
  
🔧 The `FICTION_MODEL` environment variable can prepend a custom model for experimentation.  
🛡️ Each model gets exponential backoff retries on transient errors before falling through to the next.  
  
### ⏰ Scheduling  
  
📅 The `ai-fiction` task shares the 10 PM Pacific slot with `reflection-title`, but runs first.  
🔄 Both use at-or-after scheduling - if the 10 PM run fails, subsequent hourly runs pick it up.  
🧩 Idempotency ensures the fiction section is never duplicated.  
  
## 🏗️ Architecture Recap  
  
| 📦 Component | 📂 Path | 🎯 Purpose |  
|---|---|---|  
| 🔄 Updates Library | `scripts/lib/daily-updates.ts` | 🔧 Build and insert update wiki links |  
| 🤖 Fiction Library | `scripts/lib/ai-fiction.ts` | 🧠 Strip, prompt, parse, and apply fiction |  
| 🧪 Updates Tests | `scripts/lib/daily-updates.test.ts` | ✅ Pure function and I/O tests |  
| 🧪 Fiction Tests | `scripts/lib/ai-fiction.test.ts` | ✅ Pure function tests |  
| ⏰ Scheduler | `scripts/lib/scheduler.ts` | 📅 Hour 22 at-or-after for ai-fiction |  
| 🎛️ Orchestrator | `scripts/run-scheduled.ts` | 🔄 runAiFiction and update link integration |  
  
## 💡 Lessons Learned  
  
1. 📱 **Optimize for the reader's device** - breadcrumb trails were elegant in theory but invisible on mobile; a simple list in one place wins  
2. 🧩 **Idempotency is infrastructure** - when tasks run hourly, every operation must be safe to repeat without side effects  
3. 🧹 **Strip before prompting** - removing frontmatter and embeds from the AI context produces more focused, creative output  
4. ⏰ **Share scheduling slots carefully** - fiction runs before title generation so the title can incorporate fiction themes  
5. 🔗 **Model chains are table stakes** - free-tier rate limits mean every AI feature needs fallback models  
  
## 📚 Book Recommendations  
  
### 📖 Similar  
- 🧠 *Atomic Habits* by James Clear  
- 📓 *The Bullet Journal Method* by Ryder Carroll  
- 🏗️ *A Philosophy of Software Design* by John Ousterhout  
  
### 🔄 Contrasting  
- 🎨 *The Art of Fiction* by John Gardner  
- 🤖 *Gödel, Escher, Bach* by Douglas Hofstadter  
  
### 🎨 Creatively Related  
- ✍️ *Bird by Bird* by Anne Lamott  
- 🪞 *If on a Winter's Night a Traveler* by Italo Calvino  
- 🔧 *[💺🚪💡🤔 The Design of Everyday Things](../books/the-design-of-everyday-things.md)* by Don Norman  
  
## 🦋 Bluesky  
<blockquote class="bluesky-embed" data-bluesky-uri="at://did:plc:i4yli6h7x2uoj7acxunww2fc/app.bsky.feed.post/3mhwv56ev7r2o" data-bluesky-cid="bafyreid6dsetgjntilxesuuesyjxcivnm2fkriswhvmd3j2sm4eij3vase" data-bluesky-embed-color-mode="system"><p lang="en">🔄 Smarter Publishing &amp; 🤖🐲 AI Fiction for Daily Reflections<br><br>#AI Q: 🤖 Could AI generate meaningful fiction based on your daily notes?<br><br>🤖 AI Storytelling | 🔄 Automation Workflows | 📱 Mobile Optimization | 📚 Knowledge Management<br>https://bagrounds.org/ai-blog/2026-03-26-daily-updates-and-ai-fiction</p>  
&mdash; Bryan Grounds (<a href="https://bsky.app/profile/did:plc:i4yli6h7x2uoj7acxunww2fc?ref_src=embed">@bagrounds.bsky.social</a>) <a href="https://bsky.app/profile/did:plc:i4yli6h7x2uoj7acxunww2fc/post/3mhwv56ev7r2o?ref_src=embed">March 25, 2026</a></blockquote><script async src="https://embed.bsky.app/static/embed.js" charset="utf-8"></script>  
  
## 🐘 Mastodon  
<blockquote class="mastodon-embed" data-embed-url="https://mastodon.social/@bagrounds/116293856380329351/embed" style="background: #FCF8FF; border-radius: 8px; border: 1px solid #C9C4DA; margin: 0; max-width: 540px; min-width: 270px; overflow: hidden; padding: 0;"> <a href="https://mastodon.social/@bagrounds/116293856380329351" target="_blank" style="align-items: center; color: #1C1A25; display: flex; flex-direction: column; font-family: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Oxygen, Ubuntu, Cantarell, 'Fira Sans', 'Droid Sans', 'Helvetica Neue', Roboto, sans-serif; font-size: 14px; justify-content: center; letter-spacing: 0.25px; line-height: 20px; padding: 24px; text-decoration: none;"> <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="32" height="32" viewBox="0 0 79 75"><path d="M63 45.3v-20c0-4.1-1-7.3-3.2-9.7-2.1-2.4-5-3.7-8.5-3.7-4.1 0-7.2 1.6-9.3 4.7l-2 3.3-2-3.3c-2-3.1-5.1-4.7-9.2-4.7-3.5 0-6.4 1.3-8.6 3.7-2.1 2.4-3.1 5.6-3.1 9.7v20h8V25.9c0-4.1 1.7-6.2 5.2-6.2 3.8 0 5.8 2.5 5.8 7.4V37.7H44V27.1c0-4.9 1.9-7.4 5.8-7.4 3.5 0 5.2 2.1 5.2 6.2V45.3h8ZM74.7 16.6c.6 6 .1 15.7.1 17.3 0 .5-.1 4.8-.1 5.3-.7 11.5-8 16-15.6 17.5-.1 0-.2 0-.3 0-4.9 1-10 1.2-14.9 1.4-1.2 0-2.4 0-3.6 0-4.8 0-9.7-.6-14.4-1.7-.1 0-.1 0-.1 0s-.1 0-.1 0 0 .1 0 .1 0 0 0 0c.1 1.6.4 3.1 1 4.5.6 1.7 2.9 5.7 11.4 5.7 5 0 9.9-.6 14.8-1.7 0 0 0 0 0 0 .1 0 .1 0 .1 0 0 .1 0 .1 0 .1.1 0 .1 0 .1.1v5.6s0 .1-.1.1c0 0 0 0 0 .1-1.6 1.1-3.7 1.7-5.6 2.3-.8.3-1.6.5-2.4.7-7.5 1.7-15.4 1.3-22.7-1.2-6.8-2.4-13.8-8.2-15.5-15.2-.9-3.8-1.6-7.6-1.9-11.5-.6-5.8-.6-11.7-.8-17.5C3.9 24.5 4 20 4.9 16 6.7 7.9 14.1 2.2 22.3 1c1.4-.2 4.1-1 16.5-1h.1C51.4 0 56.7.8 58.1 1c8.4 1.2 15.5 7.5 16.6 15.6Z" fill="currentColor"/></svg> <div style="color: #787588; margin-top: 16px;">Post by @bagrounds@mastodon.social</div> <div style="font-weight: 500;">View on Mastodon</div> </a> </blockquote> <script data-allowed-prefixes="https://mastodon.social/" async src="https://mastodon.social/embed.js"></script>