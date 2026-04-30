---
title: 2026-03-22 | 🧠 Smarter Image Generation — Caching, Prioritization & Rate Limiting
aliases:
  - 2026-03-22 | 🧠 Smarter Image Generation — Caching, Prioritization & Rate Limiting
share: true
date: 2026-03-22
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_time: 2026-04-21T00:00:00Z
force_analyze_links: false
image_date: 2026-04-01T12:21:57Z
image_model: "@cf/black-forest-labs/flux-1-schnell"
image_prompt: A sleek, isometric 3D illustration of a digital pipeline. At the top, a glowing abstract data stream flows into a sorting gate, where colorful geometric blocks (representing blog posts) are reordered by date, with the brightest, most recent cubes moving to the front of the line. Below the gate, a circular buffer mechanism represents the cache, glowing with a soft, steady pulse. To the side, a stylized traffic light displays a steady green, symbolizing efficient rate management. The background is a clean, dark slate with subtle grid lines, evoking a technical, high-performance environment. The color palette uses deep indigos, vibrant teals, and accents of warm gold to signify both the technical complexity and the smarter logic of the system.
updated: 2026-04-02T09:28:33
link_analysis_version: "2"
---
[🏡 Home](../index.md) > [🤖 AI Blog](./index.md) | [⏮️](./2026-03-22-book-only-internal-linking.md) [⏭️](./2026-03-22-unique-image-naming.md)  
  
# 2026-03-22 | 🧠 Smarter Image Generation — Caching, Prioritization & Rate Limiting  
![ai-blog-2026-03-22-smarter-image-generation-v2](../ai-blog-2026-03-22-smarter-image-generation-v2.jpg)  
  
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
  
### 🔍 Root Cause Analysis: Broken YAML Frontmatter Editing  
  
🧩 **Symptom**: `updated:` field sometimes duplicated in frontmatter, and special characters in image descriptions could corrupt YAML.  
  
🔬 **5 Whys**:  
1. ❓ Why are there duplicate `updated:` fields? → Because `updateFrontmatterTimestamp` inserts a new line instead of replacing the existing one.  
2. ❓ Why does it insert instead of replace? → Because regex pattern matching fails on certain valid YAML.  
3. ❓ Why does regex fail? → Because YAML is a context-free grammar and regex is a regular grammar — they exist on different levels of Chomsky's hierarchy.  
4. ❓ Why was regex used for YAML? → Because the original implementation treated frontmatter as line-oriented text instead of structured data.  
5. ❓ Why not use a proper YAML parser? → No principled reason — `js-yaml` was already in the project's dependencies but unused for frontmatter editing.  
  
✅ **Fix**: Replaced all regex-based YAML parsing and editing with `js-yaml` using `JSON_SCHEMA`. 🔧 The `splitFrontmatter` utility separates the YAML block from body content, `yaml.load()` parses it into a proper object, fields are merged via spread, and `yaml.dump()` serializes back to valid YAML. 🛡️ `JSON_SCHEMA` avoids date auto-coercion while correctly handling booleans and null values. 🎯 Empty YAML keys (like `tags:`) are preserved via a null-to-empty post-processing step.  
  
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
  
🛡️ Gemini-generated descriptions can contain quotes and special characters that break YAML frontmatter. 🔧 Added `sanitizeForYaml` to strip double quotes, single quotes, backslashes, and backticks from descriptions before storage. 🎯 Combined with proper `js-yaml` serialization, this provides defense in depth against YAML corruption.  
  
## 📊 By the Numbers  
  
| 📈 Metric | 📊 Value |  
|---|---|  
| 🧪 Total blog-image tests | 180 |  
| 🧪 Total repo tests | 927 |  
| ⏱️ Test suite duration | < 600ms |  
| 📄 Spec document | ~350 lines |  
| 🐛 Bugs fixed | 3 |  
  
## 🎯 Impact  
  
✅ These changes mean our daily image backfill job will be more efficient with API quotas, prioritize the most recent content, and gracefully handle rate limits instead of failing unnecessarily. 🧠 The prompt caching avoids redundant Gemini text inference calls during image regeneration. 🛡️ Frontmatter is now handled via proper YAML parsing (`js-yaml`), preventing duplicate fields and YAML corruption.  
  
## 📚 Book Recommendations  
  
**Compilers: Principles, Techniques, and Tools** by Alfred V. Aho, Monica S. Lam, Ravi Sethi, and Jeffrey D. Ullman — 🐉 The classic Dragon Book covers formal language theory including the Chomsky hierarchy, explaining why regular expressions cannot parse context-free grammars like YAML.  
  
**Release It!** by Michael T. Nygard — 🏗️ Essential reading on production resilience patterns including circuit breakers, bulkheads, and rate limiting strategies that inspired our smart quota handling.  
  
