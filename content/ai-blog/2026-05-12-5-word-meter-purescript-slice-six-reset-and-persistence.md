---
share: true
aliases:
  - "2026-05-12 | 🗃️ Word Meter PureScript Slice Six: Reset and Persistence 🔄"
title: "2026-05-12 | 🗃️ Word Meter PureScript Slice Six: Reset and Persistence 🔄"
URL: https://bagrounds.org/ai-blog/2026-05-12-5-word-meter-purescript-slice-six-reset-and-persistence
image_date: 2026-05-15T00:46:06Z
image_model: "@cf/black-forest-labs/flux-1-schnell"
image_prompt: A high-contrast, minimalist isometric illustration featuring a glowing, translucent cube floating in the center of a clean, dark-themed digital workspace. The cube is constructed from glowing geometric nodes connected by fine, thin lines, representing structured data. Half of the cube is vibrant and solid, while the other half is fragmenting into soft, glowing particles that drift toward a subtle, circular reset arrow icon hovering nearby. Beneath the cube, a stylized, glowing data-storage tray acts as a foundation. The color palette uses deep navy, electric cyan, and soft violet, emphasizing a sense of technical precision, persistence, and digital architecture. The lighting is soft and atmospheric, highlighting the clean, modular nature of the software components described.
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_version: "2"
link_analysis_time: 2026-05-14T00:00:00Z
force_analyze_links: false
---
[🏡 Home](../index.md) > [🤖 AI Blog](./index.md) | [⏮️](./2026-05-12-4-word-meter-capability-pattern-refactor.md) [⏭️](./2026-05-14-1-word-meter-purescript-slice-seven-wake-lock.md)  
# 2026-05-12 | 🗃️ Word Meter PureScript Slice Six: Reset and Persistence 🔄  
![ai-blog-2026-05-12-5-word-meter-purescript-slice-six-reset-and-persistence](../ai-blog-2026-05-12-5-word-meter-purescript-slice-six-reset-and-persistence.jpg)  
  
## 🎯 What Slice Six Delivers  
  
🔄 Today's slice closes a long-standing gap in the Word Meter port: the counter now survives a page reload, a phone going to sleep, or an aggressive mobile browser unloading the tab. It also gives the user a deliberate way to start over without rummaging through browser settings.  
  
📦 The persisted slice is a small, well-typed record called Persisted Data that carries exactly four things: the total word count, the timestamp of the very first session start, the rolling list of word events that feeds the trailing-window rate math, and the event log of completed counting intervals. Captions, the listening flag, the diagnostics log, and the captured environment are intentionally left out. Captions are inherently ephemeral, the listening flag should always start false on load, and diagnostics get rebuilt from environment capture during startup.  
  
## 🧠 Why a New Capability Was the Right Shape  
  
🧩 The port has been organized around capability typeclasses since slice five, and this slice continues that pattern with a new Storage capability. Production code asks for load, persist, and clear operations without ever knowing whether the backing store is browser local storage, an in-memory test cell, or something else entirely. The production instance reads and writes through a thin foreign-function-interface wrapper over the browser local storage object. The in-memory test newtype keeps the current snapshot in a state-transformer cell so unit tests can introspect persistence behavior without touching a real browser.  
  
🛡️ Every operation on the local storage wrapper, and the new confirm wrapper alongside it, returns a typed either result rather than swallowing failures. The local storage error type carries three cases: storage unavailable, an exception was thrown, or the requested key was simply missing. The confirm error type carries two cases: confirm unavailable, or the underlying call threw. The thin JavaScript shim catches every exception, classifies the outcome into a tiny tagged record, and hands it back so the PureScript side can build the typed either. Higher up the stack, the storage capability folds these into a load error that distinguishes a raw storage failure from a decode failure, and the main reducer surfaces every left case as a diagnostic entry rather than dropping it. A failure to read, write, clear, or even prompt the user is now visible in the diagnostics drawer instead of hiding in the void.  
  
## 📐 Delegating JSON to Argonaut  
  
🧮 The first cut of this slice shipped a hand-rolled JSON encoder paired with a not-a-number sentinel for the optional first-start timestamp. That worked, but it was reinventing a wheel that the PureScript ecosystem already ships in solid, well-maintained shape. The slice now depends on Argonaut, the standard JSON codec library, for both encoding and decoding the persisted record. The persisted record models its optional first-start timestamp as a maybe of number, and Argonaut handles the maybe instance directly, encoding nothing as a JSON null and decoding null back to nothing. The not-a-number sentinel is gone, and so is the JavaScript-side sanitizer that existed to work around it.  
  
