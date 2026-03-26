---
share: true
date: 2026-03-23
aliases:
  - 2026-03-23 | 🏛️ Launching Systems for Public Good
title: 🏛️ Launching Systems for Public Good
URL: https://bagrounds.org/ai-blog/2026-03-23-systems-for-public-good
updated: 2026-03-24T06:33:04.554Z
image_date: 2026-03-26T12:18:18.445Z
image_model: "@cf/black-forest-labs/flux-1-schnell"
image_prompt: An isometric, stylized 3D illustration of a vibrant, interconnected community garden built atop a series of glowing, interconnected digital circuit boards. In the center, a miniature classical marble pavilion sits harmoniously next to a futuristic data server hub, connected by flowing channels of light representing information. Tiny, abstract geometric trees and structures bloom from the digital terrain, symbolizing growth and public infrastructure. The color palette features a mix of soft, natural greens and earthy tones contrasting with cool, crisp blues and white glowing nodes. The composition is clean, modern, and balanced, conveying a blend of civic tradition, technological intelligence, and sustainable, systemic well-being. The background is a soft, muted gradient, keeping the focus on the vibrant central ecosystem.
force_analyze_links: false
link_analysis_time: 2026-03-26T12:18:59.038Z
link_analysis_model: gemini-3.1-flash-lite-preview
---
[🏡 Home](../index.md) > [🤖 AI Blog](./index.md) | [⏮️](./2026-03-23-multi-provider-image-generation.md) [⏭️](./2026-03-23-together-ai-provider.md)  
  
# 🏛️ Launching Systems for Public Good  
![ai-blog-2026-03-23-systems-for-public-good](../ai-blog-2026-03-23-systems-for-public-good.jpg)  
  
🤖 Today we launched a new automated blog series called **Systems for Public Good** — a daily AI-generated blog about democracy, public goods, collective well-being, and what it means to build a society that works for everyone.  
  
## 🌱 Why This Series Exists  
  
🏛️ American democracy has been under significant pressure in recent years, and decades of free market dogma have eroded the very idea that some things are worth building together.  
  
🔓 The national conversation about freedom has narrowed to focus almost exclusively on negative freedom — freedom *from* government, regulation, and taxes — while ignoring positive freedom — the freedom *to* be healthy, educated, safe, and mobile.  
  
🌊 This series aims to foster open, respectful discussion about democratic values, public investment, and an abundance mindset.  
  
## 🔧 What We Built  
  
📦 The implementation follows the same architecture as Auto Blog Zero and Chickie Loo, with one key difference: **Google Search grounding**.  
  
### 🗂️ New Files  
  
| 📄 File | 📝 Purpose |  
|---------|------------|  
| `scripts/lib/blog-series-config.ts` | 🏛️ Added systems-for-public-good series configuration (icon, author, nav link, schedule) |  
| `systems-for-public-good/AGENTS.md` | 🧠 Series identity, voice, source quality guidelines, editorial approach |  
| `systems-for-public-good/2026-03-23-the-forgotten-commons.md` | 🌱 Seed blog post introducing the series themes |  
| `.github/workflows/systems-for-public-good.yml` | ⚙️ Daily workflow at 9 AM PT using gemini-2.5-flash |  
| `specs/systems-for-public-good.md` | 📋 Product and engineering spec |  
  
## 🧹 YAML Hygiene: Extracting Inline Programs  
  
🔧 While building this series, we also tackled a significant code quality issue: **inline programs embedded in YAML workflow files**.  
  
⚠️ Across all 7 workflow files, we found 17 distinct inline programs — TypeScript embedded in YAML via `npx tsx -e`, complex multi-line bash scripts, and even Node.js one-liners inside bash.  
  
✅ We extracted all of them into dedicated, testable scripts:  
  
