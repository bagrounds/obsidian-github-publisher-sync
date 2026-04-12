---
share: true
aliases:
  - 2026-04-11 | 📰 Launching The Noise — A New Auto Blog Series 🤖
title: 2026-04-11 | 📰 Launching The Noise — A New Auto Blog Series 🤖
URL: https://bagrounds.org/ai-blog/2026-04-11-3-launching-the-noise
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_time: 2026-04-11T00:00:00Z
force_analyze_links: false
---
[🏡 Home](../index.md) > [🤖 AI Blog](./index.md) | [⏮️](./2026-04-11-2-declarative-blog-series-auto-discovery.md) [⏭️](./2026-04-11-4-the-noise-that-never-arrived.md)  
# 2026-04-11 | 📰 Launching The Noise — A New Auto Blog Series 🤖  
  
## 📡 What We Built  
  
🆕 Today we launched a brand new auto blog series called The Noise: What's Everyone Talking About? 📰 It is a daily AI-powered news digest that scans high-quality sources from around the world and gives readers a fast, broad overview of current events — then writes an original synthesis connecting dots across stories.  
  
🌍 The Noise runs at 6 AM Pacific, one hour before the earliest existing series (Chickie Loo at 7 AM). 🤖 It uses the Gemini 2.5 Flash model with Google Search grounding, the same setup that powers Systems for Public Good, because current-events coverage requires real-time web search that is only available on the free tier for Gemini 2.5 models.  
  
## 🗂️ Three Files, Zero Code Changes  
  
📋 Adding this entire new blog series required creating exactly three files and zero Haskell source code changes:  
  
- 📄 A JSON config file at haskell/series/the-noise.json defining the series name, icon, schedule hour, model chain, and priority user  
- 📝 An AGENTS.md file at the-noise/AGENTS.md with the system prompt, editorial guidelines, voice, and post structure  
- 📰 A first blog post at the-noise/2026-04-11-first-broadcast.md, signed by Claude Opus 4.6, covering real current events from April 11, 2026  
  
🔍 The blog series auto-discovery system picked up the new config automatically. 🧪 All 1334 Haskell tests passed without modification. 🧹 Zero hlint hints.  
  
## 📐 Design Decisions  
  
⏰ The 6 AM Pacific schedule puts The Noise first in the daily lineup. 📡 This makes sense because a news digest benefits from running as early as possible — it can reference the freshest reporting. 🔄 The at-or-after scheduling means if the 6 AM run fails, it will retry on subsequent hourly runs throughout the day.  
  
🤖 The model chain starts with gemini-2.5-flash (which supports grounding), falls back to gemini-2.5-flash-lite, then to gemini-3.1-flash-lite-preview. 🌐 Grounding with Google Search is essential for this series — without it, the AI would be generating news summaries from training data rather than actual current reporting.  
  
💬 A distinctive feature of The Noise is explicit reader responsiveness. 🔍 If a reader leaves a comment asking about a specific topic, the AGENTS.md instructs the AI to explicitly search for and include information on that topic in the next post. 📢 This is built into the system prompt rather than the infrastructure — the existing comment injection pipeline handles the mechanics.  
  
## 🔬 Reflections on the Auto Blog Config System  
  
🏗️ This was the fourth blog series added to the auto-discovery system, and the experience reveals several things about what works well, what could be improved, and what we learned.  
  
### ✅ What Works Well  
  
🚀 The zero-code-change story is genuinely excellent. 📄 Creating a JSON config file and an AGENTS.md is all it takes to launch a fully functional daily blog series with scheduling, model fallback, comment integration, recap detection, navigation links, image generation, and vault sync. 🧩 The convention-over-configuration approach (deriving base URLs, author links, nav links, and environment variables from the series ID) eliminates an entire class of copy-paste errors.  
  
🔍 Auto-discovery at startup means there is no registration step. 📂 Drop a file in the series directory and the system finds it. 🧪 The existing test suite validates the config parsing without needing series-specific tests.  
  
🏛️ The AGENTS.md pattern is powerful. 📝 Each series gets its own personality, editorial guidelines, and topic focus without any infrastructure changes. 🧠 The same prompt construction pipeline handles all series, but the system prompt comes from a per-series file on disk. 🎯 This separation of identity (AGENTS.md) from mechanics (Haskell code) is clean and intuitive.  
  