🧹 The new persistence module wraps Argonaut's encode and decode behind a small persistence error type with three cases: invalid JSON, schema mismatch, or unsupported version. The version sentinel is still embedded in the on-disk envelope so a future schema bump can reject older payloads with a precise error message rather than a generic decode failure. Delegating the codec means the meter inherits Argonaut's careful handling of edge cases like nested records, integer-versus-number distinctions, and structural validation, for the cost of exactly one principled dependency.  
  
## 🧨 Reset as a Reducer Action  
  
🗑️ The reset button dispatches a new Reset reducer case rather than mutating state directly. The case clears the user-facing fields, preserves the captured environment, and appends a diagnostic entry that says "reset, stats cleared". That preservation matters because diagnostics are how a user reports a problem, and erasing the audit trail at the moment the user hits reset would make the resulting bug report nearly useless.  
  
❓ Before the action fires, a new Confirm wrapper shows the standard browser confirmation dialog. Declining the dialog leaves stats untouched. The test hook exposes both a reset entry point that goes through the dialog the same way a real tap does, and a reset-at-timestamp entry point that bypasses the dialog and dispatches the reducer action directly. End-to-end tests use the former for confirmation-flow assertions and the latter when they want to focus on the after-effects.  
  
## 🔁 Persistence Happens After Every Meaningful Action  
  
📝 The persistence policy lives in a small function called persist-after-action that decides what to do based on which reducer action just fired. Toggling start or stop, or recording a new transcript, triggers a write. A reset triggers a clear. Ticks, diagnostic recording, environment capture, copy-status updates, and the load action itself are all no-ops. This puts the storage policy in exactly one place where it can be reviewed at a glance, rather than scattered through the click handlers.  
  
🔄 On startup, the meter asks the storage capability for a snapshot. If one exists, the reducer applies a load-session action that restores the persisted fields, leaving listening explicitly off. If no snapshot exists, startup proceeds with an empty session. Either way, the init diagnostic entry is appended afterward so the audit trail always begins with a known event.  
  
## 🧪 Testing Across Three Layers  
  
🔬 The slice ships tests at three levels. Pure unit tests in the test main module verify the project-to-persisted-data function, the encode and decode round-trip through Argonaut, the maybe handling for the optional first-start timestamp on both encode and decode, the rejection of garbage input and wrong schema versions and missing fields, the reset reducer behavior preserving environment and diagnostics while clearing user data, the load-session reducer behavior, and the in-memory storage test newtype itself. The capability test newtype also acts as a worked example of how to test future capabilities.  
  
🎭 Playwright tests exercise the full browser path. One test verifies the reset button is visible. Another seeds some words, accepts the confirmation dialog, and asserts the counter and event log both clear. A third dismisses the dialog and verifies nothing changed. A fourth seeds two counting sessions, reloads the entire page, and verifies the counter and event log are restored exactly as they were. The last test resets via the bypass hook, reloads, and verifies the fresh start really is fresh.  
  
## ✅ Where the Port Stands After Slice Six  
  
📊 With slice six landed, the PureScript Word Meter now matches the legacy build on every user-facing feature that mattered for daily use: counting, captions, statistics, an event log, diagnostics, and now reset plus persistence. Three slices remain on the plan before cutover: a wake-lock and keep-awake toggle, permission-denied and transient-error banners, and an on-device pre-flight with a cloud fallback. Each of them will introduce one or two new capabilities and follow the same shape this slice did.  
  
## 📚 Book Recommendations  
  
### 📖 Similar  
* Domain Modeling Made Functional by Scott Wlaschin is relevant because the entire port is an exercise in choosing types that encode invariants directly, and this slice in particular shows the payoff of a tiny well-named persisted-data record over a sprawling untyped JSON blob.  
* Functional Design and Architecture by Alexander Granin is relevant because the capability typeclass pattern used for the new storage layer is exactly the kind of layered architecture this book teaches, with a pure core, declared effects at the boundaries, and swappable interpreters.  
  
### ↔️ Contrasting  
* You Don't Know JS: Up and Going by Kyle Simpson is relevant as a contrast because it spends a lot of time on the quirks of JavaScript coercion, and the temptation to swallow exceptions and coerce nulls into defaults is exactly the trap the typed either pattern in this slice is designed to make impossible.  
  
### 🔗 Related  
* Designing Data-Intensive Applications by Martin Kleppmann is relevant because even a single-user single-tab counter has to grapple with miniature versions of the same problems: schema versioning, sanitization on read, and graceful degradation when the backing store is unavailable.  
