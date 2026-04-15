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

🏛️ One of our auto blog series, Systems for Public Good, published a post titled Systems for Public Good — AGENTS.md. 😬 Instead of a thoughtful essay about democracy and public goods, the post contained the entire system prompt — the AGENTS.md file that defines the series personality, voice, editorial guidelines, and topic list — followed by the user prompt including the date, instructions, and recent post history. 📋 Every section heading, every editorial instruction, and every writing guideline was published verbatim as if it were the blog post itself.

## 🔍 Root Cause Analysis

🧠 The investigation followed a five-whys approach to trace the problem from symptom to structural cause.

🔎 First, we needed to determine whether the AI model actually echoed the prompt, or whether a code bug accidentally wrote the prompt text as the blog post output. 🔬 A careful trace through the code confirmed that generateContent parses the response body JSON and extracts text exclusively from the candidates array at the path candidates, content, parts, text. ✅ There is no fallback path, error handler, or default value that could return the input prompt as output. 📡 The model genuinely echoed the entire combined prompt back as its response.

🔴 Why was the AGENTS.md content published as a blog post? 🤖 Because the AI model generated a response that echoed back the entire combined prompt — both the system prompt and the user prompt — instead of writing an original blog post.

🔴 Why did the AI echo the prompt? 📝 Because the system prompt was concatenated with the user prompt into a single text string and sent as one user message in the contents field. 🧩 With no structural boundary between instructions and content, the model treated the massive instructional block as text to repeat rather than instructions to follow.

🔴 Why was the system prompt concatenated into the user message instead of using the system_instruction API field? 📦 Because the Gemma 3 model (gemma-3-27b-it), which is the default model in the codebase, does not support the system_instruction field in the Gemini API. 🔧 The original concatenation approach was chosen to ensure compatibility across all models in the fallback chain. 🚫 However, the blog series model chains (configured in their JSON files) actually use Gemini models like gemini-2.5-flash and gemini-3.1-flash-lite-preview, all of which do support system_instruction.

🔴 Why did validation not catch this? 📋 Because parseGeneratedPost only checked for minimum length (200 characters) and at least one heading. 📄 The echoed combined prompt met both criteria since AGENTS.md files are long and contain multiple headings.

🔴 Why was there no content validation against the system prompt? 🤷 Because this failure mode was not anticipated when the system was designed.

## 🛠️ The Three-Layer Fix

### 📡 Primary Fix — Model-Aware System Instruction API

🔑 The Gemini API supports a system_instruction field that tells the model to treat text as behavioral instructions rather than user content. 🏗️ The Request type gained a new requestSystemInstruction field of type Maybe Text, and generateContentWithFallback threads the optional system instruction through every model attempt in the fallback chain.

⚠️ Critically, not all models support this field. 🚫 Gemma 3 (gemma-3-27b-it), an open-source model accessed through the Gemini API, returns an error when system_instruction is included. ✅ All Gemini-family models (gemini-2.5-flash, gemini-3.1-flash-lite-preview, and others) do support it.

🧠 The fix is model-aware: a new supportsSystemInstruction function returns False for Gemma 3 and True for all Gemini models. 🔄 Inside generateContent, when the model does not support system_instruction, the system instruction is automatically concatenated back into the user prompt — preserving backward compatibility. 📡 When the model does support it, the system instruction is sent through the dedicated API field. 🎯 This means each model in a fallback chain gets the right treatment automatically, even when the chain mixes Gemma and Gemini models.

### 🛡️ Secondary Fix — Fingerprint Echo Detection

🔬 As a safety net, a new containsSystemPrompt function detects when generated output echoes the system prompt verbatim. 🧬 The algorithm samples three 200-character fingerprint substrings from the 25 percent, 50 percent, and 75 percent positions of the system prompt. 🔍 If any fingerprint appears verbatim in the generated output, the post is rejected before publishing.

⚡ This approach is efficient because it only performs three substring searches regardless of system prompt length. 🎯 It catches the exact failure mode observed — where the AI echoes hundreds or thousands of characters from the prompt — while being unlikely to produce false positives on legitimate blog content that might incidentally share a few words with the system prompt.

🚫 When echo detection triggers, the blog generation flow fails with a descriptive error message: Generated post echoes the system prompt (AGENTS.md) — rejecting. 📊 This gives operators clear visibility into what went wrong rather than a generic parse failure.

### 🔤 Naming Fix — No Abbreviations

📛 The Request record fields originally used a two-letter prefix (an abbreviation for Gemini Request) which violates the codebase convention of no abbreviations in names. 🔧 All five fields were renamed to use full words: requestPrompt, requestSystemInstruction, requestModel, requestApiKey, and requestGenerationConfig.

## 📊 Changes at a Glance

🏗️ Eight files were modified across the Haskell codebase.

📦 Gemini.hs gained the requestSystemInstruction field on Request, the supportsSystemInstruction function for model-aware behavior, and the buildRequestBody function (now exported for testing). 🔄 Inside generateContent, when a model does not support system_instruction, the system instruction is transparently concatenated into the user prompt.

📝 BlogSeries.hs gained the containsSystemPrompt function with its fingerprint sampling algorithm.

🔧 RunScheduled.hs updated both the callGeminiForGenerator helper and the blog generation flow to pass system prompts through the dedicated API field and to check for echo before parsing.

🔄 SocialPosting.hs, BlogImage Provider, and InternalLinking Gemini each received minimal updates for the new system instruction parameter.

🧪 GeminiTest.hs gained twelve new test cases covering supportsSystemInstruction for all model variants and buildRequestBody for system instruction inclusion and omission. 🧪 BlogSeriesTest.hs gained eight new test cases covering echo detection.

## 🧠 Lessons Learned

🏗️ When an API offers a dedicated field for a concept, use it — but check whether all your models support it first. 📡 Concatenating system and user prompts into a single string was the right choice for Gemma 3 compatibility, but it should not have been applied universally to models that support proper separation. 🔑 The system_instruction field exists precisely because prompt echoing is a known failure mode in language models.

🛡️ Defense in depth matters for AI-generated content. 🤖 Even with correct API usage, models can misbehave. 🧬 The fingerprint validation is cheap insurance that catches the specific observed failure mode without adding significant complexity.

📋 Validation should be as specific as your failure modes. 📏 The original 200-character minimum and heading check were necessary but not sufficient. 🎯 Adding targeted checks for known failure patterns provides better coverage than trying to build a single all-encompassing validator.

🔍 When debugging AI misbehavior, verify the code path first. 📝 The initial hypothesis was a code bug that accidentally wrote input as output, which turned out to be incorrect after careful code tracing. 🧪 But the investigation uncovered the real structural issue — universal concatenation instead of model-aware API usage — which led to a better fix.

## 📚 Book Recommendations

### 📖 Similar
* Designing Data-Intensive Applications by Martin Kleppmann is relevant because it emphasizes building robust systems that handle failure gracefully, including input validation and defense in depth at system boundaries.
* Release It! by Michael Nygaard is relevant because it covers stability patterns for production systems, including how small design oversights can cascade into visible failures and how defensive checks prevent them.

### ↔️ Contrasting
* The Design of Everyday Things by Don Norman offers a contrasting perspective by focusing on how users interact with systems rather than how systems interact with other systems, but shares the principle that design should prevent errors rather than merely detect them.

### 🔗 Related
* Building Intelligent Systems by Geoff Hulten explores the engineering challenges of deploying AI in production, including output validation, monitoring, and handling the unpredictable nature of model behavior.