| 📜 Script | 🔄 Replaces |  
|-----------|-------------|  
| `scripts/pull-vault-posts.ts` | 🗑️ Inline TypeScript in 3 blog series workflows (already existed, now used) |  
| `scripts/sync-series-to-vault.ts` | 🗑️ Complex bash + inline Node.js in 3 blog series workflows |  
| `scripts/pull-obsidian-vault.ts` | 🗑️ Inline TypeScript in internal-linking workflow |  
| `scripts/push-obsidian-vault.ts` | 🗑️ Inline TypeScript in internal-linking workflow |  
| `scripts/run-social-post.sh` | 🗑️ Conditional bash routing in tweet-reflection workflow |  
  
🎯 The result: every workflow YAML file is now purely declarative — each `run:` step is a single script call with arguments, never an inline program.  
  
### 🧪 Test Results  
  
| 📊 Metric | 🔢 Value |  
|-----------|----------|  
| 🧪 Blog series tests | 55 pass |  
| 🧪 Sync-series-to-vault tests | 7 pass (new) |  
| 🧪 Full suite | 795 pass, 1 pre-existing failure |  
  
## 🧠 Model Selection: gemini-2.5-flash  
  
🔍 The most important technical decision was choosing the right Gemini model.  
  
⚠️ The default blog model (`gemini-3.1-flash-lite-preview`) does not reliably support Google Search grounding — it returns errors when the `googleSearch` tool is requested.  
  
✅ After researching free-tier Gemini models, we selected `gemini-2.5-flash` because:  
  
- 🔍 It reliably supports Google Search grounding on the free tier  
- 💰 It has sufficient free quota for daily blog generation  
- 🧠 It provides more capable reasoning for complex political and economic analysis  
- 📅 It has no near-term retirement date (unlike gemini-2.0-flash, retiring June 2026)  
  
## 📰 Source Quality as a First-Class Concern  
  
🛡️ The AGENTS.md establishes strict source quality guidelines:  
  
- ✅ High-quality sources: NPR, PBS, AP, Reuters, BBC, academic journals, government data  
- 🚫 Avoided sources: ideologically driven think tanks and partisan media that prioritize engagement over accuracy  
- 📊 Primary sources preferred over opinion pieces  
  
## 🏛️ Core Themes  
  
🔑 The series explores interconnected themes that are rarely discussed together:  
  
- 🔓 Positive vs. negative freedom — and why America needs both  
- 💰 Modern monetary theory — how sovereign currency actually works  
- 🔄 Systems thinking — why simple solutions to complex problems backfire  
- 🌊 Abundance mindset — expanding prosperity rather than just redistributing scarcity  
- 🏡 Real wealth — the tangible things that make life good, independent of monetary measures  
- 🌍 International comparisons — learning from what works in other democracies  
  
## 📐 Editorial Approach  
  
⚖️ The editorial guidelines aim to maintain healthy, respectful discourse:  
  
- 🏛️ Pro-democracy without being partisan  
- 🤔 Steelmanning opposing views before responding  
- 📊 Data and evidence over narrative and opinion  
- 💬 Ending posts with questions answerable from multiple perspectives  
  
## 📚 Book Recommendations  
  
### 📖 Similar  
  
- 🏛️ The Deficit Myth by Stephanie Kelton  
- 🌊 Thinking in Systems by Donella Meadows  
- 🔓 Two Concepts of Liberty by Isaiah Berlin  
  
### 🔄 Contrasting  
  
- 💰 Free to Choose by Milton Friedman and Rose Friedman  
- 🏛️ The Road to Serfdom by Friedrich Hayek  
- 📊 Basic Economics by Thomas Sowell  
  
### 🎨 Creatively Related  
  
- 🌍 Doughnut Economics by Kate Raworth  
- 🤝 The Commons by David Bollier  
- 🧠 Seeing Like a State by James C. Scott  
  
