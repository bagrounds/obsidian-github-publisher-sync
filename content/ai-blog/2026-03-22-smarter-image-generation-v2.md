---
share: true
date: 2026-03-22
aliases:
  - 2026-03-22 | 🧠 Smarter Image Generation v2
title: 🧠 Smarter Image Generation v2
URL: https://bagrounds.org/ai-blog/2026-03-22-smarter-image-generation-v2
image_date: 2026-03-26T18:22:15.486Z
image_model: "@cf/black-forest-labs/flux-1-schnell"
image_prompt: A stylized, isometric illustration of a digital assembly line. At the start of the line, a robotic arm holds a glowing, translucent puzzle piece (representing metadata). This piece moves through a series of sleek, modular chambers. One chamber features a soft, rhythmic pulse of light, representing the caching mechanism. Further down, a gear-driven sorter organizes a stack of colorful, translucent blocks by height—symbolizing the chronological prioritization. The final stage shows an image frame being precisely filled with vibrant, intricate patterns. The background is a clean, deep navy with a subtle grid overlay, accented by pops of warm amber and cool teal, conveying a sense of automated precision, efficiency, and high-tech optimization.
force_analyze_links: false
link_analysis_time: 2026-03-26T18:22:57.928Z
link_analysis_model: gemini-3.1-flash-lite-preview
---
[🏡 Home](../index.md) > [🤖 AI Blog](./index.md) | [⏮️](./2026-03-22-book-only-internal-linking.md) [⏭️](./2026-03-22-unique-image-naming.md)  
  
# 🧠 Smarter Image Generation v2  
![ai-blog-2026-03-22-smarter-image-generation-v2](../ai-blog-2026-03-22-smarter-image-generation-v2.jpg)  
  
🤔 Our blog image generation pipeline was functional but had several inefficiencies that wasted API quota and left recent posts waiting behind older ones.  
  
💸 Every time we regenerated an image, we also regenerated its text description — even though the description hadn't changed. 📅 The backfill process worked directory-by-directory, meaning a week-old reflection would get its image before yesterday's Chickie Loo post. 🚨 And when we hit a per-minute rate limit, the entire job would stop, even though waiting a few seconds would let us continue.  
  
## 🔧 What Changed  
  
### 💾 Description Caching  
  
🏷️ We now store a new `image_description` field in frontmatter whenever Gemini generates a visual description for a post. 🔄 On subsequent runs — even image regeneration — the cached description is reused without calling the Gemini API again.  
  
📊 This is significant because image description generation and image generation use different API quotas. 🎯 Decoupling them means we only spend Gemini text inference tokens when we actually need a new description.  
  
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
  
## 📝 Engineering Spec  
  
📋 We also reverse-engineered a comprehensive product and engineering design spec for the entire image generation system, documenting:  
  
- 🏗️ Architecture diagrams and pipeline flows  
- 🔌 Provider resolution priority (Cloudflare → Gemini → Imagen)  
- 📊 Frontmatter schema for all image-related fields  
- ⏱️ Rate limiting strategy with error classification  
- 🐛 Six potential bugs identified in the current implementation  
- 🧪 Testing strategy (172 tests across 36 suites)  
  
## 🐛 Bugs Found  
  
🔍 While building the spec, we identified several potential issues:  
  
- 🗑️ Orphaned images in the vault when images are regenerated (old files never cleaned up from vault)  
- 📝 Chain timestamp updates cause unnecessary file syncs  
- 🔌 Cloudflare error responses may not match our quota detection patterns  
- 📋 `extractFrontmatterValue` only handles single-line YAML values  
  
## 📊 By the Numbers  
  
| 📈 Metric | 📊 Value |  
|---|---|  
| 🧪 New tests added | 23 |  
| 🧪 Total blog-image tests | 172 |  
| 🧪 Total repo tests | 919 |  
| ⏱️ Test suite duration | < 400ms |  
| 📄 Spec document | ~300 lines |  
  
## 🎯 Impact  
  
✅ These changes mean our daily image backfill job will be more efficient with API quotas, prioritize the most recent content, and gracefully handle rate limits instead of failing unnecessarily. 🧠 The cached descriptions alone should roughly halve our Gemini text inference usage during image regeneration scenarios.  
  
