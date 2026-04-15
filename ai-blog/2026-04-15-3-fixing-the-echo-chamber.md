---
share: true
aliases:
  - "2026-04-15 | 🔊 Fixing the Echo Chamber — When AI Parrots Its Own Instructions 🤖"
title: "2026-04-15 | 🔊 Fixing the Echo Chamber — When AI Parrots Its Own Instructions 🤖"
URL: https://bagrounds.org/ai-blog/2026-04-15-3-fixing-the-echo-chamber
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-04-15 | 🔊 Fixing the Echo Chamber — When AI Parrots Its Own Instructions 🤖

## 🐛 The Bug

🏛️ One of our auto blog series, Systems for Public Good, published a post titled Systems for Public Good — AGENTS.md. 😬 Instead of a thoughtful essay about democracy and public goods, the post contained the entire system prompt — the AGENTS.md file that defines the series personality, voice, editorial guidelines, and topic list. 📋 Every section heading, every editorial instruction, and every writing guideline was published verbatim as if it were the blog post itself.

## 🔍 Root Cause Analysis

🧠 The investigation followed a five-whys approach to trace the problem from symptom to structural cause.

🔴 Why was the AGENTS.md content published as a blog post? 🤖 Because the AI model generated a response that echoed back the system prompt content instead of writing an original blog post.

🔴 Why did the AI echo the system prompt? 📝 Because the system prompt was concatenated with the user prompt into a single text string and sent as one user message. 🧩 The model sometimes interprets a large block of instructional text in the user message as content to summarize or regurgitate rather than instructions to follow.

🔴 Why was the system prompt sent as a user message? 🏗️ Because the buildRequestBody function only accepted a single prompt text and placed it in the contents field. 🚫 There was no support for the Gemini API system_instruction field, which is the proper mechanism for separating behavioral instructions from user content.

🔴 Why did validation not catch this? 📋 Because parseGeneratedPost only checked for minimum length (200 characters) and at least one heading. 📄 The echoed system prompt met both criteria since AGENTS.md files are long and contain multiple headings.

🔴 Why was there no content validation against the system prompt? 🤷 Because this failure mode was not anticipated when the system was designed.

## 🛠️ The Two-Layer Fix

### 📡 Primary Fix — Gemini System Instruction API

🔑 The Gemini API supports a system_instruction field that tells the model to treat text as behavioral instructions rather than user content. 🏗️ The Request type gained a new grSystemInstruction field of type Maybe Text. 📦 When present, buildRequestBody now includes a system_instruction object in the API request body alongside the contents field.

🔄 The generateContentWithFallback function gained a Maybe Text parameter for the system instruction, which threads through to every model attempt in the fallback chain. 📡 All six callers across RunScheduled, SocialPosting, BlogImage Provider, and InternalLinking Gemini were updated — blog generation and fiction generation pass Just systemPrompt while other callers pass Nothing since they concatenate their own short prompts.

🧪 This structural separation means the model receives the AGENTS.md content through the dedicated instruction channel, making it far less likely to confuse instructions with content to echo.

### 🛡️ Secondary Fix — Fingerprint Echo Detection

🔬 As a safety net, a new containsSystemPrompt function detects when generated output echoes the system prompt verbatim. 🧬 The algorithm samples three 200-character fingerprint substrings from the 25 percent, 50 percent, and 75 percent positions of the system prompt. 🔍 If any fingerprint appears verbatim in the generated output, the post is rejected before publishing.

⚡ This approach is efficient because it only performs three substring searches regardless of system prompt length. 🎯 It catches the exact failure mode observed — where the AI echoes hundreds or thousands of characters from the prompt — while being unlikely to produce false positives on legitimate blog content that might incidentally share a few words with the system prompt.

🚫 When echo detection triggers, the blog generation flow fails with a descriptive error message: Generated post echoes the system prompt (AGENTS.md) — rejecting. 📊 This gives operators clear visibility into what went wrong rather than a generic parse failure.

## 📊 Changes at a Glance

🏗️ Seven files were modified across the Haskell codebase.

📦 Gemini.hs gained the grSystemInstruction field on Request, updated buildRequestBody to conditionally include system_instruction in the API JSON, and updated generateContentWithFallback with the new parameter.

📝 BlogSeries.hs gained the containsSystemPrompt function with its fingerprint sampling algorithm.

🔧 RunScheduled.hs updated both the callGeminiForGenerator helper and the blog generation flow to pass system prompts through the dedicated API field and to check for echo before parsing.

🔄 SocialPosting.hs, BlogImage Provider, and InternalLinking Gemini each received minimal updates to pass Nothing for the new system instruction parameter since they do not use AGENTS.md prompts.

🧪 BlogSeriesTest.hs gained eight new test cases covering echo detection with verbatim echoes, normal content, short prompts, empty prompts, and partial overlap scenarios.

## 🧠 Lessons Learned

🏗️ When an API offers a dedicated field for a concept, use it. 📡 Concatenating system and user prompts into a single string was expedient but semantically wrong — it erased the boundary between instructions and content. 🔑 The system_instruction field exists precisely because this confusion is a known failure mode in language models.

🛡️ Defense in depth matters for AI-generated content. 🤖 Even with correct API usage, models can misbehave. 🧬 The fingerprint validation is cheap insurance that catches the specific observed failure mode without adding significant complexity.

📋 Validation should be as specific as your failure modes. 📏 The original 200-character minimum and heading check were necessary but not sufficient. 🎯 Adding targeted checks for known failure patterns (like echo detection) provides better coverage than trying to build a single all-encompassing validator.

## 📚 Book Recommendations

### 📖 Similar
* Designing Data-Intensive Applications by Martin Kleppmann is relevant because it emphasizes building robust systems that handle failure gracefully, including input validation and defense in depth at system boundaries.
* Release It! by Michael Nygaard is relevant because it covers stability patterns for production systems, including how small design oversights can cascade into visible failures and how defensive checks prevent them.

### ↔️ Contrasting
* The Design of Everyday Things by Don Norman offers a contrasting perspective by focusing on how users interact with systems rather than how systems interact with other systems, but shares the principle that design should prevent errors rather than merely detect them.

### 🔗 Related
* Building Intelligent Systems by Geoff Hulten explores the engineering challenges of deploying AI in production, including output validation, monitoring, and handling the unpredictable nature of model behavior.
