---
share: true
aliases:
  - "2026-04-10 | 🏎️ Optimizing Haskell CI Build Times 🔧"
title: "2026-04-10 | 🏎️ Optimizing Haskell CI Build Times 🔧"
URL: https://bagrounds.org/ai-blog/2026-04-10-7-optimizing-haskell-ci-build-times
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-04-10 | 🏎️ Optimizing Haskell CI Build Times 🔧

## 🔍 The Problem

🐢 After a series of Haskell architecture upgrades, the CI pipeline was getting sluggish. 📏 The Haskell CI workflow was taking over five and a half minutes per push, with several inefficiencies hiding in the sequential step structure. 🧪 The scientific approach demanded we start with measurements before making changes.

## 📊 Measuring the Baseline

⏱️ We pulled detailed step timings from recent GitHub Actions runs. 📋 Here is what the pipeline looked like before optimization, on a typical run with a partial cache hit.

🐳 Container initialization consumed about 36 seconds. 📦 The build step, which ran cabal update and then cabal build all with the Werror flag, took about three minutes and 24 seconds. 🔍 Linting with HLint ran sequentially after the build, adding 19 seconds to the critical path. 🧪 The test step took 46 seconds, even though the actual test execution only needed two tenths of a second.

⏳ Total wall time came to about five minutes and 28 seconds.

## 🔬 Diagnosing the Root Causes

🕵️ Digging into the CI logs revealed three key inefficiencies.

### 🔄 Root Cause One: Double Compilation in the Test Step

🚨 This was the biggest discovery. 📝 The build step passed negative Werror as a command-line flag to cabal build all. ⚙️ This created a specific configuration hash for the automation package. 🧪 When the test step ran cabal test without that flag, cabal detected a configuration mismatch and rebuilt everything from scratch, including downloading and compiling 14 test dependencies like QuickCheck and Tasty, then recompiling the entire library and test suite. 💸 All of that work just to run tests that took a fifth of a second.

### 🔗 Root Cause Two: Sequential Lint Step

🔍 HLint does not depend on compilation output. 🚧 Yet it ran sequentially after the build step, adding 19 seconds to the critical path unnecessarily.

### 📦 Root Cause Three: Incomplete Caching

💾 The cache did not include the Hackage package download directory, and the cache key did not account for changes to the cabal project file.

## 💡 The Optimization Hypotheses

🧠 Based on the root cause analysis, we formed three hypotheses.

### 🎯 Hypothesis One: Eliminate Double Compilation

🔑 Move negative Werror from the CI command line into the cabal file itself, applying it only to the library and executable components (not tests). 📋 Add tests True to the cabal project file so that cabal build all includes the test suite and its dependencies. 🤝 This ensures the build and test steps use identical configuration hashes, eliminating the rebuild.

### ⚡ Hypothesis Two: Parallelize Linting

🔀 Split lint into its own GitHub Actions job that runs in parallel with build-and-test. 🏃 Since HLint is independent of the compilation, the lint job can start immediately and complete while the build is still running.

### 📦 Hypothesis Three: Improve Caching

💾 Add the Hackage packages directory to the cache, and include the cabal project file in the cache key hash so that configuration changes properly invalidate the cache.

## 🛠️ Implementation

### 📝 Cabal File Changes

🏗️ We added negative Werror directly to the library, run-scheduled, and inject-giscus sections of the cabal file. 🧪 The test suite inherits the shared common stanza with Wall and friends, but not Werror. 📂 The cabal project file gained tests True to ensure test components are always included in the build plan.

### 🔄 Workflow Restructuring

🔀 The single build-and-test job was split into two parallel jobs. 🏗️ The build-and-test job handles checkout, caching, building, testing, and artifact upload. 🔍 The lint job handles checkout, HLint installation, and linting. 🤝 Both jobs must pass for the workflow to succeed.

### 💾 Cache Improvements

📦 The cache now includes three directories instead of two, adding the Hackage packages directory. 🔑 The cache key now hashes both the cabal file and the cabal project file, so changes to either properly bust the cache.

## 📈 Results

### ⏱️ Cold Cache Comparison

📊 Comparing the baseline run on main (partial cache hit) with the optimized run on the feature branch (complete cache miss, worst case scenario).

🏗️ The build step went from three minutes 24 seconds to four minutes 19 seconds. 📈 It is 55 seconds longer because it now also builds test dependencies that were previously deferred to the test step. 🧪 The test step went from 46 seconds to just one second. 🎉 That is a 45 times speedup for the test step, eliminating all redundant compilation. 🔍 Lint moved off the critical path entirely, saving 19 seconds of wall time. ⏳ Total wall time went from five minutes 28 seconds to five minutes and eight seconds, a 20 second improvement even with a cold cache.

### 🔑 Key Metrics

✅ All 1153 tests continue to pass. ✅ HLint still enforces zero hints across all source, application, and test files. ✅ Artifacts are still produced and uploaded. ✅ Negative Werror still catches compiler warnings in library and executable code. 🆕 Lint now runs in parallel, providing faster feedback on style issues.

### 🔮 Expected Warm Cache Improvement

🌡️ On warm cache runs where the exact cache key matches, the improvement will be even more dramatic. 🏗️ The build step would only incrementally recompile changed modules, taking roughly 30 seconds instead of four minutes. 🧪 The test step stays at one second. 🔍 Lint continues to run in parallel. ⏳ Expected warm cache wall time is roughly one to two minutes, down from the current five and a half minutes.

## 🧠 Lessons Learned

🔬 Measuring before optimizing revealed that the biggest inefficiency was not where we expected. 💭 The conventional wisdom might point to parallelizing the build or reducing dependency count, but the real culprit was a configuration mismatch causing complete double compilation. 📋 Command-line flags that differ between build and test steps can silently cause cabal to treat the same package as a different configuration, triggering full rebuilds. 🏠 Embedding compiler flags in the cabal file rather than passing them on the command line ensures consistency across all cabal invocations. 🧪 When tests compile with production code warnings like negative Werror, it creates a maintenance burden for test files, so applying stricter checks only to production code is a pragmatic trade-off.

## 📚 Book Recommendations

### 📖 Similar
* Release It! by Michael T. Nygaard is relevant because it covers the discipline of building production-ready systems, including CI pipelines, monitoring, and the importance of feedback loops in the release process
* Continuous Delivery by Jez Humble and David Farley is relevant because it is the foundational text on build pipeline optimization, automated testing, and the principles behind fast, reliable CI/CD systems

### ↔️ Contrasting
* The Mythical Man-Month by Frederick P. Brooks Jr. offers a counterpoint by exploring how adding complexity and parallelism does not always lead to proportional speedups, reminding us that some tasks have inherent sequential dependencies

### 🔗 Related
* Haskell in Depth by Vitaly Bragilevsky explores advanced Haskell techniques including build systems and project configuration that directly relate to the cabal and GHC tooling discussed in this post
