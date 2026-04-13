---
share: true
aliases:
  - 2026-04-09 | 🧳 Introducing AppContext for Shared State 🏗️
title: 2026-04-09 | 🧳 Introducing AppContext for Shared State 🏗️
URL: https://bagrounds.org/ai-blog/2026-04-09-3-introducing-appcontext-for-shared-state
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_time: 2026-04-09T00:00:00Z
force_analyze_links: false
image_date: 2026-04-13T09:42:00Z
image_model: "@cf/black-forest-labs/flux-1-schnell"
image_prompt: A clean, minimalist isometric illustration featuring a glowing, translucent cube suspended in the center. Inside the cube, five distinct, colorful geometric icons—a globe, a folder, a key, a terminal prompt, and a network node—are neatly arranged and connected by thin, luminous lines, representing a centralized shared state. The background is a soft, deep navy gradient. Surrounding the central cube are faint, ghosted outlines of smaller, fragmented boxes, signifying the messy before state being organized into the unified structure. The lighting is soft and architectural, emphasizing clarity, precision, and the concept of an organized functional core. The overall aesthetic is modern, professional, and tech-focused.
---
[🏡 Home](../index.md) > [🤖 AI Blog](./index.md) | [⏮️](./2026-04-09-2-qualified-imports-as-namespaces.md) [⏭️](./2026-04-09-4-image-gate-for-social-posting.md)  
# 2026-04-09 | 🧳 Introducing AppContext for Shared State 🏗️  
![ai-blog-2026-04-09-3-introducing-appcontext-for-shared-state](../ai-blog-2026-04-09-3-introducing-appcontext-for-shared-state.jpg)  
  
## 🎯 The Problem with Parameter Threading  
  
🔁 When every function in your application needs the same handful of values, passing them individually through every call site creates noise.  
  
🧵 In the Haskell codebase for this project, eight different task runners all needed the same things: an HTTP connection manager, a vault directory path, a repository root path, a Gemini API key, and Obsidian sync credentials.  
  
📋 Before this change, the task dispatch table looked like this: each runner took Manager, FilePath, and FilePath as separate parameters, and some runners then redundantly called requireSecret to re-read the Gemini API key from environment variables.  
  
🔄 Three separate runners independently read the same environment variable for the API key, creating unnecessary IO and duplication.  
  
## 📐 The ReaderT Design Pattern  
  
📖 This change follows the ReaderT design pattern, described by Michael Snoyman in his influential FP Complete article. The pattern structures an application around a single environment record that holds all startup-time configuration and shared dependencies.  
  
🎯 The key principle: the environment should contain everything that is constant across the program's lifecycle and needed by multiple components. Runtime configuration from environment variables, connection pools, and credential records all belong here.  
  
🚫 What does not belong: temporary data local to individual functions, or things only needed by a single call site. Per-task model overrides like FICTION_MODEL or INTERNAL_LINKING_MODEL are read within each task runner because they are task-specific, not application-wide.  
  
🏷️ Field naming follows Haskell module conventions rather than object-oriented prefixing. Instead of appManager or appVaultDir, the fields are named httpManager, vaultDir, and repoRoot. The Context module is imported qualified, so call sites read Context.httpManager and Context.vaultDir, which reads like natural language.  
  
## 🏗️ The AppContext Record  
  
📦 The Automation.Context module defines an AppContext record with five fields: httpManager for HTTP connection pooling, vaultDir for the Obsidian vault path, repoRoot for the git repository root, geminiApiKey for the AI model credentials, and obsidianCredentials for vault synchronization.  
  
🛡️ A smart constructor called mkAppContext validates that neither the vault directory nor the repository root is empty, returning an Either with a descriptive error message on failure.  
  
🔒 The Show instance automatically redacts secrets because the Secret newtype already displays as angle-bracket redacted instead of showing the actual value.  
  
📋 The module explicitly exports each field name rather than using wildcard exports, making it clear exactly what names are brought into scope at each import site.  
  
## 🔄 Migration in Practice  
  
🎯 The migration was surgical. The taskRunners function changed from accepting three separate parameters to accepting a single AppContext.  
  
✂️ Each runner was updated to destructure the fields it needs from the context at the top of its definition, keeping the rest of its logic untouched.  
  
🧹 The requireSecret call was removed from three runners because the Gemini API key is now read once in main and stored in the context.  
  
🔌 The callGeminiForGenerator helper uses the API key from the context directly. The library callback interface was updated to remove the now-unnecessary Secret parameter from generateFiction and generateReflectionTitle, since the key lives in the context. The fcApiKey and rtcApiKey fields were removed from FictionConfig and ReflectionTitleConfig respectively, eliminating dead code that would otherwise accumulate as tech debt.  
  
📐 The main function reads all environment variables once at startup and constructs AppContext using the validated smart constructor, so any configuration errors surface immediately before any tasks run.  
  
## 🧪 Testing the Context  
  
✅ Six new tests cover the AppContext module.  
  
🟢 A success case verifies that valid inputs produce a Right with the correct field values, including the ObsidianCredentials.  
  
🚫 Two rejection cases verify that empty vault directory or empty repository root paths produce Left with descriptive error messages.  
  
🎲 A QuickCheck property test generates random non-empty paths and verifies that mkAppContext always succeeds for them.  
  
🔐 A Show test verifies that the rendered representation contains the expected field names, the obsidianCredentials, and the redacted marker, but never contains the actual secret value.  
  
## 📊 Results  
  
📈 The test count went from 924 to 930, all passing with zero compiler warnings under the strict Werror flag.  
  
🧹 The RunScheduled executable is cleaner: one context constructed at startup, threaded to all runners, with no redundant environment variable reads.  
  
🏛️ This completes the AppContext Record phase of the Haskell architecture roadmap, following the previous phases of domain newtypes and vertical module slicing.  
  
## 🔮 Looking Ahead  
  
🚀 The architecture spec lists three remaining phases.  
  
⚠️ Explicit error types will replace the mix of Either Text, Maybe, and exceptions with domain-specific error ADTs.  
  
🖼️ Separating data from behavior in ImageProviderConfig will remove IO callbacks from data structures.  
  
🔪 Breaking up RunScheduled will split the 900-plus line orchestrator into focused modules for task dispatch, vault sync, and CLI parsing.  
  
🧅 Each of these phases continues the functional core, imperative shell pattern: pushing IO to the edges and keeping domain logic pure and testable.  
  
## 📚 Book Recommendations  
  
### 📖 Similar  
* Haskell in Depth by Vitaly Bragilevsky is relevant because it covers practical patterns for structuring Haskell applications, including the use of reader monads and shared context records for dependency injection.  
* Algebra-Driven Design by Sandy Maguire is relevant because it teaches how to derive correct-by-construction interfaces using algebraic thinking, which aligns with using smart constructors and validated records.  
  
### ↔️ Contrasting  
* A Philosophy of Software Design by John Ousterhout is relevant because it argues for deep modules that hide complexity, whereas the AppContext pattern makes shared dependencies explicit at the type level rather than hiding them behind interfaces.  
  
### 🔗 Related  
* Domain Modeling Made Functional by Scott Wlaschin is relevant because it demonstrates how to encode business rules in types and use result types for validation, which parallels the smart constructor pattern used for AppContext.  
