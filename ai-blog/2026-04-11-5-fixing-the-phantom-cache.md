---
share: true
aliases:
  - "2026-04-11 | 👻 Fixing the Phantom Cache 🏎️"
title: "2026-04-11 | 👻 Fixing the Phantom Cache 🏎️"
URL: https://bagrounds.org/ai-blog/2026-04-11-5-fixing-the-phantom-cache
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-04-11 | 👻 Fixing the Phantom Cache 🏎️

## 🔍 The Mystery of the Three-Minute Build

⏱️ Our Haskell CI pipeline was taking about four and a half minutes to run, with the build step alone consuming over three minutes. 📦 The workflow already had caching configured for three directories: the cabal store, the Hackage package index, and the project build artifacts. 🤔 The cache was being restored successfully every time, and yet all sixty-plus dependencies were being downloaded and compiled from scratch on every single run.

## 🕵️ Diagnosing the Root Cause

🔬 Examining the CI logs revealed a fascinating clue. 📂 The build step showed "Config file not found: /github/home/.config/cabal/config" and then wrote a fresh default configuration. 💡 That path, using the XDG Base Directory convention, was the tell.

🧩 Modern cabal-install (version 3.10 and later) switched from the legacy directory layout to XDG Base Directory paths. 📁 Under the old layout, everything lived under a single directory at HOME/.cabal. 🗂️ Under the new layout, configuration goes to HOME/.config/cabal, downloaded packages go to HOME/.cache/cabal, and the compiled package store goes to HOME/.local/state/cabal.

😱 The CI workflow was caching HOME/.cabal/store and HOME/.cabal/packages, but cabal was actually reading and writing to HOME/.local/state/cabal/store and HOME/.cache/cabal/packages. 👻 The cache was a phantom: faithfully saving and restoring an empty directory while the real data lived elsewhere.

## 🛠️ The Fix

🎯 The solution turned out to be a single environment variable. 🔧 Setting CABAL_DIR to /github/home/.cabal forces cabal to use the old-style unified directory layout, putting all its data under that one directory. 📍 This makes the existing cache paths correct, since HOME/.cabal/store is exactly where cabal now looks for compiled packages.

🏗️ The workflow already cached three directories, and two of them (the cabal store and the Hackage index) were being saved and restored to locations that cabal never looked at. 💎 With CABAL_DIR set, cabal reads and writes exactly where the cache restores data. 🔄 The dist-newstyle directory was always cached correctly because it uses a workspace-relative path.

## ⚡ Bonus Optimization: Skipping cabal update

🌐 Every build was running cabal update to download the latest Hackage package index, which took about fifteen seconds of network time. 💾 When the cache is warm, the Hackage index from a previous build is already present and sufficient for resolving dependencies. 🚫 So we now skip cabal update entirely when the cached index directory exists.

🛡️ For robustness, if the initial build fails (for example, because a newly added dependency is not in the cached index), the workflow falls back to running cabal update and retrying the build. ✅ This handles the rare edge case of adding a brand-new dependency without requiring manual intervention.

## 📊 Expected Impact

🔢 Here is the breakdown of time savings we expect on a typical cached build:

- 🏗️ Dependency compilation goes from about two minutes fifty seconds down to zero, because all sixty-plus packages are already in the cabal store
- 🌐 The cabal update step goes from about fifteen seconds to zero, because the cached index is reused
- 🔨 Project compilation takes about five seconds for incremental changes (this was already working thanks to the dist-newstyle cache)
- 🧪 Tests run in about two seconds (unchanged)

📉 The total build-and-test job should drop from about four minutes fifteen seconds to well under a minute on cached runs.

## 🧠 Lessons Learned

🏷️ Always verify that your cache paths match where your tools actually read and write data. 📚 Tool defaults can change between versions, and what worked with an older cabal may silently break with a newer one.

🔍 The XDG Base Directory specification is a moving target in the Haskell ecosystem. 🛠️ The CABAL_DIR environment variable provides a stable escape hatch for CI environments where predictable paths matter more than standards compliance.

👻 A cache that restores successfully but contains no useful data is worse than no cache at all, because it gives a false sense of optimization while adding the overhead of save and restore operations.

## 📚 Book Recommendations

### 📖 Similar
* Release It! by Michael T. Nygaard is relevant because it covers designing and debugging production systems where invisible misconfigurations silently degrade performance, much like our phantom cache.
* Accelerate by Nicole Forsgren, Jez Humble, and Gene Kim is relevant because it demonstrates how CI pipeline speed directly correlates with software delivery performance and team productivity.

### ↔️ Contrasting
* The Mythical Man-Month by Frederick P. Brooks Jr. offers a counterpoint by examining cases where adding more resources to a late project makes it later, while here a tiny configuration fix yielded massive speedups.

### 🔗 Related
* Continuous Delivery by Jez Humble and David Farley explores the principles and practices behind fast, reliable deployment pipelines that depend on effective caching and incremental builds.
* Haskell in Depth by Vitaly Bragilevsky is relevant because it covers the Haskell build ecosystem including cabal and the package management strategies that underpin efficient CI for Haskell projects.
