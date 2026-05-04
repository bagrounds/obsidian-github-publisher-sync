---
share: true
aliases:
  - "2026-05-04 | 🏷️ From JSON to Haskell: Strong Types for Blog Series Configs 🤖"
title: "2026-05-04 | 🏷️ From JSON to Haskell: Strong Types for Blog Series Configs 🤖"
URL: https://bagrounds.org/ai-blog/2026-05-04-2-replace-json-configs-with-haskell
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-05-04 | 🏷️ From JSON to Haskell: Strong Types for Blog Series Configs 🤖

## 🎯 The Problem with JSON Configs

📋 The auto blog system previously stored each blog series configuration as a JSON file in the `haskell/series/` directory. 🗂️ Files like `auto-blog-zero.json`, `chickie-loo.json`, and `convergence.json` held fields such as name, icon, schedule hour, model names as strings, and optional context sources.

🔄 At runtime, `BlogSeriesDiscovery.hs` would scan the directory, read each JSON file using `Data.ByteString`, parse it into an intermediate `RawConfig` record using the custom `FromValue` typeclass, then validate and convert it into the final `DiscoveredSeries` type. 🔁 This meant every run of the scheduler had to do filesystem I/O, JSON parsing, and validation before any blog generation could start. 🏷️ The type was called `DiscoveredSeries` because the series definitions were literally discovered at runtime from the filesystem — which should have been a warning sign.

🧩 More fundamentally, the JSON format was lossy. 📉 Model names were stored as plain text strings like `gemini-2.5-flash`, then converted to the `Gemini.Model` ADT via `modelFromText`. 📅 Schedule hours were raw integers, then wrapped into `TimeOfDay`. 🗂️ Context queries were parsed from JSON objects into `ContextQuery` values. 🔁 Every import of a config required a conversion pipeline, and those conversions could fail at runtime.

## ✅ The Solution: Haskell Modules as Configs

🏷️ The fix is to use what Haskell is best at: strong static types expressed directly in source code. 📦 Each blog series now has its own dedicated Haskell module in `haskell/src/Automation/Series/`. 🤖 For example, the Auto Blog Zero series is now defined in `Automation.Series.AutoBlogZero` and exports a single value called `series` of type `AutoBlogSeries`. 🏷️ The type was renamed from `DiscoveredSeries` to `AutoBlogSeries` — because nothing is discovered at runtime anymore. 🔒 Every series is a compile-time fact encoded directly in the type system.

🧾 Instead of the JSON field `"models": ["gemini-3.1-flash-lite-preview", "gemini-3-flash-preview"]`, the Haskell config writes `Gemini.Gemini31FlashLite :| [Gemini.Gemini3Flash]`. 📅 Instead of `"scheduleHourPacific": 8`, it writes `TimeOfDay 8 0 0`. 🌐 Instead of a JSON object with string keys for context sources, it uses `ContextQuery` values directly with named fields like `directories`, `orderBy`, and `limit`.

🗂️ A central registry module at `Automation.Series` imports all six series modules and exports `allSeries :: [AutoBlogSeries]` in insertion order. 🚀 The `RunScheduled.hs` entry point now just binds `let discovered = allSeries` instead of performing IO to discover JSON files and handling discovery errors.

## 🧹 What Got Removed

🗑️ The migration eliminated a meaningful amount of complexity. ❌ The `RawConfig` type and its `FromValue` instance are gone entirely. ❌ The `DiscoveryError` sum type with its `JsonParseError` and `ValidationError` constructors is gone. ❌ The `discoverSeries`, `parseSeriesFile`, `parseSeriesConfig`, `validateRawConfig`, and `isJsonFile` functions are gone. 📦 The `haskell/series/` directory itself no longer exists.

🔧 The `BlogSeriesDiscovery` module is now a lean derivation module. 📐 It defines the `AutoBlogSeries` type and the pure convention-based functions for deriving `BlogSeriesConfig`, `BlogSeriesRunConfig`, `ScheduleEntry`, author links, base URLs, nav links, and environment variable names. 🚀 The `RunScheduled.hs` executable dropped its `filepath` and `directory` build dependencies because there are no more files to scan or paths to join.

## 📐 Architecture Benefits

🏗️ The new design aligns with several core Haskell architecture principles. 🧊 Configuration data is now a compile-time fact, not a runtime discovery — impossible states cannot be represented because the type checker enforces all invariants. 🏷️ Model names use the `Gemini.Model` ADT instead of free-form strings, so misspelling a model name is a compile error rather than a silent fallback to `Custom`. 🔒 Schedule hours use `TimeOfDay` directly, eliminating the integer-to-time conversion and the bounds validation that went with it.

🧩 Each series module is self-contained and focused. 📖 Each module exports `series :: AutoBlogSeries` and keeps a module-local `identifier :: Text` binding that is used internally — once for `seriesId = identifier` and once for `contextQueries = defaultContextQueries identifier` — so the series ID string is written exactly once in each file. 🔗 For `Convergence.hs`, which reads posts from all other series, the cross-series directory references use the other modules' exported `series` records directly — for example, `seriesId AutoBlogZero.series` instead of the raw string `"auto-blog-zero"`. 🛡️ This means if a series ID ever changes, the compiler catches every use across the whole codebase rather than leaving silent mismatches. 🏷️ The design also avoids exporting a raw `Text` identifier that callers could accidentally misuse; instead they work with the `AutoBlogSeries` value itself, which is the real domain type.

🔄 Adding a new series now requires creating one Haskell module, adding two lines to `Automation.Series`, adding one line to the cabal file, and updating documentation. 📋 The launch checklist spec was updated to reflect these steps. 🔬 The `BlogSeriesDiscoveryTest` test suite was simplified by removing the JSON parsing tests, which tested the now-deleted parsing pipeline, while retaining all the derivation tests and property-based tests.

## 🔬 Lessons Learned

🧪 The JSON config approach was convenient when the system was first built because it allowed adding series without touching Haskell source. 📦 But as the Haskell type system grew richer — with a typed `Gemini.Model` ADT, structured `ContextQuery` values, and a `TimeOfDay` schedule type — the JSON layer became a liability. 🔁 Every field had to be parsed, converted, and validated at runtime.

🏷️ Replacing the JSON files with Haskell modules turns runtime errors into compile-time errors. 🧹 It removes an entire class of failure modes. 📖 It makes each series config readable as plain Haskell record syntax. 🚀 And it simplifies the entry point by eliminating IO-based discovery and error handling that could never actually fail in a production deploy anyway — since the configs are part of the repository, not external files.

## 📚 Book Recommendations

### 📖 Similar
* Domain Modeling Made Functional by Scott Wlaschin is relevant because it advocates replacing stringly-typed data and runtime validation with a rich type system and compile-time guarantees, which is exactly the transformation this PR performs.
* Effective Haskell by Rebecca Skinner is relevant because it covers practical Haskell patterns including algebraic data types, record syntax, and module organization — the same tools used to replace the JSON configs.

### ↔️ Contrasting
* The Pragmatic Programmer by David Thomas and Andrew Hunt offers a perspective where configuration files and data-driven programs are preferred to hardcoded values, advocating for flexibility over compile-time certainty — the opposite tradeoff this PR makes.

### 🔗 Related
* Types and Programming Languages by Benjamin C. Pierce explores the foundations of type systems and how types can encode and enforce program invariants, providing the theoretical grounding for why moving from JSON strings to Haskell ADTs improves correctness.