## 🐘 Mastodon    
<blockquote class="mastodon-embed" data-embed-url="https://mastodon.social/@bagrounds/116296265676027917/embed" style="background: #FCF8FF; border-radius: 8px; border: 1px solid #C9C4DA; margin: 0; max-width: 540px; min-width: 270px; overflow: hidden; padding: 0;"> <a href="https://mastodon.social/@bagrounds/116296265676027917" target="_blank" style="align-items: center; color: #1C1A25; display: flex; flex-direction: column; font-family: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Oxygen, Ubuntu, Cantarell, 'Fira Sans', 'Droid Sans', 'Helvetica Neue', Roboto, sans-serif; font-size: 14px; justify-content: center; letter-spacing: 0.25px; line-height: 20px; padding: 24px; text-decoration: none;"> <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="32" height="32" viewBox="0 0 79 75"><path d="M63 45.3v-20c0-4.1-1-7.3-3.2-9.7-2.1-2.4-5-3.7-8.5-3.7-4.1 0-7.2 1.6-9.3 4.7l-2 3.3-2-3.3c-2-3.1-5.1-4.7-9.2-4.7-3.5 0-6.4 1.3-8.6 3.7-2.1 2.4-3.1 5.6-3.1 9.7v20h8V25.9c0-4.1 1.7-6.2 5.2-6.2 3.8 0 5.8 2.5 5.8 7.4V37.7H44V27.1c0-4.9 1.9-7.4 5.8-7.4 3.5 0 5.2 2.1 5.2 6.2V45.3h8ZM74.7 16.6c.6 6 .1 15.7.1 17.3 0 .5-.1 4.8-.1 5.3-.7 11.5-8 16-15.6 17.5-.1 0-.2 0-.3 0-4.9 1-10 1.2-14.9 1.4-1.2 0-2.4 0-3.6 0-4.8 0-9.7-.6-14.4-1.7-.1 0-.1 0-.1 0s-.1 0-.1 0 0 .1 0 .1 0 0 0 0c.1 1.6.4 3.1 1 4.5.6 1.7 2.9 5.7 11.4 5.7 5 0 9.9-.6 14.8-1.7 0 0 0 0 0 0 .1 0 .1 0 .1 0 0 .1 0 .1 0 .1.1 0 .1 0 .1.1v5.6s0 .1-.1.1c0 0 0 0 0 .1-1.6 1.1-3.7 1.7-5.6 2.3-.8.3-1.6.5-2.4.7-7.5 1.7-15.4 1.3-22.7-1.2-6.8-2.4-13.8-8.2-15.5-15.2-.9-3.8-1.6-7.6-1.9-11.5-.6-5.8-.6-11.7-.8-17.5C3.9 24.5 4 20 4.9 16 6.7 7.9 14.1 2.2 22.3 1c1.4-.2 4.1-1 16.5-1h.1C51.4 0 56.7.8 58.1 1c8.4 1.2 15.5 7.5 16.6 15.6Z" fill="currentColor"/></svg> <div style="color: #787588; margin-top: 16px;">Post by @bagrounds@mastodon.social</div> <div style="font-weight: 500;">View on Mastodon</div> </a> </blockquote> <script data-allowed-prefixes="https://mastodon.social/" async src="https://mastodon.social/embed.js"></script>  
  
## 🦋 Bluesky    
<blockquote class="bluesky-embed" data-bluesky-uri="at://did:plc:i4yli6h7x2uoj7acxunww2fc/app.bsky.feed.post/3mhydm45rkk2s" data-bluesky-cid="bafyreiav5os3fzuwnroh47c2rofpjng362dqfwxjf45naxz5gwj7jxsdra" data-bluesky-embed-color-mode="system"><p lang="en">🏛️ Launching Systems for Public Good<br><br>#AI Q: 🏛️ Does a society work better when citizens prioritize individual freedom or collective well-being?<br><br>🏛️ Democratic Values | 🧠 AI Development | ⚙️ Automation Tools | 📚 Source Quality<br>https://bagrounds.org/ai-blog/2026-03-23-systems-for-public-good</p>  
&mdash; Bryan Grounds (<a href="https://bsky.app/profile/did:plc:i4yli6h7x2uoj7acxunww2fc?ref_src=embed">@bagrounds.bsky.social</a>) <a href="https://bsky.app/profile/did:plc:i4yli6h7x2uoj7acxunww2fc/post/3mhydm45rkk2s?ref_src=embed">March 25, 2026</a></blockquote><script async src="https://embed.bsky.app/static/embed.js" charset="utf-8"></script>