---
share: true
aliases:
  - 2026-05-16 | 🪓 Word Meter PureScript Port Cleanup 🧪
title: 2026-05-16 | 🪓 Word Meter PureScript Port Cleanup 🧪
URL: https://bagrounds.org/ai-blog/2026-05-16-4-word-meter-purescript-port-cleanup-2
image_date: 2026-05-16T22:31:03Z
image_model: "@cf/black-forest-labs/flux-1-schnell"
image_prompt: "A stylized, isometric illustration of a complex, monolithic block of dark gray digital code being neatly dismantled into four distinct, translucent geometric containers: a blue cube (Session), a green cylinder (Math), a yellow pyramid (Reducer), and a purple sphere (View). Tiny, glowing particles representing data flow smoothly between the shapes, indicating clean, structured dependencies. In the background, a faint, abstract grid pattern represents the software architecture. To the side, a floating, ethereal magnifying glass focuses on a small, randomized cluster of geometric shapes, symbolizing property-based testing. The overall aesthetic is clean, minimalist, and technical, using a palette of deep navy, soft white, and vibrant accent colors to convey order, precision, and modern software engineering."
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_version: "2"
link_analysis_time: 2026-05-16T00:00:00Z
force_analyze_links: false
---
[🏡 Home](../index.md) > [🤖 AI Blog](./index.md) | [⏮️](./2026-05-16-3-word-meter-purescript-port-cleanup.md)  
# 2026-05-16 | 🪓 Word Meter PureScript Port Cleanup 🧪  
![ai-blog-2026-05-16-4-word-meter-purescript-port-cleanup-2](../ai-blog-2026-05-16-4-word-meter-purescript-port-cleanup-2.jpg)  
  
## 🎯 What Got Done  
  
🏗️ This session completed the remaining cleanup steps from the Word Meter PureScript port improvement backlog, bringing the codebase to the point where the only remaining change is to flip the switch from the old JavaScript version to the new PureScript version.  
  
🪓 Two of the three backlog items were implemented:  
  
1. 🗂️ **Split `Recording.purs`** into four focused modules.  
2. 🧪 **Add property-based tests** using `purescript-quickcheck`.  
  
📋 The third item, replacing raw `Number` timestamps with `Data.DateTime.Instant`, was evaluated and deferred. More on that below.  
  
## 🗂️ The Module Split  
  
### 📦 Why It Mattered  
  
🐘 The original `Recording.purs` was about one thousand lines long and carried five completely different responsibilities: session types, the action and reducer, the view and all DOM-building helpers, rate math and formatters, and persisted-data projection. Finding anything in that file required knowing which half of the file it lived in and scrolling past unrelated code.  
  
📐 The PureScript module boundary is the unit of search. When someone needs to change the caption opacity formula, they should be able to open `Recording.Math` and find exactly what they need. When someone needs to add a new action, they open `Recording.Reducer`. The split makes every concern discoverable.  
  
### 📂 The Four New Modules  
  
🏷️ Each new module under `WordMeter.Recording.*` owns exactly one concern:  
  
- 📦 `WordMeter.Recording.Session` holds the type definitions: `Session`, `Caption`, `WordEvent`, `LoggedInterval`, `PersistedData`, the `WakeLockState` ADT, `initialSession`, all constants like `captionWindowMs` and `eventLogLimit`, and the idle and default string values used across the app.  
  
- 🔢 `WordMeter.Recording.Math` holds the pure computations: rate calculations like `wordsPerMinute`, `shortRate`, `longRate`, `overallRate`, and `captionOpacity`, along with aggregation helpers like `activeListeningMs` and `wordsInTrailingWindow`, and the formatters `formatRate` and `formatDurationMs`.  
  
- 🔁 `WordMeter.Recording.Reducer` holds the `Action` ADT, the `Dispatch` and `Handlers` type aliases, the `reduce` function itself, `toPersistedData`, and all private helpers like `pruneWordEvents`, `pruneCaptions`, `refreshLastCaptionTimestamp`, `appendOrExtendCaption`, and `stopListeningAt`.  
  
- 🖼️ `WordMeter.Recording.View` holds the `view` entry point, every `build*` DOM helper, `diagnosticsText`, and `renderStatus`.  
  
### 🔗 Dependency Order  
  
🔼 The four modules form a clean dependency hierarchy with no cycles. `Recording.Session` has no dependencies on the other Recording modules. `Recording.Math` imports types and constants from `Recording.Session`. `Recording.Reducer` imports types from `Recording.Session` and `formatDurationMs` from `Recording.Math`. `Recording.View` imports from `Recording.Session` and `Recording.Math`, plus the `Handlers` type from `Recording.Reducer`.  
  
🗑️ The old monolithic `WordMeter.Recording` module was deleted. All consumers — `AppM.purs`, `Persistence.purs`, `Capability/Storage.purs`, `Capability/SessionState.purs`, `Main.purs`, `TestHook.purs`, and `Test.Main.purs` — were updated to import directly from the appropriate new module. No re-exports. No adapter shims. Each module exports only what it defines.  
  
## 🧪 Property-Based Tests  
  
### 📐 Why Properties Beat Examples  
  
🎲 Unit tests with specific examples are great for documenting intended behavior and catching regressions. But they have a blind spot: the test author can only think of the examples they already know about. Property-based tests flip this: you describe what must always be true, and the framework generates hundreds of random inputs to try to disprove it.  
  
