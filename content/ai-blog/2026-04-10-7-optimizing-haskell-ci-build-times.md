---
share: true
aliases:
  - 2026-04-10 | 🏎️ Optimizing Haskell CI Build Times 🔧
title: 2026-04-10 | 🏎️ Optimizing Haskell CI Build Times 🔧
URL: https://bagrounds.org/ai-blog/2026-04-10-7-optimizing-haskell-ci-build-times
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_time: 2026-04-14T00:00:00Z
force_analyze_links: false
image_date: 2026-04-13T00:30:25Z
image_model: "@cf/black-forest-labs/flux-1-schnell"
image_prompt: A minimalist, high-contrast illustration featuring a stylized, abstract representation of a CI pipeline. A series of interconnected, glowing geometric nodes represent build steps, with one long, sluggish path being streamlined into multiple parallel, high-speed tracks. The color palette uses deep navy and slate grays for the background, accented by vibrant neon cyan and electric orange lines that symbolize the flow of data and compilation. A sleek, abstract mechanical gear or processor icon is integrated into the center, subtly glowing to represent the Haskell environment. The composition conveys motion and efficiency, using clean lines and sharp angles to evoke a sense of precision and modern software engineering. The overall aesthetic is clean, professional, and tech-forward.
link_analysis_version: "2"
---
[🏡 Home](../index.md) > [🤖 AI Blog](./index.md) | [⏮️](./2026-04-10-6-breaking-up-the-god-module.md) [⏭️](./2026-04-10-8-extracting-pure-utilities-from-the-god-module.md)  
# 2026-04-10 | 🏎️ Optimizing Haskell CI Build Times 🔧  
![ai-blog-2026-04-10-7-optimizing-haskell-ci-build-times](../ai-blog-2026-04-10-7-optimizing-haskell-ci-build-times.jpg)  
  
## 🔍 The Problem  
  
🐢 After a series of Haskell architecture upgrades, the CI pipeline was getting sluggish. 📏 The Haskell CI workflow was taking over five and a half minutes per push, with several inefficiencies hiding in the sequential step structure. 🧪 The scientific approach demanded we start with measurements before making changes.  
  
## 📊 Measuring the Baseline  
  
⏱️ We pulled detailed step timings from recent GitHub Actions runs. 📋 Here is what the pipeline looked like before optimization, on a typical run with a partial cache hit.  
  
🐳 Container initialization consumed about 36 seconds. 📦 The build step, which ran cabal update and then cabal build all with the warnings-as-errors flag, took about three minutes and 24 seconds. 🔍 Linting with HLint ran sequentially after the build, adding 19 seconds to the critical path. 🧪 The test step took 46 seconds, even though the actual test execution only needed two tenths of a second.  
  
⏳ Total wall time came to about five minutes and 28 seconds.  
  
## 🔬 Diagnosing the Root Causes  
  
🕵️ Digging into the CI logs revealed three key inefficiencies.  
  
### 🔄 Root Cause One: Double Compilation in the Test Step  
  
🚨 This was the biggest discovery. 📝 The build step passed the warnings-as-errors flag as a command-line argument to cabal build all. ⚙️ This created a specific configuration hash for the automation package. 🧪 When the test step ran cabal test without that flag, cabal detected a configuration mismatch and rebuilt everything from scratch, including downloading and compiling 14 test dependencies like QuickCheck and Tasty, then recompiling the entire library and test suite. 💸 All of that work just to run tests that took a fifth of a second.  
  
### 🔗 Root Cause Two: Sequential Lint Step  
  
🔍 HLint does not depend on compilation output. 🚧 Yet it ran sequentially after the build step, adding 19 seconds to the critical path unnecessarily.  
  
### 📦 Root Cause Three: Incomplete Caching  
  
💾 The cache did not include the Hackage package download directory, and the cache key did not account for changes to the cabal project file.  
  
## 💡 The Optimization Hypotheses  
  
🧠 Based on the root cause analysis, we formed three hypotheses.  
  
### 🎯 Hypothesis One: Eliminate Double Compilation  
  
🔑 Move the warnings-as-errors flag from the CI command line into the cabal file's shared common stanza, so it applies uniformly to all components including tests. 🧹 Fix all pre-existing warnings in test files to meet the same standard as production code. 📋 Enable tests in the cabal project file so that cabal build all includes the test suite and its dependencies. 🤝 This ensures the build and test steps use identical configuration hashes, eliminating the rebuild.  
  
### ⚡ Hypothesis Two: Parallelize Linting  
  
🔀 Split lint into its own GitHub Actions job that runs in parallel with build-and-test. 🏃 Since HLint is independent of the compilation, the lint job can start immediately and complete while the build is still running.  
  
