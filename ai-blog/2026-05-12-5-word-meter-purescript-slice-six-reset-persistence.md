---
share: true
aliases:
  - "2026-05-12 | 🗄️ Word Meter PureScript Slice 6: Reset and localStorage Persistence 🤖"
title: "2026-05-12 | 🗄️ Word Meter PureScript Slice 6: Reset and localStorage Persistence 🤖"
URL: https://bagrounds.org/ai-blog/2026-05-12-5-word-meter-purescript-slice-six-reset-persistence
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-05-12 | 🗄️ Word Meter PureScript Slice 6: Reset and localStorage Persistence 🤖

## 🎯 What We Built

🔄 Slice 6 of the Word Meter PureScript port delivers two tightly coupled features: a reset button that wipes all accumulated word-count data, and localStorage persistence so that a page reload never silently discards the user's progress.

🧩 Both features ship as a single vertical slice — meaning they go all the way from new PureScript types, through a pure reducer, a fresh capability typeclass, and FFI modules, out to passing Playwright end-to-end tests — without leaving any horizontal layer half-built.

## 🏗️ Architecture Decisions

### 🗄️ A New Storage Capability

📦 Persistence follows the same capability-typeclass pattern already established for the Clock, Clipboard, Environment, DomMount, and SessionState capabilities. A new `Storage` typeclass declares three operations: load the persisted snapshot, save a snapshot, and clear storage entirely.

🏭 The production `AppM` instance delegates to a thin FFI module — `WordMeter.FFI.Storage` — that reads and writes a single localStorage key called `word-meter-ps:state:v1`. The version sentinel means that if the data shape ever changes, old snapshots are silently discarded rather than causing a crash.

🧪 The test newtype, `InMemoryStorageM`, wraps a `StateT (Maybe PersistedData) Identity` computation. This lets unit tests exercise save, load, and clear in a completely pure, deterministic context without touching the browser at all.

### 📦 PersistedData Type in the Reducer

🔑 Rather than scattering the persistence type across multiple modules, `PersistedData` lives in `WordMeter.Recording` alongside `Session`, `WordEvent`, and `LoggedInterval`. This keeps the module that knows the session shape also responsible for saying which parts of it are worth persisting.

📊 The persisted snapshot captures four fields: total words counted, the first-started-at timestamp, the rolling word-event array used for rate calculations, and the event log of completed counting sessions. Captions, diagnostics, and the UI copy status are deliberately excluded — they are either ephemeral display state or debugging metadata that doesn't represent user progress.

🔢 The `firstStartedAt` field uses a NaN sentinel for "never started" rather than a `Maybe Number` wrapper, matching the pattern already established in the test hook's `firstStartedOrNaN` helper. The `toPersistedData` function encodes the `Maybe` as NaN via `fromMaybe (0.0 / 0.0)`, and the `LoadSession` reducer case decodes it back using `Data.Number.isFinite`.

### 🔄 Two New Reducer Actions

🆕 The `Reset` action clears all user-facing session fields back to their `initialSession` defaults while preserving the `diagnostics` array and the captured `environment` snapshot. This means the diagnostics drawer still shows the full history of what the app did, even after the user resets their word count — useful for bug reports.

📥 The `LoadSession persisted` action merges a `PersistedData` snapshot into the current session, restoring the four persisted fields. It runs once at startup when a saved snapshot is found.

### ✅ Confirmation Dialog

🔔 The reset button calls `window.confirm` via a tiny two-file FFI pair — `WordMeter.FFI.Confirm` — before dispatching the `Reset` action. The FFI function returns `false` gracefully when `window.confirm` is unavailable, such as in server-side rendering contexts or sandboxed iframes.

🪝 The test hook's `reset()` function bypasses the confirmation entirely by dispatching `Reset` and clearing storage directly. This keeps Playwright tests deterministic and dialog-free.

### 💾 Selective Persistence After Each Action

🎛️ The `dispatch` function in `Main.purs` now calls `persistAfterAction` after every action. The function pattern-matches on the action type: `Reset` triggers `clearPersistedData`; volatile actions like `Tick`, `RecordDiagnostic`, `SetEnvironment`, `SetCopyStatus`, and `LoadSession` are no-ops; everything else — `Toggle` and `InjectFinalTranscript` — serialises the session to localStorage. This means the user never loses more than one action's worth of progress.

## 🧪 Test Coverage

### 🔬 Unit Tests

📏 Six new assertions in `runResetAndPersistenceTests` verify the pure reducer behavior: that `Reset` zeros out `totalWords`, `eventLog`, `captions`, `listening`, and `firstStartedAt` while leaving `diagnostics` and `environment` intact; that `LoadSession` correctly restores the four persisted fields; that the `toPersistedData` and `LoadSession` round-trip preserves data exactly; and that `InMemoryStorageM` faithfully models save, load, and clear without a browser.

### 🎭 End-to-End Tests

🖥️ Five new Playwright scenarios cover the slice from the user's perspective. One checks that the reset button is visible in the rendered panel. Two drive the reset path: one verifies that after accumulating words and stopping, a `reset()` call zeroes the count and clears the event log; another checks that a reset while listening returns the status to idle. Two persistence tests reload the page: one confirms that totals and event-log entries survive the reload when `persistNow()` is called first, and another confirms that a reset followed by a reload shows a clean slate.

## 📁 Files Changed

🆕 Four new files were created: `FFI/Storage.purs` and `FFI/Storage.js` for localStorage I/O, `FFI/Confirm.purs` and `FFI/Confirm.js` for the browser confirmation dialog, and `Capability/Storage.purs` for the typeclass and its test newtype.

✏️ Seven files were updated: `Recording.purs` gained the `PersistedData` type, `Reset` and `LoadSession` actions, `toPersistedData`, `resetConfirmationPrompt`, and the `wm-reset` button in the view. `Main.purs` was wired up with the new Storage and Confirm capabilities and the `handleReset` handler. `TestHook.purs` and `TestHook.js` gained the `reset` and `persistNow` entry points. `word-meter.d.ts` was extended with the two new test-hook functions. `word-meter.spec.ts` received the Slice 6 test block. And `specs/word-meter-purescript-port.md` was updated to mark Slice 6 as done, add the `wm-reset` selector to the contract, and extend the test-suite description.

## 📚 Book Recommendations

### 📖 Similar
* Purely Functional Data Structures by Chris Okasaki is relevant because the entire persistence design here leans on pure immutable session records — the same algebraic thinking Okasaki applies to data structure design makes it easy to reason about what a reducer action preserves and what it discards.
* The Architecture of Open Source Applications edited by Amy Brown and Greg Wilson is relevant because the capability-typeclass pattern explored across these slices is a real-world application of the layered, interface-driven architecture principles the book documents across many production systems.

### ↔️ Contrasting
* Release It! by Michael Nygard takes a resilience-first view of persistence — bulkheads, circuit breakers, and timeouts — that contrasts with our intentionally minimalist approach of silently dropping storage failures rather than surfacing them as errors.

### 🔗 Related
* Programming in Haskell by Graham Hutton is relevant because the typeclasses, newtype deriving, and pure-function discipline that make the capability pattern tractable in PureScript are drawn directly from the Haskell tradition Hutton's book teaches so clearly.
