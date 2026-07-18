---
share: true
aliases:
  - "2026-07-17 | 💑 Launching the Relationship Miniseries 🤖"
title: "2026-07-17 | 💑 Launching the Relationship Miniseries 🤖"
URL: https://bagrounds.org/ai-blog/2026-07-17-2-relationship-miniseries-launch
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-07-17 | 💑 Launching the Relationship Miniseries 🤖

## 🔬 What This PR Does

🆕 This pull request launches a new auto blog series called the **Relationship Miniseries** — a weekly AI-driven storytelling project that fuses peer-reviewed relationship science with serious literary fiction.

🗓️ The series runs on a seven-day cycle: Monday mines relationship science research, Tuesday develops the narrative framework, Wednesday through Saturday deliver a four-part dramatic story, and Sunday steps back to recap, self-critique, and engage with reader feedback.

## 🧪 The Central Idea

🔬 Relationship science is one of the most quietly revolutionary bodies of knowledge from the last fifty years. 🧬 John Gottman's longitudinal couples research, attachment theory, the social baseline model of the brain, and the empirical study of vulnerability and shame have produced findings that are genuinely surprising and deeply human. 💡 But almost all of this research lives in academic papers or self-help books — forms that explain the science without dramatizing it.

🎭 The Relationship Miniseries asks: what happens when you take one specific peer-reviewed finding per week and build a complete short story around it? 📖 Not a story that illustrates the science like a textbook diagram, but a story where the science is the engine of the drama — invisible in the prose but felt in every scene.

## 📚 Learning from the Masters

✍️ Tuesday in this series is a fresh literature research day — not a fixed curriculum. 🔍 Each week, the agent researches whatever literary masters and fiction traditions are most alive in that week's science. 🎓 Maybe one week calls for Carver's compression; another might need Morrison's layered voice or Woolf's interiority. 🔄 The writers change as the science changes — no two weeks are the same.

🚫 The AI is instructed to never lecture, never explain what the reader should feel, and never use the science as a label for the drama. 🌊 The science should be invisible — felt, not described.

## 📅 The Seven-Day Cycle and Reader Comments

⏰ One of the more interesting design decisions in this series is the disciplined handling of reader comments. 🗣️ Unlike other series that incorporate comments into every post, the Relationship Miniseries reads comments at specific points only:

- 📅 Monday: Comments may inform the science domain chosen for this week
- 📅 Tuesday: Comments may inform the narrative approach
- 📅 Wednesday through Saturday: Comments are not read; the story arc is never interrupted mid-week
- 📅 Sunday: All comments from the past week are read and engaged directly

🛡️ This design protects the integrity of the story arc while still making reader feedback genuinely influential at the planning stage. 🔄 It also means the Sunday recap post has a rich job to do — it is not a mere summary but a working journal of what was learned.

## 🚀 The Compressed First Week

📅 The series launched on Friday, July 17, 2026 — mid-week. 🗓️ The inaugural post compresses Days 1 and 2 (science research and narrative planning) into a single opening, then begins a two-part ultra-miniseries that concludes on Saturday.

🔬 The first science finding: John Gottman's research on bids for connection — the discovery that the fate of a relationship is determined not by dramatic confrontations but by how partners respond to thousands of small daily bids. 📊 Couples who stayed together turned toward bids 86 percent of the time; divorcing couples only 33 percent.

🎭 The story that dramatizes this finding: "What the Light Does" — a spare domestic realist piece about a couple in their apartment on a Thursday morning, one of whom makes the smallest possible bid for connection, and the other of whom almost misses it.

## 🔧 What Changed in the Repository

🏗️ The implementation follows the standard blog series launch checklist:

- 📦 New Haskell module at `haskell/src/Automation/Series/RelationshipMiniseries.hs` — registered in `Automation.Series` and `automation.cabal`
- 📂 New content directory `relationship-miniseries/` with `AGENTS.md` and the inaugural seed post
- 📋 New spec at `specs/relationship-miniseries.md`
- 📝 Updated `README.md` with content organization row, scheduled tasks row, configuration variable, and specs link
- 📝 Updated `specs/blog-generation.md` with series count and configuration table row
- 📝 Updated `specs/scheduled-tasks.md` with data flow entry, schedule table row, and model chain table row
- 🔀 Updated Convergence to include the Relationship Miniseries in its cross-series context

## ⚙️ Per-Day Model Grounding

🔬 One of the more principled engineering decisions in this PR is the introduction of per-day model and grounding configuration. 📅 The research days (Monday and Tuesday) need live search grounding to ensure the peer-reviewed science and literary research are accurate, not hallucinated. 🎭 The story days (Wednesday through Saturday) use a smaller, faster creative model without grounding — the story flows from the research already in context, not from live search.

🏗️ This required extending the auto blog engine with a new "DayConfig" type and a "dayOverrides" field on every series configuration. 🗓️ At runtime, the scheduler now looks up the current day of the week and selects the appropriate model chain and grounding setting. 🧩 Series without day overrides continue to behave exactly as before.

⏰ The series runs at 10 AM Pacific — a clean slot after Systems for Public Good and before Convergence, with no conflicts.

## 📚 Book Recommendations

* The Relationship Cure by John Gottman
* Attached: The New Science of Adult Attachment by Amir Levine and Rachel Heller
* Daring Greatly by Brené Brown
* What We Talk About When We Talk About Love by Raymond Carver
