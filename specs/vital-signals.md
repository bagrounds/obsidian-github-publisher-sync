# ⚡ Vital Signals — Blog Series Spec

## 📋 Overview

⚡ **Vital Signals** is a daily AI-generated blog series that applies rigorous mental models and evidence-based frameworks to the fundamentals of human performance: energy, motivation, focus, executive function, rest, balance, and health.

🔬 Every post is grounded in peer-reviewed research and applies three core thinking frameworks: Systems Thinking, Tiny Habits, and First Principles. 🌅 Posts publish at 5 AM Pacific — the earliest slot in the pipeline — so the insights are ready when readers start their day.

## 🏗️ Architecture

🔄 Vital Signals uses the same blog generation pipeline as the other grounded series:

```
GitHub Actions cron (5 AM PT / 13:00 UTC)
  → Pull vault posts
  → Build context (AGENTS.md + previous posts + comments)
  → Generate post via Gemini with Google Search grounding
  → Generate cover image (optional)
  → Sync post + image to Obsidian vault
```

### 🔑 Series Configuration

| 🏷️ Aspect | 📝 Value |
|---|---|
| 🆔 Series ID | `vital-signals` |
| 🎨 Icon | ⚡ |
| 📛 Name | Vital Signals |
| ⏰ Schedule | 5 AM Pacific |
| 🤖 Primary model | `gemini-2.5-flash` |
| 🌐 Search grounding | Enabled |
| 👤 Priority user | `bagrounds` |
| 🌍 Base URL | `https://bagrounds.org/vital-signals` |

## 🧠 Model Selection

📊 The series uses `gemini-2.5-flash` as the primary model because:

1. 🔍 **Google Search grounding support** — Quality citations require grounding; `gemini-2.5-flash` reliably supports the `googleSearch` tool on the free tier
2. 💰 **Free tier availability** — `gemini-2.5-flash` is available on the Gemini API free tier with sufficient daily quota
3. 🧠 **Capable reasoning** — Applying systems thinking and first principles across neuroscience, sleep science, and behavioral research benefits from a capable model
4. 🔄 **Fallback chain** — Degrades gracefully to `gemini-2.5-flash-lite` then `gemini-3.1-flash-lite-preview` on quota or API errors

## 📝 Post Structure

🏗️ Every non-recap post follows a two-section structure with creative headings (never generic labels):

### 📡 Section 1 — The Signal

- 🔬 Grounds the post in 1–3 specific research findings from peer-reviewed sources or foundational expert work
- 🧠 Introduces or extends a named mental model explaining the underlying mechanism
- 🏗️ Applies Systems Thinking to show how the finding connects to the broader human performance ecosystem
- 🌱 Translates the insight into a Tiny Habits-compatible behavior: smallest possible, anchored, measurable
- 🔭 Applies First Principles to examine what the biology or psychology actually shows beneath conventional wisdom
- 📊 Distinguishes well-established findings from preliminary research; names researchers, institutions, or journals

### 🔀 Section 2 — The Pattern

- 🔗 Steps back from specific findings to identify a larger principle
- 🏗️ Connects the day's insight to the broader framework being built across the series
- 📈 Identifies leverage points — where small interventions have disproportionate returns
- ❓ Ends with a question or principle the reader can carry into their day

## ⏰ Schedule

🌅 Vital Signals runs at **5 AM Pacific** — the earliest blog series slot in the pipeline. 📋 This ensures the post is published and available before readers begin their day.

🔄 The task uses at-or-after scheduling: it becomes eligible at 5 AM Pacific and remains eligible for the rest of the day. 🛡️ The orchestrator checks whether today's post already exists before generating, providing resilience against partial failures.

## 📐 Editorial Standards

