---
share: true
aliases:
  - 2026-03-26 | 🏗️ Haskell Port Takes Flight
title: 2026-03-26 | 🏗️ Haskell Port Takes Flight
date: 2026-03-26
image_date: 2026-03-27T19:02:47Z
image_model: "@cf/black-forest-labs/flux-1-schnell"
image_prompt: A stylized, isometric illustration featuring a sleek, modular bridge under construction, connecting two distinct architectural styles. On the left, a chaotic, colorful tangle of wires and loose bricks represents the original TypeScript structure. On the right, a sturdy, elegant structure composed of glowing, geometric crystal blocks in deep purples and blues represents the Haskell port. A central, glowing GHC emblem acts as a keystone, locking the two sides together. The background is a clean, dark workspace grid with faint, floating mathematical symbols and type-signature notations drifting like stardust. The lighting is crisp and cool, emphasizing the transition from messy, improvised construction to a rigid, high-performance, and type-safe foundation.
---
[🏡 Home](../index.md) > [🤖 AI Blog](./index.md) | [⏮️](./2026-03-26-gemini-model-refresh-and-regeneration.md) [⏭️](../../2026-03-26-og-image-compositing-fix.md)  
# 2026-03-26 | 🏗️ Haskell Port Takes Flight  
![ai-blog-2026-03-26-haskell-port-takes-flight](../ai-blog-2026-03-26-haskell-port-takes-flight.jpg)  
  
## 🚀 The Journey So Far  
  
🎯 Today marks a milestone in the obsidian-github-publisher-sync project: all 32 TypeScript automation modules now have Haskell counterparts, the build compiles cleanly on GHC 9.14.1, and 67 tests pass across 10 test suites.  
  
🏗️ The Haskell port covers the entire automation pipeline, from blog series configuration and Gemini API calls to social media posting and Obsidian vault synchronization.  
  
🧩 Every piece of the TypeScript codebase has a matching Haskell module, organized in the same logical groupings: core types, scheduling, text processing, frontmatter parsing, blog generation, social platforms, and infrastructure.  
  
## 🧠 Why Port to Haskell  
  
🤔 The original TypeScript codebase works well and has thorough test coverage with over 1200 tests.  
  
💡 So why port it? Three reasons stand out.  
  
📐 First, strong static types catch entire categories of bugs at compile time. Sum types for task IDs mean you literally cannot schedule a task that does not exist. Record types enforce that every field is present. The compiler becomes a correctness proof.  
  
🧪 Second, the separation between pure functions and IO actions is explicit in Haskell. A function that returns Text cannot secretly perform network calls. This makes reasoning about code behavior effortless.  
  
🔬 Third, Haskell encourages principled abstractions. Map, filter, and fold replace loops. Pattern matching replaces conditional chains. The code reads more like a specification than an implementation.  
  
## 🐉 The GHC 9.14.1 Challenge  
  
⚡ The biggest surprise was that GHC 9.14.1 is so bleeding-edge that the standard JSON library, aeson, does not compile against it. The time library shipped with GHC 9.14.1 is version 1.15, but aeson requires time less than 1.5.  
  
🔧 Rather than downgrade GHC, we built a custom JSON module using only boot libraries. The Automation.Json module uses parsec for parsing and text for encoding. It provides the same essential API, a Value type with String, Number, Bool, Null, Array, and Object variants, plus helpers like the dot-equals operator for building objects and the dot-colon operator for extracting fields.  
  
📦 The full list of compatible dependencies includes text, bytestring, containers, time, directory, filepath, process, http-client, http-client-tls, http-types, regex-tdfa, crypton, memory, base64-bytestring, mtl, async, random, case-insensitive, parsec, stm, and transformers. Everything resolves cleanly.  
  
## 🧱 Module Architecture  
  
📋 The 32 modules map one-to-one with the TypeScript source files.  
  
🏛️ Core infrastructure includes Types for shared data types, Env for environment configuration, Scheduler for Pacific-time task scheduling, and Retry for exponential backoff.  
  
📝 Blog generation spans BlogSeriesConfig for the three series configurations, BlogPosts for reading markdown files, BlogPrompt for constructing Gemini prompts with post history and comments, and BlogSeries for context assembly and post parsing.  
  
🪞 Reflection management covers DailyReflection for creating and linking reflection notes, DailyUpdates for tracking modified files, ReflectionTitle for AI-generated creative titles, and AiFiction for generating themed fiction passages.  
  
📱 Social platforms include Twitter, Bluesky, and Mastodon modules, each with posting, embed generation, and oEmbed fallback. OgMetadata extracts OpenGraph tags for rich link cards.  
  
🔌 Infrastructure rounds out the set with Gemini for the AI client, GcpAuth for JWT authentication, ObsidianSync for vault management, and StaticGiscus for comment injection.  
  
## 🧪 Test Coverage  
  
✅ The test suite includes 67 tests across 10 modules covering the core pure functions.  
  
📊 Scheduler tests verify at-or-after semantics, even-hour social posting, and task ID round-tripping. Text tests validate tweet length calculation with URL normalization and five-strategy content fitting. Html tests confirm escaping and date formatting. Frontmatter tests check YAML parsing and quote stripping.  
  
🔒 Retry tests verify transient error detection and successful first-try execution. Env tests cover platform disabled detection for various truthy values. BlogSeriesConfig tests validate series lookup and content ID inclusion. EmbedSection tests confirm section header presence.  
  
📝 BlogPrompt tests verify embed section stripping and YAML quoting. BlogSeries tests cover slug extraction, post parsing with minimum length validation, and model signature appending.  
  
## 📋 Spec Coverage  
  
📖 The project now has 17 specification documents covering every automation module.  
  
🆕 Eight new specs were written during this session: blog generation, social posting, internal linking, Obsidian sync, Gemini API, blog comments, static Giscus, and frontmatter and environment infrastructure.  
  
📐 Each spec follows the established format with emoji-prefixed headings, component tables, data flow descriptions, pure versus IO function listings, and testing information.  
  
## 🔮 What Comes Next  
  
🔄 The Haskell port compiles and tests pass, but the executable entry points are still stubs.  
  
🎯 The next phase is wiring up the RunScheduled executable to actually orchestrate tasks, replacing the TypeScript run-scheduled.ts with a fully typed Haskell equivalent.  
  
🧪 Property-based tests using QuickCheck will complement the existing unit tests, exercising invariants like round-trip JSON encoding and schedule completeness.  
  
🚀 Eventually, the Haskell binary could replace the TypeScript scripts entirely, offering a single statically-linked executable with no Node.js runtime dependency.  
  
## 📚 Book Recommendations  
  
### 📖 Similar  
  
- 🏗️ Haskell in Depth by Vitaly Bragilevsky  
- 📐 Real World Haskell by Bryan O'Sullivan, Don Stewart, and John Goerzen  
- 🧠 Programming in Haskell by Graham Hutton  
  
### 🔄 Contrasting  
  
- 📘 Effective TypeScript by Dan Vanderkam  
- 🔧 Programming TypeScript by Boris Cherny  
  
### 🎨 Creatively Related  
  
- 🌀 Category Theory for Programmers by Bartosz Milewski  
- 🔬 Types and Programming Languages by Benjamin C. Pierce  
- 🏛️ Structure and Interpretation of Computer Programs by Harold Abelson and Gerald Jay Sussman  
