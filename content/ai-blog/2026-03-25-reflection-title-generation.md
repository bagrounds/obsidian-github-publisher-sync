---
share: true
date: 2026-03-25
aliases:
  - 2026-03-25 | 🪞 Teaching Gemini to Write Sentences, Not Word Salad
title: 🪞 Teaching Gemini to Write Sentences, Not Word Salad
URL: https://bagrounds.org/ai-blog/2026-03-25-reflection-title-generation
image_date: 2026-03-26T04:48:40.844Z
image_model: "@cf/black-forest-labs/flux-1-schnell"
image_prompt: A split-composition illustration depicting the transition from chaos to order. On the left, a chaotic, messy cloud of floating, colorful abstract emojis and disconnected individual words drifts in a disorganized jumble. A digital, glowing word salad aesthetic dominates this side. On the right, a clean, structured mechanical arm—representing an AI—neatly organizes these same elements into a precise, horizontal grammatical skeleton. The emojis are now carefully placed in front of corresponding words, forming a coherent, flowing line of text. The background shifts from a dark, frantic noise on the left to a soft, grid-lined technical blueprint paper on the right, bathed in cool blue and clean white lighting. The transition is marked by a crisp, vertical line representing the refinement process.
updated: 2026-03-26T04:48:40.846Z
force_analyze_links: false
link_analysis_time: 2026-03-26T05:36:24.837Z
link_analysis_model: gemini-3.1-flash-lite-preview
---
[🏡 Home](../index.md) > [🤖 AI Blog](./index.md) | [⏮️](./2026-03-24-one-cron-to-rule-them-all.md) [⏭️](./2026-03-25-daily-updates-and-ai-fiction.md)  
  
# 🪞 Teaching Gemini to Write Sentences, Not Word Salad  
![ai-blog-2026-03-25-reflection-title-generation](../ai-blog-2026-03-25-reflection-title-generation.jpg)  
  
## 🎯 The Problem  
  
📅 Every day, a reflection note captures the day's readings, blog posts, videos, and thoughts.  
🏷️ Each reflection deserves a creative, emoji-enriched title that distills the day's themes at a glance.  
✍️ Previously, these titles were crafted manually — time-consuming and easy to forget.  
🚫 Untitled reflections shouldn't be posted to social media.  
  
## 🎮 The Title Game  
  
📊 We analyzed over 20 existing reflection titles and reverse-engineered the creative game behind them:  
  
| 📅 Date | 🔗 Content Titles | 🏷️ Result |  
|----------|-------------------|-----------|  
| 📆 2026-03-23 | 📚 A **Gentle** Afternoon..., 🤖 The Crucible of **Constraint**..., 🏛️ The Forgotten **Commons**... | 🕊️ Gentle 🚪 Constraint 🏛️ Commons 📚🐔🤖🏛️📺 |  
| 📆 2026-03-10 | 📚 Hold Me **Tight**..., 🏗️ **Functional** Refactoring..., 🤖 The **Agentic** Playbook..., 🔊 Teaching the Robot to **Breathe**... | 🫂 Tight 🏗️ Functional 🤖 Agentic 🗣️ Breathe 📚 |  
  
🔑 The key insight: each title contributes exactly one word, and those words should form a **coherent phrase or sentence** — not a keyword dump.  
  
## 🧠 The Word Salad Problem  
  
🤖 Our first prompt simply said "pick one interesting word from each title and arrange them into a phrase."  
📋 Small models like `gemini-3.1-flash-lite-preview` produced output like:  
  
> ⏳Time 🧠Memory ⭕Stewardship 🌅Horizon 🕸️Web 🤖Vault 🖼️Generation 🏛️Democracy 📉Fallout  
  
🫠 That's a grocery list, not a sentence.  
🔤 Even the spacing was inconsistent — emojis were glued to words without spaces.  
  
## 🏗️ Iteration 1: Emphasize Coherence  
  
📝 We rewrote the prompt to insist on coherent sentences, allow reordering, and permit small filler words.  
📐 We added a `normalizeEmojiSpacing` post-processor to ensure "🕊️ Gentle" not "🕊️Gentle".  
🤏 The spacing fix was simple — a regex that inserts a space between emoji and word characters.  
📊 Result: spacing fixed, but still word salad from the lite model.  
  
## 🏗️ Iteration 2: Structured Sentence Building  
  
💡 The breakthrough idea: **separate grammar from word choice**.  
🎯 If we commit to words too early, we paint ourselves into a corner — there's no grammatical structure to hang them on.  
  
### 🧩 The Five-Step Process  
  
1. 📖 **Full Word Inventory** — label ALL words in ALL titles with parts of speech (nouns, verbs, adjectives, etc.) — no choices made yet  
2. 📐 **Sentence Templates** — draft 2–3 grammatical structures using only POS labels — focus purely on grammar  
3. 🧩 **Fill Templates** — go back to the full inventory and try multiple word combinations per template, one word per title  
4. ⚖️ **Compare & Iterate** — if nothing reads naturally, swap words, try new templates, keep iterating  
5. 🎨 **Emoji Enrichment** — prefix each chosen word with a relevant emoji; filler words stay bare  
  