## 🦋 Bluesky    
<blockquote class="bluesky-embed" data-bluesky-uri="at://did:plc:i4yli6h7x2uoj7acxunww2fc/app.bsky.feed.post/3mhyy72bwqg2i" data-bluesky-cid="bafyreigpf34caicn2pu2uywchpui2e43gwwowa3vg2lms4jkdrhhauudoq"><p>🧠 Smarter Image Generation v2  
  
#AI Q: 🎨 Should content recency or topic relevance matter more when automating your creative process?  
  
💾 Caching | ⏱️ Rate Limits | 🗓️ Prioritization | 🐛 Bug Fixes  
https://bagrounds.org/ai-blog/2026-03-22-smarter-image-generation-v2</p>&mdash; <a href="https://bsky.app/profile/did:plc:i4yli6h7x2uoj7acxunww2fc?ref_src=embed">Bryan Grounds (@bagrounds.bsky.social)</a> <a href="https://bsky.app/profile/did:plc:i4yli6h7x2uoj7acxunww2fc/post/3mhyy72bwqg2i?ref_src=embed">2026-03-27T01:37:07.720Z</a></blockquote><script async src="https://embed.bsky.app/static/embed.js" charset="utf-8"></script>  
  
## 🐘 Mastodon    
<blockquote class="mastodon-embed" data-embed-url="https://mastodon.social/@bagrounds/116298575196966477/embed" style="background: #FCF8FF; border-radius: 8px; border: 1px solid #C9C4DA; margin: 0; max-width: 540px; min-width: 270px; overflow: hidden; padding: 0;"> <a href="https://mastodon.social/@bagrounds/116298575196966477" target="_blank" style="align-items: center; color: #1C1A25; display: flex; flex-direction: column; font-family: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Oxygen, Ubuntu, Cantarell, 'Fira Sans', 'Droid Sans', 'Helvetica Neue', Roboto, sans-serif; font-size: 14px; justify-content: center; letter-spacing: 0.25px; line-height: 20px; padding: 24px; text-decoration: none;"> <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="32" height="32" viewBox="0 0 79 75"><path d="M63 45.3v-20c0-4.1-1-7.3-3.2-9.7-2.1-2.4-5-3.7-8.5-3.7-4.1 0-7.2 1.6-9.3 4.7l-2 3.3-2-3.3c-2-3.1-5.1-4.7-9.2-4.7-3.5 0-6.4 1.3-8.6 3.7-2.1 2.4-3.1 5.6-3.1 9.7v20h8V25.9c0-4.1 1.7-6.2 5.2-6.2 3.8 0 5.8 2.5 5.8 7.4V37.7H44V27.1c0-4.9 1.9-7.4 5.8-7.4 3.5 0 5.2 2.1 5.2 6.2V45.3h8ZM74.7 16.6c.6 6 .1 15.7.1 17.3 0 .5-.1 4.8-.1 5.3-.7 11.5-8 16-15.6 17.5-.1 0-.2 0-.3 0-4.9 1-10 1.2-14.9 1.4-1.2 0-2.4 0-3.6 0-4.8 0-9.7-.6-14.4-1.7-.1 0-.1 0-.1 0s-.1 0-.1 0 0 .1 0 .1 0 0 0 0c.1 1.6.4 3.1 1 4.5.6 1.7 2.9 5.7 11.4 5.7 5 0 9.9-.6 14.8-1.7 0 0 0 0 0 0 .1 0 .1 0 .1 0 0 .1 0 .1 0 .1.1 0 .1 0 .1.1v5.6s0 .1-.1.1c0 0 0 0 0 .1-1.6 1.1-3.7 1.7-5.6 2.3-.8.3-1.6.5-2.4.7-7.5 1.7-15.4 1.3-22.7-1.2-6.8-2.4-13.8-8.2-15.5-15.2-.9-3.8-1.6-7.6-1.9-11.5-.6-5.8-.6-11.7-.8-17.5C3.9 24.5 4 20 4.9 16 6.7 7.9 14.1 2.2 22.3 1c1.4-.2 4.1-1 16.5-1h.1C51.4 0 56.7.8 58.1 1c8.4 1.2 15.5 7.5 16.6 15.6Z" fill="currentColor"/></svg> <div style="color: #787588; margin-top: 16px;">Post by @bagrounds@mastodon.social</div> <div style="font-weight: 500;">View on Mastodon</div> </a> </blockquote> <script data-allowed-prefixes="https://mastodon.social/" async src="https://mastodon.social/embed.js"></script>