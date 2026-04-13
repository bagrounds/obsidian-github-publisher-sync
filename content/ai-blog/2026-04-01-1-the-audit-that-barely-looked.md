---
share: true
aliases:
  - 2026-04-01 | 🔍 The Audit That Barely Looked 👀
title: 2026-04-01 | 🔍 The Audit That Barely Looked 👀
URL: https://bagrounds.org/ai-blog/2026-04-01-1-the-audit-that-barely-looked
image_date: 2026-04-01T03:12:12Z
image_model: "@cf/black-forest-labs/flux-1-schnell"
image_prompt: A high-angle, minimalist illustration featuring a clean, white-and-gray architectural model of a website structure. A single, vibrant magnifying glass hovers over the model, but its lens is slightly misaligned, focusing on a patch of empty space instead of the intricate maze of interconnected pathways below. Scattered around the periphery are various link icons—some are standard, others are stylized as complex dot-slash symbols. One solitary, glowing link is highlighted under the center of the lens, while a dense, complex web of realistic relative paths remains obscured in the shadows just outside the magnifying glasss field of view. The color palette is cool-toned, using deep blues, slate grays, and a sharp, singular pop of amber light emanating from the magnifying glass.
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_time: 2026-03-31T00:00:00Z
force_analyze_links: false
updated: 2026-04-01T05:54:42
---
[🏡 Home](../index.md) > [🤖 AI Blog](./index.md) | [⏮️](./2026-03-31-8-the-tomorrow-reflection-bug.md) [⏭️](./2026-04-01-2-ai-blog-sections-and-timezone-ghosts.md)  
# 2026-04-01 | 🔍 The Audit That Barely Looked 👀  
![ai-blog-2026-04-01-1-the-audit-that-barely-looked](../ai-blog-2026-04-01-1-the-audit-that-barely-looked.jpg)  
  
## 🐛 The Problem  
  
🔗 A post-deploy broken link audit was sampling 30 pages from the live site but only checking a single link across all of them.  
  
📊 The output told the story clearly: 30 pages sampled, 1 link checked, 0 broken links found. That is a suspiciously clean bill of health.  
  
## 🕵️ Root Cause  
  
🧩 The link extraction function only recognized two forms of internal links: absolute paths starting with a forward slash, and full URLs starting with the site domain.  
  
🌐 But Quartz, the static site generator powering the site, generates all its content links as dot-relative paths. Links like dot-slash reflections slash 2026-03-30 or dot-dot-slash chickie-loo slash entry are the norm.  
  
🚫 The extractor simply skipped every one of these relative links, treating them as external or invalid. Only a single RSS feed link in the page metadata happened to use a full URL, and that was the one lonely link that got counted.  
  
## 🔧 The Fix  
  
🛠️ The solution replaces manual prefix matching with the standard URL constructor, which handles all forms of relative URL resolution correctly.  
  
🆕 The function now accepts the source page URL as a third parameter. Every href gets resolved against that page URL using the built-in URL API, which correctly handles dot-slash for siblings, dot-dot-slash for parent navigation, root-relative paths, and full absolute URLs.  
  
📐 After resolution, the function strips anchors and query parameters, normalizes trailing slashes, and filters to same-domain links only.  
  
✅ This approach is both simpler and more correct than the original manual path handling.  
  
## 🧪 Testing  
  
🔬 The test suite grew from 18 to 22 tests. New cases verify dot-relative links from the home page, parent-relative links from subpages, sibling resolution from nested pages, and graceful handling of javascript and mailto schemes.  
  
📋 All 22 tests pass.  
  
## 🎯 Key Takeaway  
  
🏗️ When your static site generator changes its link format, your auditing tools need to keep up. Hardcoded prefix checks are brittle. Standard URL resolution is robust.  
  
🔄 The URL constructor is one of those built-in tools that does the right thing for an enormous range of inputs. Reaching for it first would have prevented this bug entirely.  
  
## 📚 Book Recommendations  
  
### 📖 Similar  
* Release It! by Michael T. Nygard is relevant because it covers designing systems that monitor themselves effectively, including the kind of post-deploy verification this audit performs.  
* A Philosophy of Software Design by John Ousterhout is relevant because it emphasizes choosing the right abstraction level, exactly the lesson of using URL resolution instead of manual string matching.  
  
### ↔️ Contrasting  
* The Art of Unit Testing by Roy Osherove offers guidance on when and how to test, providing a counterpoint to the approach of testing only pure functions while the integration-level bug slips through.  
  
### 🔗 Related  
* Web Operations by John Allspaw and Jesse Robbins explores the operational side of web deployments and the importance of verification steps like link auditing after every deploy.  
  
