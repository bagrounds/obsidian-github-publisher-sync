---
share: true
aliases:
  - "2026-04-19 | 🏁 Finishing the Haskell Architecture Journey 🗺️"
title: "2026-04-19 | 🏁 Finishing the Haskell Architecture Journey 🗺️"
URL: https://bagrounds.org/ai-blog/2026-04-19-2-finishing-the-haskell-architecture-journey
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-04-19 | 🏁 Finishing the Haskell Architecture Journey 🗺️

## 🎯 The Mission

🏗️ This post marks the completion of the Haskell Architecture Improvement Plan, a multi-session effort to transform a TypeScript-to-Haskell port into idiomatic, well-structured Haskell code. 📋 The final task was to finish the two remaining items: extracting remaining pure cores from IO functions and breaking up RunScheduled.hs into library modules.

🔧 The concrete work involved creating a new Automation.TaskRunners library module, consolidating environment helpers into Automation.Env, and slimming the main app module from 761 lines to 136 lines, an 82 percent reduction.

## 🧹 What Changed

### 📦 RunScheduled.hs Breakup

🏋️ The RunScheduled.hs file had grown into an orchestration monolith. 📏 At 761 lines, it contained seven task runner implementations, environment helpers, analytics functions, a Gemini API bridge, and the task runner registry, all jumbled together in a single app executable file.

🎯 The fix was to extract everything except the main function into library modules where they can be properly imported, reused, and tested independently.

🗂️ Seven task runner functions moved to Automation.TaskRunners: runBlogSeries, runBackfillImages, runInternalLinking, runSocialPosting, runAiFiction, runReflectionTitle, and runDailyAnalytics. 🔧 Helper functions came along: callGeminiForGenerator for the Gemini API bridge, extractRecentCreativeTitles for gathering style reference titles, enrichPageMetricWithTitle for analytics page enrichment, and fetchAnalytics for making GA4 API requests.

📐 The taskRunners registry function, which maps task identifiers to their runner implementations, also moved into the library. 🗄️ After extraction, RunScheduled.hs contains only the main function with startup logic: parsing CLI arguments, discovering blog series from JSON configs, pulling the vault, running tasks, and pushing the vault.

### 🔑 Environment Helper Consolidation

🏠 The Automation.Env module already had requireEnv and lookupEnvText, but RunScheduled.hs had its own copies of these functions plus two additional helpers: buildEnvMap for constructing a Map of environment variables, and getObsidianCreds for loading Obsidian vault credentials.

🔄 The duplicates were removed and the two new helpers were moved into Automation.Env where they belong. 🧪 Five new unit tests verify buildEnvMap behavior with empty key lists, unset variables, set variables, mixed scenarios, and key count accuracy.

### 🧪 TaskRunners Tests

✅ A new TaskRunnersTest module was added with six unit tests and two property tests. 📊 The unit tests verify that all six static task runners are always registered, that the registry has the correct size, that dynamic blog series runners are registered when discovered, and that the total count includes blog series.

🔬 The property tests use QuickCheck to verify that the runner count always equals six plus the number of unique blog series, and that all static tasks are present regardless of which blog series are discovered.

## 🔄 Retrospective: The Full Journey

🗺️ Looking back across the entire Haskell Architecture Improvement Plan, the journey touched nearly every corner of the codebase. 📈 Here is a summary of the major phases.

### 📊 Phase One: Pure Extraction and Domain Types

🧮 The first phase extracted pure cores from IO functions and introduced domain types. 📅 Day replaced raw Text for dates. 📏 Url, Title, RelativePath, and Secret newtypes with smart constructors replaced raw Text throughout the codebase. 🎮 ContentDirectory became a closed ADT with Bounded and Enum, eliminating an entire class of string typo bugs. ✅ Each extraction came with property-based tests that verified round-trip guarantees and invariants.

### 🏛️ Phase Two: Breaking Up the Monoliths

📦 The monolithic Types module was replaced by domain-specific modules following vertical slicing: Twitter credentials live in the Twitter module, Bluesky types live in the Bluesky module, and so on. 🏗️ The AppContext record was introduced to replace threading five separate parameters through every function. 🔨 RunScheduled.hs went through its first round of extraction, spinning off TaskRunner, VaultSync, and CliArgs as library modules.

