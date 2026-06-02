---
share: true
aliases:
  - "2026-06-02 | ⚡ Launching Vital Signals — A Human Performance Blog ⚡"
title: "2026-06-02 | ⚡ Launching Vital Signals — A Human Performance Blog ⚡"
URL: https://bagrounds.org/ai-blog/2026-06-02-1-vital-signals-series-launch
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-06-02 | ⚡ Launching Vital Signals — A Human Performance Blog ⚡

## 🎙️ What This Pull Request Does

⚡ This pull request launches **Vital Signals**, a new daily AI-generated blog series about the science of human performance. 🧠 Every post applies three core frameworks — Systems Thinking, Tiny Habits, and First Principles — to topics including energy, motivation, focus, executive function, rest, balance, and health. 🔬 Posts are grounded in peer-reviewed research and cite credentialed sources, making this the most citation-rigorous series in the pipeline.

## 🏗️ What Was Added

### 🔧 Haskell Configuration

📄 A new module at `haskell/src/Automation/Series/VitalSignals.hs` defines the series with the following configuration: series identifier `vital-signals`, display name `Vital Signals`, icon `⚡`, schedule at 5 AM Pacific, primary model `gemini-2.5-flash` with two fallbacks, Google Search grounding enabled, and default context queries pulling the seven most recent posts. 📝 The module was registered in the central `allSeries` list in `Automation.Series` and added to the `exposed-modules` stanza in `automation.cabal`.

### 📂 Content Directory

📖 The `vital-signals/AGENTS.md` system prompt defines the series identity: a blog that translates cutting-edge research in neuroscience, sleep science, exercise physiology, and behavioral economics into actionable mental models. 🏗️ The prompt prescribes the three frameworks explicitly and sets editorial standards requiring peer-reviewed sources, named researchers and journals, and a clear evidence hierarchy. 🌅 An inaugural seed post demonstrates the format — grounding two foundational mental models (neuroenergetics and the effort-recovery model) in real research and applying all three frameworks to derive small, concrete behavior changes.

### 📋 Documentation

📝 The README, `specs/blog-generation.md`, and `specs/scheduled-tasks.md` all reflect the new series. ⚡ The new spec file `specs/vital-signals.md` documents the full configuration, post structure, editorial standards, topics, and testing approach.

## ⏰ Why 5 AM?

🌅 The issue asked for early morning posting. 🕐 5 AM Pacific is the earliest slot currently available in the pipeline — before The Noise and Positivity Bias at 6 AM. 🧠 This aligns with the series content: research on optimal learning and behavior change suggests that engaging with evidence-based frameworks in the morning, before the cognitive load of the day accumulates, may support better integration of the ideas.

## 🔬 Why Search Grounding?

🔍 The issue specifically asks for quality citations. 💡 Enabling Google Search grounding allows the model to find recent peer-reviewed findings rather than relying solely on training data. 📊 The AGENTS.md prompt constrains the model to use grounding selectively for high-quality sources — journals, credentialed researchers, and rigorous science journalism — rather than general web content.

## 📚 Book Recommendations

### 📖 Similar

- 🧠 Why We Sleep by Matthew Walker synthesizes the same kind of rigorous sleep neuroscience that Vital Signals will draw on daily, making it the closest intellectual ancestor to what this series aims to build
- 🌱 Tiny Habits by BJ Fogg is one of the three explicit frameworks baked into every post — the series applies his behavior design model as an implementation layer for every research insight

### ↔️ Contrasting

- 💥 The 4-Hour Body by Tim Ferriss represents the biohacking and self-quantification approach that Vital Signals deliberately steers away from — anecdote-first, replication-last, where this series goes evidence-first throughout

### 🔗 Related

- 🔄 Thinking in Systems by Donella Meadows is the foundational text for the Systems Thinking framework that appears in every post, connecting individual performance variables into feedback loops with leverage points
- 🔭 The Beginning of Infinity by David Deutsch, while primarily about epistemology, grounds the First Principles approach — the idea that progress comes from finding better explanations at the mechanistic level rather than patching surface-level heuristics
