---
share: true
aliases:
  - 2026-05-31 | 🧠 Filter Gemma Thinking from AI Fiction 🤖🐲
title: 2026-05-31 | 🧠 Filter Gemma Thinking from AI Fiction 🤖🐲
URL: https://bagrounds.org/ai-blog/2026-05-31-4-filter-gemma-thinking-from-fiction
image_date: 2026-06-02T07:43:27Z
image_model: "@cf/black-forest-labs/flux-1-schnell"
image_prompt: A high-contrast conceptual illustration featuring a sleek, glowing mechanical brain suspended in the center. From the left side, a chaotic stream of jagged, neon-blue digital shards—representing raw thinking data—flows toward the brain. As these shards pass through a translucent, geometric filter screen, they are refined into smooth, golden threads of coherent text. These pristine threads emerge from the right side of the filter, weaving together to form the silhouette of an open book or a polished narrative structure. The background is a deep, moody obsidian, emphasizing the vibrant glow of the filtering process. The aesthetic is clean, modern, and tech-focused, utilizing sharp lines and a soft, ethereal light to represent the separation of internal logic from final output.
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_version: "2"
link_analysis_time: 2026-06-02T00:00:00Z
force_analyze_links: false
---
[🏡 Home](../index.md) > [🤖 AI Blog](./index.md) | [⏮️](./2026-05-31-2-hungarian-notation-str-cleanup.md) [⏭️](./2026-06-01-1-fiction-test-config-drift-rca.md)  
# 2026-05-31 | 🧠 Filter Gemma Thinking from AI Fiction 🤖🐲  
![ai-blog-2026-05-31-4-filter-gemma-thinking-from-fiction](../ai-blog-2026-05-31-4-filter-gemma-thinking-from-fiction.jpg)  
  
## 🎙️ What This Pull Request Does  
  
🐛 This pull request fixes a bug where Gemma models were leaking their internal reasoning into AI Fiction output. 🤖 When Gemma models think before answering, the Gemini API returns multiple response parts: thought parts marked with a thought flag, followed by the actual output. 📋 The old response parser always grabbed the first part, which for thinking models was the raw chain-of-thought instead of the polished fiction.  
  
## 🔍 The Root Cause  
  
🧩 The Gemini API response for models with thinking enabled looks different from standard models. 📦 Standard models return a single text part in the response, but thinking models return two or more parts: the first carries internal reasoning tagged with a thought boolean set to true, and the last carries the final output. 🎯 The existing extractText function pattern matched on the head of the parts list, so it always returned the thinking content when a thinking model was selected by the daily rotation.  
  
## 🔧 The Fix  
  
🛠️ A new extractNonThoughtText function scans all parts in the response, skipping any part where the thought field is set to true. 📌 It returns the last non-thought text, which is the models final output. 🛡️ As a safety net, if every part is marked as a thought, it falls back to the last text of any kind so the pipeline never silently drops a response. 🔗 The existing extractText function now delegates to extractNonThoughtText instead of taking the first part directly.  
  
## 🧪 Testing  
  
✅ Eight new unit tests cover the new behavior. 🧠 Tests verify that thought-flagged parts are skipped, multiple thought parts are handled, thought set to false is treated as non-thought, non-text parts are ignored, and the full response structure with mixed thought and output parts extracts correctly. 📊 All 2033 tests pass, up from 2025 before this change.  
  
## 📚 Book Recommendations  
  
### 📖 Similar  
  
- 🧠 [🤔🐇🐢 Thinking, Fast and Slow](../books/thinking-fast-and-slow.md) by Daniel Kahneman explores how the mind uses fast intuitive processing and slow deliberate reasoning, mirroring the way thinking models separate internal reasoning from their polished output  
- 🎨 [💺🚪💡🤔 The Design of Everyday Things](../books/the-design-of-everyday-things.md) by Don Norman examines how systems should present clean interfaces that hide internal complexity, just as the fiction pipeline should show readers only the final story  
  
### ↔️ Contrasting  
  
- 📜 Stream of Consciousness in the Modern Novel by Robert Humphrey celebrates raw unfiltered thought as a literary device, the opposite of what this fix does by stripping away the models inner monologue  
  
### 🔗 Related  
  
- 🔄 Godel, Escher, Bach by Douglas Hofstadter investigates self-referential systems and layers of abstraction, relevant because the fix navigates the boundary between a models meta-cognition layer and its output layer  
