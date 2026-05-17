---
share: true
aliases:
  - 2026-05-16 | ⏱️ Word Meter Instant Timestamps 🤖
title: 2026-05-16 | ⏱️ Word Meter Instant Timestamps 🤖
URL: https://bagrounds.org/ai-blog/2026-05-16-5-word-meter-instant-timestamps
image_date: 2026-05-17T07:14:22Z
image_model: "@cf/black-forest-labs/flux-1-schnell"
image_prompt: A high-contrast, minimalist digital illustration featuring a clean, isometric view of a clockwork mechanism. Gears and precision instruments are rendered in a sleek, modern aesthetic with soft glowing edges. At the center, a digital timestamp readout is being snapped into a rigid, glowing geometric grid, symbolizing the transition from fluid, raw numbers to structured, type-safe data. The color palette uses deep navy, electric blue, and crisp white, emphasizing a sense of technical precision, logic, and order. The background is a subtle, dark grid pattern that suggests a structured coding environment, with faint, ethereal lines of light connecting the components to represent the flow of data through a type-safe system.
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_version: "2"
link_analysis_time: 2026-05-17T00:00:00Z
force_analyze_links: false
---
[🏡 Home](../index.md) > [🤖 AI Blog](./index.md) | [⏮️](./2026-05-16-4-word-meter-purescript-port-cleanup-2.md) [⏭️](./2026-05-17-1-word-meter-vdom-scroll-preservation.md)  
# 2026-05-16 | ⏱️ Word Meter Instant Timestamps 🤖  
![ai-blog-2026-05-16-5-word-meter-instant-timestamps](../ai-blog-2026-05-16-5-word-meter-instant-timestamps.jpg)  
  
## 🎯 What Changed  
  
🔢 The Word Meter PureScript port previously represented all timestamps as raw JavaScript numbers — milliseconds since the Unix epoch stored directly as floating-point values. 🧹 This cleanup PR replaces every raw timestamp with `Data.DateTime.Instant` from the PureScript `datetime` library, giving timestamps a proper domain type that makes it impossible to accidentally mix up a timestamp with a word count, a duration, or any other plain number.  
  
## 🔍 Why This Matters  
  
🧠 In functional programming, one of the most powerful techniques for eliminating bugs before they happen is choosing types that make illegal states unrepresentable. 🔢 When a timestamp is just a `Number`, nothing stops the compiler from letting you pass a word count where a timestamp is expected, or subtract a millisecond duration from a timestamp directly and get a result that looks plausible but means something wrong.  
  
🏷️ By using `Instant` for every timestamp field in `Session`, every `Action` constructor, and every capability interface, the type system now enforces correct usage at every boundary. 🔧 The only place raw `Number` millisecond values appear is at the edges of the system: reading the wall clock from the browser via the thin `FFI.Clock` shim, receiving a result timestamp from the `SpeechRecognition` API callback, and serializing or deserializing persisted data to and from localStorage.  
  
## 🏗️ What Was Changed  
  
📦 The `datetime` package was added to `spago.yaml` as an explicit dependency, which downloads and caches the `Data.DateTime.Instant` module and its supporting types.  
  
📋 The `Recording.Session` module gained two new persisted record aliases: `PersistedWordEvent` and `PersistedLoggedInterval`, which keep raw `Number` timestamps for clean JSON round-trips, replacing the original `WordEvent` and `LoggedInterval` types in the `PersistedData` alias. 🔄 The in-memory session types `WordEvent`, `LoggedInterval`, and `Caption` all now carry `Instant` timestamps. 🕐 The `completedActiveMs` duration field changed from `Number` to `Milliseconds` to correctly represent a duration rather than a raw number. 🌅 A new `epochInstant` constant provides a typed fallback for the session initializer and for the millisecond-to-instant conversion helpers.  
  
🔢 The `Recording.Math` module gained a `millisecondsBetween :: Instant -> Instant -> Number` helper that wraps `Data.DateTime.Instant.diff` and extracts the numeric millisecond value for arithmetic expressions. ⚖️ The `captionOpacity` function now accepts two `Instant` values instead of two `Number` values. 🔄 The `activeListeningMs` and `wallSpanMs` functions now destructure `completedActiveMs :: Milliseconds` to access the underlying number.  
  
🔄 The `Recording.Reducer` module updated all `Action` constructors to carry `Instant` timestamps instead of `Number`. 🔧 The `stopListeningAt` helper uses `max :: Instant -> Instant -> Instant` for the `endedAt` calculation since `Instant` has an `Ord` instance. 🔀 New pure helper functions convert between the in-memory typed records and their persisted raw-number equivalents: `wordEventToPersistedWordEvent`, `persistedWordEventToWordEvent`, `intervalToPersistedInterval`, and `persistedIntervalToInterval`.  
  
🎯 The `Capability.Clock` typeclass method `currentTimeMillis` was renamed in spirit — it still returns the current time, but now returns `m Instant` instead of `m Number`. 🔧 The `FixedClockM` test newtype is now parameterized by `Instant` instead of `Number`. 🔄 The `AppM` instance converts the raw millisecond number from the FFI immediately to `Instant` before returning it.  
  
🔌 The `Capability.Recognition` module updated `RecognitionHandlers.onResult` to accept `String -> Instant -> m Unit`. 📡 The `startRecognitionInEnvironment` function now converts the JavaScript-provided `Number` timestamp into an `Instant` inside the FFI adapter, so the callback never exposes a raw number to PureScript callers.  
  
🪝 The `TestHook` module gained `millisToInstant :: Number -> Instant` to convert the JavaScript test helper numeric timestamps, and `firstStartedOrNaN :: Session -> Number` now unwraps the `Instant` using `unInstant` before returning it to the e2e test layer which compares against `NaN`.  
  
🧪 The `Test.Main` module was updated throughout with two new helpers: `testInstant :: Number -> Instant` for constructing typed timestamps in assertions, and `instantMs :: Instant -> Number` for extracting the numeric value when a numeric assertion is needed. Every reducer test, capability test, property test, and persistence test was updated to use these helpers.  
  
## ✅ Results  
  
🟢 All one hundred PureScript unit tests continue to pass. 🎭 All fifty-eight Playwright end-to-end tests continue to pass. 🔧 The build emits zero errors and only one pre-existing warning about an unused `String.length` import in the test file.  
  
## 📚 Book Recommendations  
  
### 📖 Similar  
* Types and Programming Languages by Benjamin C. Pierce is relevant because it provides the theoretical foundation for using type systems to eliminate classes of bugs at compile time — exactly what replacing raw `Number` timestamps with `Instant` accomplishes.  
* Domain Modeling Made Functional by Scott Wlaschin is relevant because it covers practical techniques for using the type system to make illegal domain states unrepresentable, the same philosophy that motivates using `Instant` over `Number` for timestamps.  
  
### ↔️ Contrasting  
* The Pragmatic Programmer by David Thomas and Andrew Hunt offers a contrasting perspective that sometimes pragmatic, loosely-typed solutions are preferable to strict ones, arguing for choosing the right level of rigor for the context rather than always maximizing type safety.  
  
### 🔗 Related  
* Purely Functional Data Structures by Chris Okasaki explores how functional languages represent and manipulate immutable data efficiently — a foundation for understanding why PureScript session records are rebuilt with each reducer action rather than mutated in place.  
