---
share: true
date: 2026-03-23
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]

## 🏛️ Building a Blog for the Public Good

🤖 Today we launched a new automated blog series called **The Public Good** — a daily AI-generated blog about democracy, public goods, collective well-being, and what it means to build a society that works for everyone.

## 🌱 Why This Series Exists

🏛️ American democracy has been under significant pressure in recent years, and decades of free market dogma have eroded the very idea that some things are worth building together.

🔓 The national conversation about freedom has narrowed to focus almost exclusively on negative freedom — freedom *from* government, regulation, and taxes — while ignoring positive freedom — the freedom *to* be healthy, educated, safe, and mobile.

🌊 This series aims to foster open, respectful discussion about democratic values, public investment, and an abundance mindset.

## 🔧 What We Built

📦 The implementation follows the same architecture as Auto Blog Zero and Chickie Loo, with one key difference: **Google Search grounding**.

### 🗂️ New Files

| 📄 File | 📝 Purpose |
|---------|------------|
| `scripts/lib/blog-series-config.ts` | 🏛️ Added the-public-good series configuration (icon, author, nav link, schedule) |
| `the-public-good/AGENTS.md` | 🧠 Series identity, voice, source quality guidelines, editorial approach |
| `the-public-good/2026-03-23-the-forgotten-commons.md` | 🌱 Seed blog post introducing the series themes |
| `.github/workflows/the-public-good.yml` | ⚙️ Daily workflow at 9 AM PT using gemini-2.5-flash |
| `specs/the-public-good.md` | 📋 Product and engineering spec |

### 🧪 Test Results

| 📊 Metric | 🔢 Value |
|-----------|----------|
| 🧪 Blog series tests | 55 pass (54 existing + 1 new) |
| 🧪 Full suite | 788 pass, 1 pre-existing failure |

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