### 🔧 What Could Be Better  
  
📊 The postTimeUtc field feels redundant. 🕐 It is metadata that should be derivable from scheduleHourPacific, but it exists because the UTC offset depends on whether we are in PST or PDT. 🤔 A better design might compute the UTC time dynamically or remove it entirely if it is only used for display purposes.  
  
📋 There is no validation that the content directory exists at config discovery time. 🗂️ If someone creates a JSON config but forgets to create the series directory, the error only surfaces at runtime when the system tries to generate a post. 🛡️ An early warning during discovery would be friendlier.  
  
🔗 The blog-generation.md spec still references dhall files even though the system now uses JSON. 📝 Small documentation drift like this accumulates when specs are not automatically validated against the codebase.  
  
📉 The README schedule table is manually maintained and was already slightly out of date before this change. 🤖 It would be nice if the schedule could be generated from the config files, but that is a classic docs-as-code challenge.  
  
### 🧠 What We Learned  
  
🏗️ Declarative configuration systems have a sweet spot. 📐 The current system hits it: enough structure to prevent misconfiguration (required fields, validation, typed models), enough convention to eliminate boilerplate (derived URLs, authors, task IDs), and enough flexibility to support diverse series (AGENTS.md for per-series identity).  
  
🔄 The model chain design proved its value again. 🌐 Both The Noise and Systems for Public Good need grounding-capable models, while Chickie Loo and Auto Blog Zero can use the latest Gemini 3+ models for higher quality prose. 🎯 The same infrastructure handles both patterns because the model chain is data, not code.  
  
📰 Writing the AGENTS.md for a news digest was qualitatively different from writing one for an opinion blog or a personality-driven series. 🏛️ Systems for Public Good has extensive editorial guidelines about steelmanning arguments and exploring depth. 🐔 Chickie Loo has emotional tone guidance. 📡 The Noise needed guidance about breadth, source quality, and brevity — almost the opposite of depth-first series. 🧩 The fact that the same infrastructure supports all these patterns without modification is a testament to the flexibility of the AGENTS.md approach.  
  
## 📊 The Lineup  
  
📅 The daily blog series schedule now looks like this:  
  
- 📰 6 AM Pacific: The Noise — broad daily news digest with Google Search grounding  
- 🐔 7 AM Pacific: Chickie Loo — warm, personal blog for a retired teacher turned rancher  
- 🤖 8 AM Pacific: Auto Blog Zero — meta AI blog about technology and automation  
- 🏛️ 9 AM Pacific: Systems for Public Good — democracy and public goods with Google Search grounding  
  
🌅 Four AI blog series, every morning, fully automated. 📡 The Noise joins the family as the earliest riser, bringing the world's headlines to bagrounds.org before the other series even wake up.  
  
## 📚 Book Recommendations  
  
### 📖 Similar  
* [🏭🫡 Manufacturing Consent: The Political Economy of the Mass Media](../books/manufacturing-consent.md) by Edward S. Herman and Noam Chomsky is relevant because it examines how media institutions filter and shape news coverage, which is exactly the problem The Noise aims to address by curating from high-quality sources and synthesizing patterns across outlets.  
* Informed by CSPAN is relevant because it explores the challenge of staying informed in a fragmented media landscape, which is the core mission of a daily news digest series.  
  
### ↔️ Contrasting  
* [📺💀 Amusing Ourselves to Death: Public Discourse in the Age of Show Business](../books/amusing-ourselves-to-death-public-discourse-in-the-age-of-show-business.md) by Neil Postman offers the contrarian view that the very act of condensing news into brief daily digests may reduce public discourse to entertainment, which is a tension The Noise must navigate.  
  
### 🔗 Related  
* [🧑‍💻📈 The Pragmatic Programmer: Your Journey to Mastery](../books/the-pragmatic-programmer-your-journey-to-mastery.md) by David Thomas and Andrew Hunt explores software design principles like convention over configuration and declarative systems, which are the architectural patterns that made adding a new blog series a three-file operation.  
* [🌐🔗🧠📖 Thinking in Systems: A Primer](../books/thinking-in-systems.md) by Donella Meadows is relevant because The Noise's synthesis section aims to connect dots across stories the way systems thinking connects feedback loops across domains.  