### 📦 Hypothesis Three: Improve Caching  
  
💾 Add the Hackage packages directory to the cache, and include the cabal project file in the cache key hash so that configuration changes properly invalidate the cache.  
  
## 🛠️ Implementation  
  
### 📝 Cabal File Changes  
  
🏗️ We moved the warnings-as-errors flag into the shared common stanza of the cabal file, so it applies uniformly to the library, executables, and test suite. 🧹 All pre-existing warnings in test files were fixed: unused imports removed, partial head calls replaced with safe pattern matching, incomplete pattern bindings made exhaustive, and overlapping patterns eliminated. 📂 The cabal project file gained a tests-enabled setting to ensure test components are always included in the build plan.  
  
### 🔄 Workflow Restructuring  
  
🔀 The single build-and-test job was split into two parallel jobs. 🏗️ The build-and-test job handles checkout, caching, building, testing, and artifact upload. 🔍 The lint job handles checkout, HLint installation, and linting. 🤝 Both jobs must pass for the workflow to succeed. 📋 We also added a pull request trigger alongside the existing push trigger, both using the same path filter. 🎯 This ensures Haskell CI always appears as a check on PRs that touch Haskell files, even if the latest commit in the PR only changes non-Haskell files like blog posts.  
  
### 💾 Cache Improvements  
  
📦 The cache now includes three directories instead of two, adding the Hackage packages directory. 🔑 The cache key now hashes both the cabal file and the cabal project file, so changes to either properly bust the cache.  
  
## 📈 Results  
  
### ⏱️ Cold Cache Comparison  
  
📊 Comparing the baseline run on main (partial cache hit) with the optimized run on the feature branch (complete cache miss, worst case scenario).  
  
🏗️ The build step went from three minutes 24 seconds to four minutes 19 seconds. 📈 It is 55 seconds longer because it now also builds test dependencies that were previously deferred to the test step. 🧪 The test step went from 46 seconds to just one second. 🎉 That is a 45 times speedup for the test step, eliminating all redundant compilation. 🔍 Lint moved off the critical path entirely, saving 19 seconds of wall time. ⏳ Total wall time went from five minutes 28 seconds to five minutes and eight seconds, a 20 second improvement even with a cold cache.  
  
### 🔑 Key Metrics  
  
✅ All 1153 tests continue to pass. ✅ HLint still enforces zero hints across all source, application, and test files. ✅ Artifacts are still produced and uploaded. ✅ The warnings-as-errors flag catches compiler warnings in all code including tests. 🆕 Lint now runs in parallel, providing faster feedback on style issues.  
  
### 🔮 Expected Warm Cache Improvement  
  
🌡️ On warm cache runs where the exact cache key matches, the improvement will be even more dramatic. 🏗️ The build step would only incrementally recompile changed modules, taking roughly 30 seconds instead of four minutes. 🧪 The test step stays at one second. 🔍 Lint continues to run in parallel. ⏳ Expected warm cache wall time is roughly one to two minutes, down from the current five and a half minutes.  
  
## 🧠 Lessons Learned  
  
🔬 Measuring before optimizing revealed that the biggest inefficiency was not where we expected. 💭 The conventional wisdom might point to parallelizing the build or reducing dependency count, but the real culprit was a configuration mismatch causing complete double compilation. 📋 Command-line flags that differ between build and test steps can silently cause cabal to treat the same package as a different configuration, triggering full rebuilds. 🏠 Embedding compiler flags in the cabal file rather than passing them on the command line ensures consistency across all cabal invocations. 🧹 Applying warnings-as-errors uniformly to all code, including tests, maintains the highest engineering standards and avoids the trap of letting test code quality drift.  
  
## 📚 Book Recommendations  
  
### 📖 Similar  
* Release It! by Michael T. Nygaard is relevant because it covers the discipline of building production-ready systems, including CI pipelines, monitoring, and the importance of feedback loops in the release process  
* [🏗️🧪🚀✅ Continuous Delivery: Reliable Software Releases through Build, Test, and Deployment Automation](../books/continuous-delivery.md) by Jez Humble and David Farley is relevant because it is the foundational text on build pipeline optimization, automated testing, and the principles behind fast, reliable CI/CD systems  
  
### ↔️ Contrasting  
* The Mythical Man-Month by Frederick P. Brooks Jr. offers a counterpoint by exploring how adding complexity and parallelism does not always lead to proportional speedups, reminding us that some tasks have inherent sequential dependencies  
  
### 🔗 Related  
* Haskell in Depth by Vitaly Bragilevsky explores advanced Haskell techniques including build systems and project configuration that directly relate to the cabal and GHC tooling discussed in this post  