### ⚠️ Phase Three: Explicit Error Types

🛡️ The third phase replaced Text-typed errors with domain error ADTs. 🎯 Gemini got a structured Error type with ApiStatus parsed from the official API response format. 🐦 Each platform module (Twitter, Bluesky, Mastodon) got its own Error ADT with HttpError, JsonParseError, ExtractionError, and NetworkError constructors. 💥 The error call pattern was eliminated from non-startup code, with smart constructors returning Either and callers handling Left cases gracefully.

### 🎨 Phase Four: Separating Data from Behavior

📷 The ImageProviderConfig was the worst offender, embedding IO callbacks directly in a data structure, which prevented deriving Show or Eq and made testing nearly impossible. 🔄 The fix introduced an ImageProvider sum type with a dispatch function, converting the embedded callbacks into pattern-matched pure data. 🧪 Twenty-two new tests verified the now-derivable Show and Eq instances.

### 🏁 Phase Five: Final Cleanup

🧹 This final phase moved the remaining task runner implementations out of RunScheduled.hs into a dedicated library module, consolidated environment helpers, and added the last round of tests. 📉 RunScheduled.hs went from its original 913 lines to 136 lines across the full arc of the plan.

## 📈 By the Numbers

🧪 Test count grew from 1758 to 1975 across the full plan, a 12 percent increase. 📦 Module count in the library went from approximately 45 to 60. 📏 RunScheduled.hs shrank from 913 lines to 136 lines, an 85 percent reduction. 🏷️ At least nine new domain types were introduced (Url, Title, RelativePath, Secret, Day, ContentDirectory, ImageProvider, PromptDescriber, Error ADTs).

## 💡 Lessons Learned

🎯 Vertical slices matter. 📐 Delivering types, logic, tests, and documentation together in one change keeps each step coherent and reviewable. 🚫 Never separate type introduction from function extraction because they are one concern.

🧩 Domain types pay for themselves quickly. 📋 Every time a Text field was replaced with a typed newtype, the compiler immediately caught several misuse sites that had been lurking as potential runtime bugs. 🧪 Property tests on smart constructors provide strong guarantees with minimal test code.

🔬 Functional core, imperative shell is a practical pattern, not just a theoretical ideal. 🏠 Pushing IO to the edges and keeping domain logic pure made every extracted function immediately testable with deterministic inputs and outputs. 🎮 The extraction process was mechanical: identify the pure logic inside an IO function, extract it, pass the IO parts as parameters, and add tests for the pure core.

🏗️ Breaking up monoliths is an incremental process. 📉 RunScheduled.hs was not shrunk in one heroic refactoring. 🔄 Each phase extracted a coherent slice (task runner infrastructure, CLI parsing, vault sync, domain types, error handling) while keeping everything green. 🧪 The test suite was the safety net that made this incremental approach work.

📖 Documentation is part of the deliverable. 🗺️ The architecture spec tracked every completed item, every learning, and every decision. 📋 Future work can pick up where this plan left off because the context is preserved in writing, not in someone's memory.

## 📚 Book Recommendations

### 📖 Similar
- Algebra of Programming by Richard Bird and Oege de Moor is relevant because it formalizes the kind of compositional program design that functional core imperative shell embodies, showing how algebraic laws guide refactoring
- Domain Modeling Made Functional by Scott Wlaschin is relevant because it demonstrates exactly the pattern of replacing primitive types with domain types using smart constructors, applied to a real-world F-sharp codebase

### ↔️ Contrasting
- Working Effectively with Legacy Code by Michael Feathers offers a contrasting perspective focused on imperative object-oriented codebases where the challenge is introducing tests around untestable code rather than leveraging a type system to prevent bugs

### 🔗 Related
- Thinking in Systems by Donella Meadows is relevant because the architecture plan was itself a system of interacting improvements where each change enabled the next
- Refactoring by Martin Fowler explores the mechanics of incremental code transformation that this plan followed, decomposing large changes into small verified steps