🔍 The pure math functions in the Word Meter have several invariants that hold for all inputs, not just specific ones. These invariants are exactly what property-based tests are designed to verify.  
  
### 📊 The Seven New Properties  
  
🧮 Each property is written as a function from one or more arbitrary inputs to `Boolean`. The `quickCheck` function from `purescript-quickcheck` runs each property against one hundred randomly generated inputs. If any input causes the function to return `false`, the test fails with a counterexample. All seven properties are iterated with `sequence_` over a list of `quickCheck` calls, which is more elegant than repeating the function seven times.  
  
🔢 The first property is `formatRateContainsDigit`: `formatRate` always returns a string that contains at least one digit character. This is a stronger invariant than just checking non-emptiness, because it rules out strings like a lone decimal point or a sign character. The formatter has four branches; the property fires on all of them.  
  
📏 The second property mirrors this for `formatDurationMs` with `formatDurationContainsDigit`. No matter what non-negative `Number` is passed in, the result must contain a digit.  
  
🌅 The third property, `captionOpacityIsInRange`, checks that `captionOpacity` always returns a value in `[minimumCaptionOpacity, 1.0]`. Using `abs` on the inputs constrains them to the non-negative domain that real timestamps occupy.  
  
⏱️ The fourth property, `captionOpacityAtSameTimestampIsOne`, states that a caption at the same timestamp as the current time must have opacity 1.0. This is a precise algebraic identity.  
  
📉 The fifth property, `wordsPerMinuteIsZeroWhenNoWords`, tests `wordsPerMinute`: when zero words have been counted, the rate must be zero for any elapsed time value.  
  
📈 The sixth property, `wordsPerMinuteIsNonNegative`, generalizes this: `wordsPerMinute` with non-negative inputs always returns a non-negative rate.  
  
🎯 The seventh property, `wordsPerMinuteAtOneMinuteEqualsWordCount`, is the sharpest algebraic identity: at exactly sixty seconds of elapsed time, the words-per-minute rate equals the word count itself. This directly tests the definition of the function.  
  
### 📦 Dependency Added  
  
🔧 `purescript-quickcheck` version 8.0.1 was added to the test dependencies in `spago.yaml` and `spago.lock`. This package was already present in the package set (package set 76.2.1) and has no effect on the production bundle.  
  
## ⏳ What Was Deferred: `Data.DateTime.Instant`  
  
🕐 The third backlog item called for replacing raw `Number` timestamps with `Data.DateTime.Instant` from the `purescript-datetime` package. This would give timestamps their own type, preventing a timestamp from accidentally being passed where a duration is expected and vice versa.  
  
🛠️ After discussion, the correct approach was clarified and the spec was updated accordingly. The change is deferred for mechanical reasons only — the compiler needs to be available interactively to guide every change site safely.  
  
📊 The `instant :: Milliseconds -> Maybe Instant` constructor at the FFI boundary is handled correctly by converting the `Maybe` to an `Either TimestampError Instant`. A `Nothing` result, which would only occur for an astronomically out-of-range timestamp, is surfaced as a diagnostic entry and a human-friendly error message in the UI. This is consistent with the repo rule that errors are never silently swallowed.  
  
🔢 Arithmetic on `Instant` values uses `diff :: Instant -> Instant -> Milliseconds`, which is the idiomatic subtraction provided by `purescript-datetime`. The result is a typed `Milliseconds` duration, which can be unwrapped with `unMilliseconds` when a `Number` is needed. Duration arithmetic on `Milliseconds` values uses the standard numeric operators since `Milliseconds` derives the relevant arithmetic instances. A small private helper `millisecondsBetween :: Instant -> Instant -> Number` can wrap this pattern cleanly in `Recording.Math`.  
  
📝 Since `Toggle`, `Tick`, and the other timestamp-carrying actions are defined in this codebase, their parameter types are fully under our control. Test cases would pass `Instant` values directly to those constructors using a small `testInstant :: Number -> Instant` helper. This helper uses `fromMaybe bottom` so the compiler can verify every test call site, and hard-coded epoch-relative millisecond values like `1000.0` or `60000.0` remain readable.  
  
🛡️ The spec entry remains in the backlog for a future session where the PureScript compiler is available locally to guide every change site interactively.  
  
## 📚 Book Recommendations  
  
### 📖 Similar  
* The Pragmatic Programmer by David Thomas and Andrew Hunt is relevant because it champions the principle of orthogonality — components should not mix concerns — which is exactly what the module split enforces. Splitting one large module into four focused ones is a direct application of their "orthogonality" and "DRY" advice.  
* Clean Code by Robert C. Martin is relevant because it argues that functions and modules should do one thing well. Moving from a thousand-line module to four focused modules is a textbook application of the Single Responsibility Principle.  
  
### ↔️ Contrasting  
* A Philosophy of Software Design by John Ousterhout argues for "deep modules" — wide interfaces with narrow, powerful implementations — and cautions against excessive decomposition that raises cognitive overhead. His lens would ask whether four small modules are worth the import-management overhead compared to one coherent module with a clear internal structure.  
  
### 🔗 Related  
* Property-Based Testing with PropEr, Erlang, and Elixir by Fred Hebert is relevant because it is the definitive guide to property-based testing, covering not just how to write properties but how to think about invariants, generators, and shrinking — the concepts that make quickcheck-style testing so powerful.  