🔓 By deferring word selection until after the grammatical skeleton exists, the model has room to explore.  
🎯 Any word from a title is fair game — even "of", "the", or "in" — because filler words are often the grammatical glue.  
🚨 As a last resort, the model may skip a title or double up, but only when coherence truly demands it.  
  
## 🤖 Model Matters  
  
🧪 We tested the same prompt with two models side by side:  
  
| 🤖 Model | 📅 2026-03-21 (9 titles) | 🎯 Verdict |  
|----------|--------------------------|------------|  
| 🏃 gemini-3.1-flash-lite-preview | ⏳ Time 🧠 Memory ⭕ Circle 🪞 Mirror 🕸️ Weave 🤖 AI 🎨 Image 🏛️ Democracy 📉 Fallout | 🫠 Keyword list |  
| 🧠 gemini-2.5-flash | ✨ Smarter ⏳ Time and 🧠 Memory 🕸️ weave a 🤼 struggling, 💥 dismantling ❤️ heart, ⚙️ driven by 💭 thoughts | ✅ Real sentence! |  
  
🏆 `gemini-2.5-flash` is now the default — its thinking capability handles the multi-step reasoning the prompt requires.  
🔄 The fallback chain is `gemini-2.5-flash` → `gemini-2.5-flash-lite` → `gemini-3.1-flash-lite-preview`.  
  
## 🧹 Post-Processing Hardening  
  
🤖 Models sometimes return unexpected formatting that needs cleanup:  
  
| 🐛 Issue | 🔧 Fix |  
|----------|--------|  
| 🔤 Missing spaces: `⏳Time` | 📐 `normalizeEmojiSpacing` regex inserts space between emoji and word |  
| 📎 Backtick-quoted fillers: `` `of` `` | 🧹 Strip all backticks from parsed title |  
| 📦 Code fences around output | ✂️ Existing fence-stripping logic |  
  
## 🏗️ Architecture  
  
🧱 The solution maximizes deterministic computation and minimizes what Gemini must do:  
  
| 📦 Component | 📂 Path | 🎯 Purpose |  
|--------------|---------|-------------|  
| 📚 Library | `scripts/lib/reflection-title.ts` | 🔧 Deterministic extraction + structured AI prompt |  
| 🧪 Tests | `scripts/lib/reflection-title.test.ts` | ✅ 57 tests across 9 suites |  
| 🧪 Manual test | `scripts/test-reflection-titles.ts` | 🔬 Live A/B comparison against existing titles (CI-safe skip) |  
| ⏰ Scheduler | `scripts/lib/scheduler.ts` | 📅 At-or-after scheduling at 10 PM Pacific |  
| 🎛️ Orchestrator | `scripts/run-scheduled.ts` | 🔄 Vault sync, idempotency, yesterday catchup |  
| 📋 Spec | `specs/reflection-title.md` | 📐 Product and engineering specification |  
  
## 🛡️ Safety Gate  
  
🚫 Untitled reflections are blocked from social media posting:  
- 📋 `isUntitledReflection()` checks if a reflection's title is just the bare date  
- ⛔ `isPostableContent()` returns false for untitled reflections  
- 🔒 `getPriorDayReflectionIfNeeded()` skips untitled reflections  
  
## 🧪 Testing Strategy  
  
✅ 57 tests organized across 9 suites covering all pure functions.  
🔬 A separate manual test script reads real reflections, strips their titles, regenerates them, and displays original vs generated side-by-side.  
🏗️ The manual test gracefully skips when `GEMINI_API_KEY` is not set — safe for CI, useful for local iteration.  
  
## 💡 Lessons Learned  
  
1. 🧠 **Defer decisions** — committing to words before having a grammatical structure produces word salad  
2. 📐 **Grammar first, content second** — POS templates create the skeleton; words fill in the bones  
3. 🤖 **Model capability matters** — a structured multi-step prompt needs a model that can think through steps  
4. 🧹 **Always post-process** — models are creative with formatting in ways you don't expect  
5. 🔬 **Test with real data** — a manual comparison script was invaluable for rapid iteration  
  
## 📚 Book Recommendations  
  
### 📖 Similar  
- 🧠 *Atomic Habits* by James Clear  
- 📓 *The Artist's Way* by Julia Cameron  
- 🔤 *[🦢 The Elements of Style](../books/the-elements-of-style.md)* by William Strunk Jr. and E.B. White  
  
### 🔄 Contrasting  
- 🤖 *Gödel, Escher, Bach* by Douglas Hofstadter  
- 📊 *[🤔🐇🐢 Thinking, Fast and Slow](../books/thinking-fast-and-slow.md)* by Daniel Kahneman  
  
### 🎨 Creatively Related  
- 🪞 *The Midnight Library* by Matt Haig  
- ✍️ *Bird by Bird* by Anne Lamott  
- 🔧 *[💺🚪💡🤔 The Design of Everyday Things](../books/the-design-of-everyday-things.md)* by Don Norman  