- 🔬 **Peer-reviewed sources first** — Prioritize journals (Nature, Science, PNAS, JAMA, Lancet, Cell, Sleep, Neuron, PLOS ONE) and published books by credentialed researchers
- 📰 **Quality science journalism** — Acceptable secondary sources include Ars Technica, Quanta, The Atlantic, Scientific American, NPR Science
- 🚫 **No pop-psychology** — Avoid content that misrepresents or cherry-picks research, biohacking claims without evidence, or self-help content without scientific basis
- 📊 **Evidence hierarchy** — Clearly distinguish RCTs, observational studies, mechanistic research, and expert opinion
- 🏷️ **Named sources** — Every cited finding names the researcher, institution, or journal
- 🚫 **No links** — All citations are descriptive prose, never URLs or wikilinks

## 📅 Periodic Recaps

| 📆 Trigger | 📝 Recap Type |
|---|---|
| Every Sunday | Weekly Recap — synthesizes the week's insights into a cohesive performance model |
| Last day of month | Monthly Recap — summarizes weekly recaps, identifies durable mental models |
| Last day of quarter | Quarterly Recap — traces how the evidence base and models evolved |
| December 31 | Annual Recap — full accounting of what the science showed and how models changed |

🔄 Each recap level reads from the level below: weekly reads daily posts, monthly reads weeklies, quarterly reads monthlies, annual reads quarterlies.

## 🧠 Core Frameworks

| 🏷️ Framework | 📝 Application |
|---|---|
| 🔄 Systems Thinking | Map feedback loops between energy, motivation, focus, rest, and health; identify leverage points |
| 🌱 Tiny Habits | Connect each insight to the smallest possible anchored behavior change |
| 🔭 First Principles | Decompose conventional wisdom to examine what the biology actually requires |
| 🗺️ Mental Models | Introduce named frameworks: effort-recovery model, allostatic load, ultradian rhythms, cognitive load theory, Default Mode Network, prefrontal-limbic balance |

## 📚 Topics

- ⚡ Energy management — ultradian rhythms, metabolic flexibility, the effort-recovery model, ATP and glucose dynamics
- 🎯 Motivation — dopamine circuitry, intrinsic motivation research, challenge and threat states, motivational interviewing
- 🔍 Focus and attention — prefrontal cortex function, Default Mode Network, directed versus diffuse attention, cognitive load theory
- 🧩 Executive function — working memory, task switching costs, inhibitory control, sleep and exercise effects on prefrontal function
- 😴 Rest and recovery — sleep stages and their functions, the glymphatic system, napping science, active versus passive recovery
- ⚖️ Balance — allostatic load, work-rest cycles, the distinction between eustress and distress, recovery from chronic stress
- 🏥 Health foundations — exercise as cognitive enhancer, nutrition and brain function, the gut-brain axis, hormesis
- 🏗️ Systems and frameworks — mental models that unify the topic space, second-order effects, feedback loop analysis

## 🧪 Testing

🔬 The series configuration is covered by the shared test infrastructure:
- 📐 `BlogSeriesDiscoveryTest.hs` — derivation tests verify that `deriveBlogSeriesConfig` and `deriveBlogSeriesRunConfig` correctly derive all fields from the `AutoBlogSeries` value
- 🗓️ `SchedulerTest.hs` — schedule entry tests verify `blog-series:vital-signals` is eligible at and after hour 5
- 📊 `BlogSeriesConfigTest.hs` — config lookup tests cover the series map used at runtime

## 📂 Files

| 📂 Path | 📝 Purpose |
|---|---|
| `haskell/src/Automation/Series/VitalSignals.hs` | Haskell series configuration module |
| `haskell/src/Automation/Series.hs` | Central registry — includes `VitalSignals.series` in `allSeries` |
| `haskell/automation.cabal` | Cabal exposed-modules entry |
| `vital-signals/AGENTS.md` | System prompt defining identity, voice, frameworks, editorial standards, topics |
| `vital-signals/2026-06-02-inaugural-the-energy-budget.md` | Inaugural seed post |
| `specs/vital-signals.md` | This spec |
