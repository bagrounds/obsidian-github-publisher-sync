# 📰 The Noise — What's Everyone Talking About?

## 🎯 Overview

📡 A daily AI news digest that answers one question: what is everyone talking about? 🌍 Each post scans high-quality news sources worldwide and provides a fast, broad overview of as many current events as possible, followed by an original synthesis section that connects dots across stories.

## 🏗️ Architecture

📋 The Noise follows the standard blog series auto-discovery architecture documented in the [Blog Series Auto-Discovery spec](blog-series-discovery.md).

### 📦 Configuration

| 🏷️ Field | 📝 Value |
|---|---|
| 🆔 Series ID | `the-noise` |
| 📰 Display Name | The Noise |
| 🎨 Icon | 📰 |
| ⏰ Schedule Hour (Pacific) | 6 AM |
| 🕐 Post Time (UTC) | 14:00 |
| 👤 Priority User | bagrounds |
| 🤖 Model Chain | gemini-2.5-flash, gemini-2.5-flash-lite, gemini-3.1-flash-lite-preview |
| 🌐 Google Search Grounding | Yes (required for current events) |

### 🌐 Why Gemini 2.5 Flash

🔍 The Noise requires Google Search grounding to pull in current news from the past 24 to 48 hours. ⚠️ Grounding with Google Search is only available on the free tier for Gemini 2.5 models, not for Gemini 3 or later models. 🏛️ This is the same model chain used by the Systems for Public Good series for the same reason.

## 📐 Post Structure

### 📊 Section 1 — The Overview

- 📡 Searches for and summarizes as many distinct current events as possible from the past 24 to 48 hours
- 🗂️ Stories organized into thematic clusters with descriptive subheadings
- ⚡ Each story gets one to three sentences naming the source and key facts
- 🌍 Covers stories from multiple continents and domains
- 🔢 Targets at least 15 to 25 distinct stories per post

### 🧠 Section 2 — The Signal

- 🔗 An original synthesis section that connects dots between stories
- 💡 Identifies patterns, contradictions, or ironies across the full landscape
- 🔮 Optionally speculates about what to watch in coming days
- ❓ Ends with a thought-provoking observation or question

## ⏰ Schedule

📌 Runs at 6 AM Pacific — one hour before the earliest existing series (Chickie Loo at 7 AM). 🔄 Uses at-or-after scheduling like all blog series: eligible at 6 AM and remains eligible for the rest of the day.

## 💬 Reader Responsiveness

🔍 If a reader leaves a comment asking about a specific topic, the next post explicitly searches for information on that topic using the grounding tool and includes a dedicated subsection addressing their question. 📢 This is a core design principle — reader comments are the highest priority input.

## ⚖️ Editorial Standards

- 🏆 Source quality is paramount — exclusively use AP, Reuters, BBC, NPR, PBS, The Guardian, NYT, Washington Post, The Economist, Financial Times, Al Jazeera, ProPublica, Nature, Science, The Atlantic, Ars Technica, and similar outlets
- 📐 Neutral and factual in the overview section; opinion reserved for the synthesis
- 🌍 Global coverage — not US-centric
- 🚫 No links, URLs, or wikilinks — cite sources descriptively in plain prose
- 🚫 No quotation marks

## 📅 Recaps

- 📆 Sunday: weekly recap synthesizing the week's major stories
- 📆 Last day of month: monthly recap with emerging trends
- 📆 Last day of quarter: quarterly recap
- 📆 December 31: annual recap
- 🔄 Recaps emphasize which stories persisted, which faded, and what patterns emerged

## 🧪 Testing

🔬 No series-specific tests needed. 🔍 The standard blog series discovery tests in `BlogSeriesDiscoveryTest.hs` validate config parsing. 📋 The scheduler tests verify at-or-after scheduling behavior for all blog series.

## 📂 Files

| 📄 File | 📝 Purpose |
|---|---|
| `haskell/series/the-noise.json` | Series configuration |
| `the-noise/AGENTS.md` | System prompt with identity, voice, editorial guidelines |
| `the-noise/` | Content directory for generated posts |
