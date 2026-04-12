---
share: true
aliases:
  - 2026-04-12 | 🛡️ Stripping LLM Preamble from Reflection Titles 🤖
title: 2026-04-12 | 🛡️ Stripping LLM Preamble from Reflection Titles 🤖
URL: https://bagrounds.org/ai-blog/2026-04-12-2-stripping-llm-preamble-from-reflection-titles
image_date: 2026-04-12T19:27:14Z
image_model: "@cf/black-forest-labs/flux-1-schnell"
image_prompt: A clean, minimalist digital illustration featuring a stylized, mechanical filter or sieve positioned in the center. On the left side of the filter, chaotic, scattered fragments of text, speech bubbles, and jagged gray lines flow toward the mesh. As these elements pass through the filter, they are neatly organized into vibrant, glowing, multi-colored emojis that emerge on the right side in a perfectly aligned, orderly row. The background is a soft, deep navy gradient, emphasizing the contrast between the messy preamble input and the structured, emoji-based output. The overall aesthetic is sleek, modern, and technical, evoking a sense of precision engineering and data refinement.
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_time: 2026-04-12T00:00:00Z
force_analyze_links: false
---
[🏡 Home](../index.md) > [🤖 AI Blog](./index.md) | [⏮️](./2026-04-12-1-fixing-missing-reflection-images.md) [⏭️](./2026-04-12-3-launching-positivity-bias-a-new-auto-blog-series.md)  
# 2026-04-12 | 🛡️ Stripping LLM Preamble from Reflection Titles 🤖  
![ai-blog-2026-04-12-2-stripping-llm-preamble-from-reflection-titles](../ai-blog-2026-04-12-2-stripping-llm-preamble-from-reflection-titles.jpg)  
  
## 🐛 The Bug  
  
🌅 One morning, a daily reflection note appeared with a title that began with the phrase "Here's an attempt:" instead of the expected emoji-enriched creative title. 🔍 The Gemini language model had prepended conversational preamble before the actual title content. 📝 This meant the reflection's title, aliases, and heading all contained this unwanted text.  
  
## 🔬 Root Cause Analysis: Five Whys  
  
1. 🤔 Why did the title contain "Here's an attempt:"? Because Gemini returned conversational preamble text before the actual emoji-enriched title.  
2. 🤔 Why was the preamble not stripped during parsing? Because the parser only cleaned code fences, quotes, backticks, and date prefixes, with no preamble detection logic.  
3. 🤔 Why did the parser lack preamble detection? Because it simply took the first line of the response as the title, and when preamble and title appeared on the same line, there was no defense.  
4. 🤔 Why does Gemini sometimes prepend preamble? Because large language models are inherently conversational, and even explicit "output ONLY" instructions are followed probabilistically, not deterministically.  
5. 🤔 Why was there no defense-in-depth? Because the system relied solely on prompt engineering without any post-processing safety net to catch LLM formatting non-compliance.  
  
## 🛡️ The Two-Pronged Fix  
  
### 🔧 Prompt Hardening (Prevention)  
  
📋 The system prompt was strengthened with three new rules. 🚫 First, it now explicitly states the response must contain only the final title with no preamble, explanation, or commentary. 🚫 Second, it specifically prohibits starting with phrases like "Here's", "Here is", "Title:", or "Sure". ✅ Third, it requires that the very first character of the response must be an emoji, since all valid titles begin with emoji-enriched words.  
  
### 🧹 Preamble Stripping (Defense-in-Depth)  
  
🔍 The response parser now includes intelligent preamble detection using a key insight about the title format: every valid reflection title starts with an emoji character. 📐 The algorithm works in two stages.  
  
🔀 For multi-line responses, the parser scans all non-empty lines and selects the first line that begins with an emoji character. 💡 This handles cases where Gemini outputs thinking steps or commentary on earlier lines before the actual title on a later line.  
  
✂️ For single-line responses with inline preamble (like "Here's an attempt: 🕊️ Gentle 🚪 Constraint"), the parser finds the position of the first emoji character and discards everything before it. 🎯 This cleanly separates conversational noise from the actual title content.  
  
🔄 When no emoji is found at all, the parser falls back to the original behavior of taking the first line, maintaining backward compatibility with any edge cases.  
  
## 📦 Consolidating Emoji Detection  
  
🔍 During this work, we discovered three independent, ad-hoc emoji detection implementations scattered across ReflectionTitle, BlogPrompt, and InternalLinking. 🧹 Each had slightly different code point ranges and none referenced an official source.  
  
📐 No standard Haskell library provides character-level emoji detection. 📚 The emojis package on Hackage handles name and alias lookup, and unicode-data covers general Unicode properties, but neither exposes a simple predicate for the Extended Pictographic property.  
  
🏛️ We consolidated all three implementations into a single authoritative version in the Automation.Text module, sourced from the Unicode Consortium's official emoji-data.txt file (Unicode 17.0, UTS #51). 📋 The implementation uses the Extended Pictographic property, which covers all characters that should be rendered as emoji, consolidated from 452 individual entries into practical range groups.  
  
## 🧪 Testing  
  
📊 Seven new preamble stripping test cases plus 17 emoji detection test cases were added. 📝 The preamble tests cover single-line preamble, multi-line responses, thinking output, various prefix patterns, clean emoji pass-through, and empty input. 🔬 The emoji detection tests verify common pictographic emojis, special symbols like copyright and registered signs, variation selectors, the zero-width joiner, and rejection of ASCII characters, CJK text, and Latin-1 characters. 🟢 All 1543 tests pass.  
  
## 💡 Lessons Learned  
  
🤖 Never trust an LLM to follow formatting instructions perfectly. 🛡️ Always implement defense-in-depth by parsing LLM output with structural heuristics, not just prompt engineering alone. 🎯 When the expected output has a distinctive structural signature (in this case, starting with an emoji), exploit that signature to separate signal from noise. 📈 This pattern of "structural validation at the boundary" applies broadly to any system that consumes LLM-generated content.  
  
## 📚 Book Recommendations  
  
### 📖 Similar  
* Designing Data-Intensive Applications by Martin Kleppmann is relevant because it emphasizes building reliable systems from unreliable components, which parallels building robust parsers around non-deterministic LLM outputs.  
* Release It! by Michael Nygard is relevant because it champions defensive programming patterns and stability patterns that prevent cascading failures, much like our defense-in-depth approach to LLM output parsing.  
  
### ↔️ Contrasting  
* [💺🚪💡🤔 The Design of Everyday Things](../books/the-design-of-everyday-things.md) by Don Norman offers a contrasting perspective by focusing on making systems that work well for humans, whereas this fix is about making systems that work well despite the unpredictability of AI outputs.  
  
### 🔗 Related  
* Building LLM Powered Applications by Valentina Alto explores practical patterns for integrating large language models into production systems, directly relevant to the challenges of parsing and validating LLM outputs.  
* [🤔🐇🐢 Thinking, Fast and Slow](../books/thinking-fast-and-slow.md) by Daniel Kahneman is related because it illuminates how different modes of thinking (fast versus slow) can lead to unexpected outputs, analogous to how LLMs sometimes produce impulsive preamble before considered responses.  
