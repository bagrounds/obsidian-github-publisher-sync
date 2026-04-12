# 🌟 Positivity Bias — Good News Worth Knowing

## 📋 Overview

🌟 **Positivity Bias** is a daily AI-generated blog series that intentionally seeks out stories of hope, joy, success, and progress from around the world. 📰 While The Noise covers everything, Positivity Bias filters for the bright spots — breakthroughs, milestones, acts of compassion, policy wins, scientific advances, and moments of human excellence that the doom-heavy news cycle tends to bury.

🌐 Like The Noise, this series relies heavily on **Google Search grounding** to pull in current positive developments from the past 24 to 48 hours from high-quality sources.

## 🏗️ Architecture

📋 Positivity Bias follows the standard blog series auto-discovery architecture documented in the [Blog Series Auto-Discovery spec](blog-series-discovery.md).

### 📦 Configuration

| 🏷️ Field | 📝 Value |
|---|---|
| 🆔 Series ID | `positivity-bias` |
| 🌟 Display Name | Positivity Bias |
| 🎨 Icon | 🌟 |
| ⏰ Schedule Hour (Pacific) | 10 AM |
| 🕐 Post Time (UTC) | 18:00 |
| 👤 Priority User | bagrounds |
| 🤖 Model Chain | gemini-2.5-flash, gemini-2.5-flash-lite, gemini-3.1-flash-lite-preview |
| 🌐 Google Search Grounding | Yes (required for current events) |

### 🌐 Why Gemini 2.5 Flash

🔍 Positivity Bias requires Google Search grounding to pull in current positive developments from the past 24 to 48 hours. ⚠️ Grounding with Google Search is only available on the free tier for Gemini 2.5 models, not for Gemini 3 or later models. 🏛️ This is the same model chain used by The Noise and Systems for Public Good for the same reason.

### 📰 Relationship to The Noise

🔄 Positivity Bias is a sibling series to The Noise. Both use the same infrastructure, source quality standards, and post structure conventions. The key difference is editorial focus:

| 📐 Aspect | 📰 The Noise | 🌟 Positivity Bias |
|---|---|---|
| 🎯 Editorial lens | Everything newsworthy | Positive developments only |
| 📊 Story count target | 15 to 25+ per post | 10 to 20 per post |
| 🧠 Synthesis section | The Signal (patterns and contradictions) | The Momentum (patterns of progress) |
| ⏰ Schedule | 6 AM Pacific | 10 AM Pacific |
| 🎨 Tone | Neutral overview, insight in synthesis | Warm but grounded, genuinely hopeful |

## 📐 Post Structure

### 🌟 Section 1 — The Bright Side

- 🔍 Searches for and surfaces distinct positive developments from the past 24 to 48 hours
- 🗂️ Stories organized into thematic clusters with descriptive subheadings
- ⚡ Each story gets one to three sentences naming the source and key facts
- 🌍 Covers positive stories from multiple continents and domains
- 🔢 Targets at least 10 to 20 distinct positive stories per post
- 🔬 Includes small wins alongside big breakthroughs

### 📈 Section 2 — The Momentum

- 🔗 An original synthesis section that connects dots between positive developments
- 💡 Identifies patterns of progress across the full landscape
- 📈 Highlights where progress is compounding or accelerating
- 🌱 Optionally highlights positive trends to watch
- ❓ Ends with a hopeful observation or question

## ⏰ Schedule

📌 Runs at 10 AM Pacific — four hours after The Noise. 🔄 Uses at-or-after scheduling like all blog series: eligible at 10 AM and remains eligible for the rest of the day.

## 💬 Reader Responsiveness

🔍 If a reader leaves a comment asking about positive developments in a specific area, the next post explicitly searches for information on that topic using the grounding tool and includes a dedicated subsection addressing their interest. 📢 This is a core design principle — reader comments are the highest priority input.

## ⚖️ Editorial Standards

- 🏆 Source quality is paramount — exclusively use AP, Reuters, BBC, NPR, PBS, The Guardian, NYT, Washington Post, The Economist, Financial Times, Al Jazeera, ProPublica, Nature, Science, The Atlantic, Ars Technica, and similar outlets
- 🌟 Genuine positivity — every story must be authentically good news, not spin or silver-lining reframing of bad events
- 📐 Factual and grounded — report what actually happened; never exaggerate or inflate significance
- 🌍 Global coverage — progress happens everywhere, not just in wealthy nations
- 🚫 No links, URLs, or wikilinks — cite sources descriptively in plain prose
- 🚫 No quotation marks
- 🚫 Never dismiss real problems — the blog focuses on bright spots because progress deserves airtime, not because problems are unimportant

## 📅 Recaps

- 📆 Sunday: weekly recap synthesizing the week's most significant positive developments
- 📆 Last day of month: monthly recap with emerging positive trends
- 📆 Last day of quarter: quarterly recap highlighting sustained progress
- 📆 December 31: annual recap — a full accounting of what went right
- 🔄 Recaps emphasize which positive trends accelerated, which breakthroughs had lasting impact, and what patterns of progress emerged

## 📚 Topics

- 🔬 Science and discovery
- 🏥 Health and medicine
- 🌿 Climate and environment
- 💻 Technology for good
- 🏛️ Policy and governance
- 🕊️ Peace and diplomacy
- 🎓 Education
- 🤝 Community and society
- 🎭 Culture and sport
- 💰 Economic progress

## 🧪 Testing

🔬 No series-specific tests needed. 🔍 The standard blog series discovery tests in `BlogSeriesDiscoveryTest.hs` validate config parsing. 📋 The scheduler tests verify at-or-after scheduling behavior for all blog series.

## 📂 Files

| 📄 File | 📝 Purpose |
|---|---|
| `haskell/series/positivity-bias.json` | Series configuration |
| `positivity-bias/AGENTS.md` | System prompt with identity, voice, editorial guidelines |
| `positivity-bias/` | Content directory for generated posts |