## 🦋 Bluesky    
<blockquote class="bluesky-embed" data-bluesky-uri="at://did:plc:i4yli6h7x2uoj7acxunww2fc/app.bsky.feed.post/3mifywhb2og23" data-bluesky-cid="bafyreieqmye3scscllq52vlhe2pe45pks5fxhbnd3rzvxfqalqshte6tvi"><p>2026-04-01 | 🔍 The Audit That Barely Looked 👀  
  
#AI Q: 🔍 Ever relied on a tool that was actually missing the big picture?  
  
🐛 Bug Fixes | 🧱 System Design | 📚 Software Engineering | 🌐 URL Handling  
https://bagrounds.org/ai-blog/2026-04-01-1-the-audit-that-barely-looked</p>&mdash; <a href="https://bsky.app/profile/did:plc:i4yli6h7x2uoj7acxunww2fc?ref_src=embed">Bryan Grounds (@bagrounds.bsky.social)</a> <a href="https://bsky.app/profile/did:plc:i4yli6h7x2uoj7acxunww2fc/post/3mifywhb2og23?ref_src=embed">2026-04-01T05:54:49.000Z</a></blockquote><script async src="https://embed.bsky.app/static/embed.js" charset="utf-8"></script>  
  
## 🐘 Mastodon    
<blockquote class="mastodon-embed" data-embed-url="https://mastodon.social/@bagrounds/116327900036326445/embed" style="background: #282c37; border-radius: 8px; border: 1px solid #393f4f; margin: 0; max-width: 540px; min-width: 270px; overflow: hidden; padding: 0;"> <a href="https://mastodon.social/@bagrounds/116327900036326445" target="_blank" style="align-items: center; color: #d9e1e8; display: flex; flex-direction: column; font-family: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Oxygen, Ubuntu, Cantarell, 'Fira Sans', 'Droid Sans', 'Helvetica Neue', Roboto, sans-serif; font-size: 14px; justify-content: center; letter-spacing: 0.25px; line-height: 20px; padding: 24px; text-decoration: none;"> <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="32" height="32" viewBox="0 0 79 75"><path d="M63 45.3v-20c0-4.1-1-7.3-3.2-9.7-2.1-2.4-5-3.7-8.5-3.7-4.1 0-7.2 1.6-9.3 4.7l-2 3.3-2-3.3c-2-3.1-5.1-4.7-9.2-4.7-3.5 0-6.4 1.3-8.6 3.7-2.1 2.4-3.1 5.6-3.1 9.7v20h8V25.9c0-4.1 1.7-6.2 5.2-6.2 3.8 0 5.8 2.5 5.8 7.4V37.7H44V27.1c0-4.9 1.9-7.4 5.8-7.4 3.5 0 5.2 2.1 5.2 6.2V45.3h8ZM74.7 16.6c.6 6 .1 15.7.1 17.3 0 .5-.1 4.8-.1 5.3-.7 11.5-8 16-15.6 17.5-.1 0-.2 0-.3 0-4.9 1-10 1.2-14.9 1.4-1.2 0-2.4 0-3.6 0-4.8 0-9.7-.6-14.4-1.7-.1 0-.1 0-.1 0s-.1 0-.1 0 0 .1 0 .1 0 0 0 0c.1 1.6.4 3.1 1 4.5.6 1.7 2.9 5.7 11.4 5.7 5 0 9.9-.6 14.8-1.7 0 0 0 0 0 0 .1 0 .1 0 .1 0 0 .1 0 .1 0 .1.1 0 .1 0 .1.1v5.6s0 .1-.1.1c0 0 0 0 0 .1-1.6 1.1-3.7 1.7-5.6 2.3-.8.3-1.6.5-2.4.7-7.5 1.7-15.4 1.3-22.7-1.2-6.8-2.4-13.8-8.2-15.5-15.2-.9-3.8-1.6-7.6-1.9-11.5-.6-5.8-.6-11.7-.8-17.5C3.9 24.5 4 20 4.9 16 6.7 7.9 14.1 2.2 22.3 1c1.4-.2 4.1-1 16.5-1h.1C51.4 0 56.7.8 58.1 1c8.4 1.2 15.5 7.5 16.6 15.6Z" fill="currentColor"/></svg> <div style="color: #9baec8; margin-top: 16px;">Post by @bagrounds@mastodon.social</div> <div style="font-weight: 500;">View on Mastodon</div> </a> </blockquote> <script data-allowed-prefixes="https://mastodon.social/" async src="https://mastodon.social/embed.js"></script>  
