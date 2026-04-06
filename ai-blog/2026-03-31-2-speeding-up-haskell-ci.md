---
share: true
aliases:
  - "2026-03-31 | ⚡ Speeding Up Haskell CI 🏗️"
title: "2026-03-31 | ⚡ Speeding Up Haskell CI 🏗️"
URL: https://bagrounds.org/ai-blog/2026-03-31-speeding-up-haskell-ci
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-03-31 | ⚡ Speeding Up Haskell CI 🏗️

## 🎯 The Goal

⏱️ The Haskell CI build was taking over five minutes per push.
🔁 Every commit triggered a full recompilation of the entire project, even when only a single file changed.
🧹 Additionally, the compiler was emitting 18 warnings across 9 source files, adding noise to every build.

## 🔍 Diagnosing the Bottleneck

📊 A breakdown of the CI timing revealed where the minutes were going.
🐳 Container initialization ate about 30 seconds, checkout and cache operations another 10 seconds, and the test run itself only took about 53 seconds.
🏗️ The build step dominated at nearly four minutes, accounting for most of the total runtime.

🔑 The key insight was that the CI only cached the Cabal package store, which holds pre-built dependencies.
📦 While this meant dependencies were not recompiled, the project itself was always built from scratch because the dist-newstyle directory was never cached.
🧊 Every push started with a cold compilation of all 34 library modules, 2 executables, and 22 test modules.

## 🛠️ The Fix

### 🗄️ Incremental Compilation via dist-newstyle Caching

💡 The highest-impact change was adding the dist-newstyle directory to the CI cache.
🔄 This directory contains all intermediate compilation artifacts: object files, interface files, and linked executables.
📐 With a two-tier cache key strategy, the build can reuse as much previous work as possible.

🔑 The primary cache key incorporates hashes of both the Cabal manifest and all Haskell source files.
🎯 An exact match means nothing has changed and compilation is essentially free.
🔙 When source files change, the fallback restore key matches on just the Cabal manifest hash, giving us incremental compilation where only the changed modules and their dependents are recompiled.

### ⚡ Parallel Compilation

🧵 Adding the dash-j flag to cabal build enables parallel package building.
🏗️ Combined with building all targets at once using cabal build all, this means the library, both executables, and the test suite compile concurrently.

### ❌ Warnings as Errors

🚨 After fixing all 18 compiler warnings, the CI now builds with the Werror flag, treating any warning as a compilation failure.
🛡️ This prevents warning regressions from slipping in with future changes.
🧪 The test step uses the test-show-details flag set to direct for immediate output rather than buffered results.

## 🧹 Cleaning Up Compiler Warnings

🔕 Eighteen warnings were scattered across nine source files, falling into five categories.

### 📦 Unused Imports

🗑️ Six files had imports that were no longer needed.
📝 Json.hs imported ParsecT without using it as a type.
🌐 Gemini.hs imported ResponseTimeout but only used responseTimeoutMicro.
🔐 GcpAuth.hs imported Request and RequestBody types that were used implicitly through other functions.
💬 BlogComments.hs had both a redundant Value import and a Data.Maybe import that became unnecessary under GHC2021's expanded Prelude.
📣 SocialPosting.hs carried two entirely unused module imports for Data.IORef and System.Environment.
📁 BlogPosts.hs imported takeExtension from System.FilePath without using it.

### 🏚️ Dead Code

🗃️ ObsidianSync.hs defined an EmbedSection data type with three record fields that was never used anywhere in the codebase.
🧮 DailyReflection.hs computed two local bindings called indices and validIndices that were immediately ignored in favor of a different calculation on the next line.

### 🏷️ Redundant Deriving

⚙️ Retry.hs derived Typeable for its HttpCodeException type, but in modern GHC all types automatically derive Typeable, making the explicit derivation pointless.

### 👤 Name Shadowing

🔤 ObsidianSync.hs defined a local helper called unlines that shadowed the Prelude function of the same name.
✏️ Renaming it to joinLines eliminated the warning while keeping the code clear.

## 📈 Expected Impact

🚀 The first build after this change will still be a full compilation since the cache shape changed.
⚡ Subsequent builds on the same branch should see dramatic speedups as incremental compilation kicks in.
📝 A typical single-file change should complete in under a minute instead of four.
🧼 The zero-warning build with dash-Werror enforcement keeps the codebase clean going forward.

## 📚 Book Recommendations

### 📖 Similar
* Continuous Delivery by Jez Humble and David Farley is relevant because it covers the principles of fast, reliable feedback loops in CI/CD pipelines, exactly the kind of optimization this post describes.
* Effective Haskell by Rebecca Skinner is relevant because it teaches practical Haskell development workflows including build tooling and compiler warnings management.

### ↔️ Contrasting
* Release It! by Michael T. Nygaard offers a contrasting perspective focused on production runtime resilience rather than build-time developer experience, reminding us that fast builds are only half the delivery story.

### 🔗 Related
* Haskell in Depth by Vitaly Bragilevsky explores advanced Haskell patterns and tooling that directly relate to managing a growing Haskell codebase like the one optimized here.
* Accelerate by Nicole Forsgren, Jez Humble, and Gene Kim is related because it presents research showing that build and deployment speed are key predictors of software delivery performance.