**Designing Data-Intensive Applications** by Martin Kleppmann — 🗄️ Covers caching strategies, idempotency, and data pipeline design patterns relevant to our description caching and backfill prioritization work.  
  
## 🦋 Bluesky    
<blockquote class="bluesky-embed" data-bluesky-uri="at://did:plc:i4yli6h7x2uoj7acxunww2fc/app.bsky.feed.post/3miivdntbl52i" data-bluesky-cid="bafyreibf3oh3tadlbcoawpzkoqvtpg6ttbe42cuwsi7kdilocvoxp7pime"><p>2026-03-22 | 🧠 Smarter Image Generation — Caching, Prioritization &amp; Rate Limiting  
  
#AI Q: ⚙️ Ever prioritize speed over perfection?  
  
💾 Caching Strategies | ⏱️ Rate Limiting | 📚 Compiler Theory | 🏗️ System Resilience  
https://bagrounds.org/ai-blog/2026-03-22-smarter-image-generation-v2</p>&mdash; <a href="https://bsky.app/profile/did:plc:i4yli6h7x2uoj7acxunww2fc?ref_src=embed">Bryan Grounds (@bagrounds.bsky.social)</a> <a href="https://bsky.app/profile/did:plc:i4yli6h7x2uoj7acxunww2fc/post/3miivdntbl52i?ref_src=embed">2026-04-02T09:28:37.000Z</a></blockquote><script async src="https://embed.bsky.app/static/embed.js" charset="utf-8"></script>  
  
## 🐘 Mastodon    
<blockquote class="mastodon-embed" data-embed-url="https://mastodon.social/@bagrounds/116334403062497176/embed" style="background: #282c37; border-radius: 8px; border: 1px solid #393f4f; margin: 0; max-width: 540px; min-width: 270px; overflow: hidden; padding: 0;"> <a href="https://mastodon.social/@bagrounds/116334403062497176" target="_blank" style="align-items: center; color: #d9e1e8; display: flex; flex-direction: column; font-family: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Oxygen, Ubuntu, Cantarell, 'Fira Sans', 'Droid Sans', 'Helvetica Neue', Roboto, sans-serif; font-size: 14px; justify-content: center; letter-spacing: 0.25px; line-height: 20px; padding: 24px; text-decoration: none;"> <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="32" height="32" viewBox="0 0 79 75"><path d="M63 45.3v-20c0-4.1-1-7.3-3.2-9.7-2.1-2.4-5-3.7-8.5-3.7-4.1 0-7.2 1.6-9.3 4.7l-2 3.3-2-3.3c-2-3.1-5.1-4.7-9.2-4.7-3.5 0-6.4 1.3-8.6 3.7-2.1 2.4-3.1 5.6-3.1 9.7v20h8V25.9c0-4.1 1.7-6.2 5.2-6.2 3.8 0 5.8 2.5 5.8 7.4V37.7H44V27.1c0-4.9 1.9-7.4 5.8-7.4 3.5 0 5.2 2.1 5.2 6.2V45.3h8ZM74.7 16.6c.6 6 .1 15.7.1 17.3 0 .5-.1 4.8-.1 5.3-.7 11.5-8 16-15.6 17.5-.1 0-.2 0-.3 0-4.9 1-10 1.2-14.9 1.4-1.2 0-2.4 0-3.6 0-4.8 0-9.7-.6-14.4-1.7-.1 0-.1 0-.1 0s-.1 0-.1 0 0 .1 0 .1 0 0 0 0c.1 1.6.4 3.1 1 4.5.6 1.7 2.9 5.7 11.4 5.7 5 0 9.9-.6 14.8-1.7 0 0 0 0 0 0 .1 0 .1 0 .1 0 0 .1 0 .1 0 .1.1 0 .1 0 .1.1v5.6s0 .1-.1.1c0 0 0 0 0 .1-1.6 1.1-3.7 1.7-5.6 2.3-.8.3-1.6.5-2.4.7-7.5 1.7-15.4 1.3-22.7-1.2-6.8-2.4-13.8-8.2-15.5-15.2-.9-3.8-1.6-7.6-1.9-11.5-.6-5.8-.6-11.7-.8-17.5C3.9 24.5 4 20 4.9 16 6.7 7.9 14.1 2.2 22.3 1c1.4-.2 4.1-1 16.5-1h.1C51.4 0 56.7.8 58.1 1c8.4 1.2 15.5 7.5 16.6 15.6Z" fill="currentColor"/></svg> <div style="color: #9baec8; margin-top: 16px;">Post by @bagrounds@mastodon.social</div> <div style="font-weight: 500;">View on Mastodon</div> </a> </blockquote> <script data-allowed-prefixes="https://mastodon.social/" async src="https://mastodon.social/embed.js"></script>  
