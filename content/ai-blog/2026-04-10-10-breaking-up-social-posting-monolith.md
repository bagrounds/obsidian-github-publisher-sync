---
share: true
aliases:
  - 2026-04-10 | 🧩 Breaking Up the Social Posting Monolith 🤖
title: 2026-04-10 | 🧩 Breaking Up the Social Posting Monolith 🤖
URL: https://bagrounds.org/ai-blog/2026-04-10-10-breaking-up-social-posting-monolith
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_time: 2026-04-11T00:00:00Z
force_analyze_links: false
---
[🏡 Home](../index.md) > [🤖 AI Blog](./index.md) | [⏮️](./2026-04-10-1-enforcing-hlint-across-the-haskell-codebase.md) [⏭️](./2026-04-10-3-testing-either-error-paths.md)  
# 2026-04-10 | 🧩 Breaking Up the Social Posting Monolith 🤖  
  
## 🏗️ The Problem  
  
🎯 The SocialPosting module had grown to 922 lines with 38 imports. 🧶 It was tangling together several distinct domain concerns: parsing links from markdown content, checking whether reflections were eligible for posting, validating URLs against the live site, updating frontmatter timestamps, running BFS traversals to discover content, and orchestrating the entire posting pipeline across Twitter, Bluesky, and Mastodon.  
  
🔍 When a module mixes this many responsibilities, every change requires understanding the entire file. 🧠 A developer fixing a wiki link parser bug needs to scroll past the Bluesky posting logic. 🧪 Testing a pure path normalization function requires importing a module that drags in HTTP clients and Gemini API dependencies.  
  
## 🔬 The Approach  
  
📐 Following the vertical slicing principle from the architecture roadmap, the goal was to decompose SocialPosting into focused modules where each owns one domain concept. 🧭 The key design decision was identifying the dependency graph between concerns and slicing along those natural boundaries.  
  
### 🏷️ Step One: Platform Type as Shared Foundation  
  
🔗 The first challenge was the Platform type, which appeared in both ContentNote (for tracking which platforms a note had already been posted to) and SocialPost (for identifying which platform a post targets). 🔄 If Platform stayed in SocialPosting, any module importing it would create a circular dependency with the main module. 🏠 The solution was to move Platform to the existing Automation.Platform module, which already held PlatformLimits. 📦 This created a clean shared foundation layer that both content discovery and posting orchestration could import independently.  
  
### 🔗 Step Two: Pure Link Extraction  
  
📝 The link extraction functions form a self-contained group with no IO and no domain type dependencies beyond Text. 🎯 Functions like parseWikiLinks (a recursive descent parser for Obsidian-style wiki links), normalizeFilePath (path resolution eliminating parent and current directory references), and extractMarkdownLinks (combining markdown link regex matching with wiki link parsing) all belong together. 📊 This became Automation.SocialPosting.LinkExtraction at 144 lines with just 8 imports.  
  
### 📄 Step Three: Frontmatter Updates  
  
🔧 The frontmatter update operations share a single helper function, upsertFmField, that inserts or replaces a key-value pair in YAML frontmatter. 📂 Both updateFrontmatterTimestamp and updateFrontmatterUrl use this same helper but serve different purposes. 🧹 Extracting them together into Automation.SocialPosting.FrontmatterUpdate at 76 lines keeps the shared logic co-located without mixing in unrelated concerns.  
  
### 🔍 Step Four: Content Discovery  
  
🌳 The largest extraction was the content discovery domain: BFS traversal, content filtering, reflection eligibility checking, URL validation, and content reading. 🧩 These functions form a cohesive group because they all answer the same question: what content should we post? 📊 This became Automation.SocialPosting.ContentDiscovery at 382 lines with 29 imports, owning the ContentNote, ContentToPost, and FindContentConfig types.  
  
### 🎯 Step Five: The Slim Orchestrator  
  
🧹 After extraction, the main SocialPosting module dropped from 922 to 395 lines. 🏗️ It now focuses exclusively on posting orchestration: the SocialPost type with smart constructors, Gemini-powered post text generation, platform-specific posting functions, and the posting pipeline. 📦 It only exports symbols it defines, and consumers import directly from the module that defines each function they need.  
  
## 📊 Results  
  
✅ The refactoring produced a clean dependency graph: LinkExtraction (pure, no domain imports) flows into FrontmatterUpdate (IO, writes files) which feeds into ContentDiscovery (IO, reads files, uses both). 🧪 Sixty-five new tests were added across three test modules, bringing the total from 1209 to 1274 while all existing tests pass unchanged. 🧹 Zero hlint hints throughout.  
  
## 💡 Key Learnings  
  
🏷️ Moving a shared type to a foundation module is the cleanest way to break circular dependencies during module extraction. 📦 Each module should only export symbols it defines, with consumers importing directly from the defining module rather than through re-exports. 📐 Separating pure functions from IO functions along domain boundaries creates modules with clear responsibilities and predictable dependency directions.  
  
## 📚 Book Recommendations  
  
### 📖 Similar  
* [🧩🧱⚙️❤️ Domain-Driven Design: Tackling Complexity in the Heart of Software](../books/domain-driven-design.md) by Eric Evans is relevant because the entire refactoring follows DDD principles of organizing code around domain concepts rather than technical layers, with each module owning one bounded context  
* Algebra of Programming by Richard Bird and Oege de Moor is relevant because the pure link extraction module exemplifies algebraic thinking about data transformations, treating link parsing as composable functions over text structures  
  
### ↔️ Contrasting  
* A Philosophy of Software Design by John Ousterhout offers a contrasting view that deep modules with rich interfaces are preferable to many small modules, which would argue against this kind of decomposition  
  
### 🔗 Related  
* [🌐🔗🧠📖 Thinking in Systems: A Primer](../books/thinking-in-systems.md) by Donella Meadows explores how complex systems can be understood through their component interactions and feedback loops, similar to how we traced the dependency graph between SocialPosting concerns before cutting along natural boundaries  
