---
share: true
title: 🎙️ Word Meter PureScript Port Spec
---

# 🎙️ Word Meter PureScript Port Spec

Incremental port of `quartz/static/word-meter.js` to PureScript, compiling to `quartz/static/word-meter-ps.js`. Both builds run side-by-side until the cutover. `specs/word-meter.md` remains the source of truth for **what** the Word Meter does; this spec covers **how** the PureScript port is structured.

## Slicing principle

A vertical slice delivers **end-to-end, user-visible functionality** in the smallest coherent feature. Every slice must be end-to-end testable through the Playwright harness against the same selector contract every implementation honors. We never build a horizontal layer (capability, FFI module, view library) as a slice on its own — those grow in service of features as the features arrive.

## Toolchain

- Compiler: `purescript@0.15.16`.
- Build tool: `spago@1.0.4`.
- Bundler: `spago bundle --platform browser --bundle-type app` (esbuild under the hood) → single self-invoking IIFE.
- End-to-end tests: `@playwright/test` against a static-fixture page served by `http-server`.

### Dependencies

Held to the `purescript/` GitHub organization's core libraries: `prelude`, `effect`, `console`, `maybe`, `arrays`, `strings`, `integers`, `foldable-traversable`. No user-space packages.

## Project layout

```
purs-ps/
  spago.yaml
  src/WordMeter/
    Main.purs                  entry point (Effect); wires capabilities + click handlers
    AppM.purs                  ReaderT-based production newtype + ApplicationEnvironment
    Version.purs               WORD_METER_VERSION constant
    Clock.purs / Clock.js      pure locale clock-time formatter (no effects)
    Vdom.purs / Vdom.js        typed declarative DOM (Element / Attribute / Style / Listener) + mount
    Words.purs                 pure word counter
    Recording.purs             slices 1–6: session state + reducer + view + rate math + event log + diagnostics view + reset + persisted-data projection
    Diagnostics.purs           slice 5: pure diagnostics log + environment-snapshot formatters
    TestHook.purs / .js        window.__wordMeter test hook
    Capability/
      Clock.purs               class Clock + AppM instance + FixedClockM test newtype
      Clipboard.purs           class Clipboard + AppM instance + RecordingClipboardM test newtype
      Environment.purs         class Environment + AppM instance + StubEnvironmentM test newtype
      DomMount.purs            class DomMount + AppM instance + RecordingDomMountM test newtype
      SessionState.purs        class SessionState + AppM instance + StatefulSessionM test newtype
      Storage.purs             class Storage + AppM instance + InMemoryStorageM test newtype (slice 6)
    FFI/
      Clock.purs / .js         currentTimeMillis :: Effect Number
      Clipboard.purs / .js     navigator.clipboard.writeText with success / error callbacks
      Environment.purs / .js   navigator.userAgent / navigator.language snapshot capture
      Storage.purs / .js       localStorage get / set / remove + JSON-decode sanitizer (slice 6)
      Confirm.purs / .js       window.confirm wrapper for destructive-action prompts (slice 6)
  test/Test.Main.purs          pure reducer / formatter unit tests + per-capability test-newtype tests
scripts/
  build-word-meter-ps.mjs      spago bundle wrapper
tests/e2e/
  playwright.config.ts
  word-meter.spec.ts
  word-meter.d.ts              ambient types for window.__wordMeter
  fixtures/word-meter.html     ?build=js|ps loader
```

## Declarative typed DOM

The PureScript bundle never produces an HTML string. `WordMeter.Vdom` defines a small algebra:

- `Node` — `ElementNode { tag, attributes, styles, listeners, children }` or `TextNode String`.
- `Attribute`, `Style`, `Listener` — typed records.
- Smart constructors: `div_`, `button`, `span_`, `text`, `attribute`, `testId`, `buttonType`, `style`, `onClick`.
- `mount :: String -> Node -> Effect Unit` walks the tree, calling `document.createElement` / `setAttribute` / `style.setProperty` / `addEventListener` / `appendChild` through the narrow FFI surface in `Vdom.js`. Production code does not call `mount` directly — it uses the `DomMount` capability's `mountToHost`, whose `AppM` instance delegates here.

Views are pure functions from state to `Node`. The reducer loop in `Main.purs` reads state through `SessionState`'s `readCurrentSession`, calls `view handlers state`, and remounts through `mountToHost` after every dispatched action.

## Capability pattern

Every effect this app needs (clock, clipboard, environment snapshot, DOM mount, session state, and the future wake lock / speech-recognition / storage / logging) lives behind a **capability typeclass**, and production code is written against the typeclasses rather than against `Effect` directly. See [`specs/purescript-capability-pattern.md`](./purescript-capability-pattern.md) for the full pattern: how to declare a capability, how to write the production `AppM` newtype, how to write a deterministic test newtype, and how this delivers swappable implementations + property-testable pure logic.

As of slice 6 the port runs end-to-end on the capability pattern. `WordMeter.AppM` is a `ReaderT ApplicationEnvironment Effect` newtype whose environment carries the session `Ref`. Production code in `WordMeter.Main` is polymorphic over `m` with `Clock m`, `Clipboard m`, `Environment m`, `DomMount m`, `SessionState m`, and `Storage m` constraints; the `Effect`-typed click callbacks the typed DOM tree needs are built at the boundary by `runAppM`. Each capability module exports at least one test newtype (`FixedClockM`, `RecordingClipboardM`, `StubEnvironmentM`, `RecordingDomMountM`, `StatefulSessionM`, `InMemoryStorageM`) and `Test.Main` exercises them, so the pattern pays for its abstraction tax.

Future capabilities (`WakeLock`, `Recognition`, `Log`, …) grow into the same shape: a class with an `AppM` instance and at least one test newtype, sitting alongside its `FFI` siblings.

## Persistence (slice 6)

The slice that survives across page reloads / tab unloads is `Recording.PersistedData`: `{ totalWords, firstStartedAt, wordEvents, eventLog }`. Diagnostics, captions, environment, listening flag, and clock are deliberately excluded — they are either ephemeral or rebuilt from environment on startup. `Main.persistAfterAction` writes after every `Toggle` and `InjectFinalTranscript`, clears after `Reset`, and is a no-op for `Tick` / `RecordDiagnostic` / `SetEnvironment` / `SetCopyStatus` / `LoadSession`. The capability backend is `localStorage` under key `word-meter-ps:state:v1` with `version=1` sentinel; missing key, parse failure, schema mismatch, and `localStorage` being disabled all gracefully degrade to "no restore".

## Test hook

When the host page sets `window.__WM_TEST_HOOK__ = true` before loading the bundle, the bundle exposes `window.__wordMeter` with both clock-bound and clock-injectable entry points so the e2e suite can drive deterministic time:

- `simulateFinalTranscript(transcript)` / `simulateFinalTranscriptAt(transcript, timestamp)` — push a recognized utterance through the reducer (real wall-clock vs. injected timestamp).
- `start()` / `stop()` / `startAt(timestamp)` / `stopAt(timestamp)` — toggle listening state.
- `tick(timestamp)` — advance the reducer's notion of "now" without dispatching an action; used to recompute rates against a known clock.
- `getTotalWords()` / `getListening()` / `getVersion()` — read accessors.
- `getRateShort()` / `getRateLong()` / `getRateOverall()` / `getDurationMs()` / `getFirstStartedAt()` — numeric stats accessors that bypass formatting so tests can assert exact values.
- `getEventLogLength()` / `getEventLogLimit()` — current size of and cap on the per-counting-session event log.
- `getDiagnosticsText()` / `getDiagnosticsLength()` / `getDiagnosticsLimit()` — rendered diagnostics text (snapshot + log), current size, and cap on the rolling event log.
- `getCopyStatus()` — current value of the copy-to-clipboard status span (`""`, `"Copied!"`, or `"Copy failed: <reason>"`).
- `requestCopyDiagnostics()` — same code path the copy button takes; useful when a test wants to drive the clipboard write without a click.
- `reset()` — same code path the reset button takes, including the `window.confirm` prompt; tests that want to skip the prompt should use `resetAt` instead.
- `resetAt(timestamp)` — dispatches a `Reset` action at the given clock value, bypassing the confirmation dialog; clears persisted state via the `Storage` capability.
- `persistNow()` — force-persists the current session through the `Storage` capability without waiting for the next reducer action.

The hook is the contract the end-to-end suite uses to simulate Web Speech API events.

## Implementation-agnostic test suite

`tests/e2e/word-meter.spec.ts` loads `?build=js` or `?build=ps` and drives the panel through a stable `data-testid` selector contract:

- `wm-root` — mounted container.
- `wm-build` — "PureScript build" / "JavaScript build" tag.
- `wm-status` — listening / idle status.
- `wm-count` — total words.
- `wm-count-label` — descriptor.
- `wm-toggle` — start / stop button.
- `wm-reset` — reset button. On tap, prompts via `window.confirm(resetConfirmationPrompt)`; on acceptance, dispatches a `Reset` action that clears `totalWords`, `wordEvents`, `eventLog`, captions, and `firstStartedAt`, preserves the captured environment + diagnostics log (so the reset itself is auditable), and clears the persisted snapshot from `localStorage` (key `word-meter-ps:state:v1`).
- `wm-captions` — captions strip container; mostly a troubleshooting aid showing recent recognized utterances as they fade out.
- `wm-captions-placeholder` — "Waiting for speech…" shown when no caption is within the 30s window.
- `wm-caption` — one per recognized utterance, in chronological order. Captions older than `captionWindowMs` (30s) are pruned on every action, and their CSS `opacity` fades linearly with age from 1.0 down to `minimumCaptionOpacity` (0.15).
- `wm-stats` — stats dashboard container.
- `wm-rate-short` — words / minute over the trailing 1-minute window.
- `wm-rate-long` — words / minute over the trailing 10-minute window.
- `wm-rate-overall` — words / minute over total active listening time.
- `wm-duration` — active listening duration (formatted, e.g. `15s`, `1m 5s`).
- `wm-started` — clock time when the session first started, or `—` if never started.
- `wm-event-log` — event log container; one row per completed **counting session** (a single start→stop interval). The log persists across stops and restarts so that history accumulates over time.
- `wm-event-log-placeholder` — "(no counting sessions yet — press Start counting to begin)" shown when no interval has been completed.
- `wm-event-log-entry` — one per completed counting session, in chronological order (oldest first), capped at the most recent 200 entries.
- `wm-event-log-entry-started` — clock time when the counting session started.
- `wm-event-log-entry-duration` — total duration of the counting session, formatted by `formatDurationMs` (e.g. `30s`, `1m 0s`).
- `wm-event-log-entry-words` — word count for the session, rendered as `<n> w`.
- `wm-event-log-entry-rate` — words / minute for the session, rendered as `<x> wpm` via `formatRate`.
- `wm-diagnostics` — collapsible `<details>` drawer; collapsed by default, opens on a tap of the summary.
- `wm-diagnostics-toggle` — the `<summary>` row labelled `🔧 Diagnostics`.
- `wm-diagnostics-copy` — the `📋 Copy diagnostics` button. On click the meter calls `navigator.clipboard.writeText` with the rendered text and updates `wm-diagnostics-copy-status` with `Copied!` on success or `Copy failed: <reason>` on failure (including when the Clipboard API is unavailable).
- `wm-diagnostics-copy-status` — a span next to the copy button, empty until the first copy attempt completes.
- `wm-diagnostics-content` — a `<pre>` containing the formatted diagnostics text: an environment snapshot prefix (`version`, `userAgent`, `navigator.language`) followed by the rolling event log capped at `diagnosticsLimit` (60) entries. Each event line is `<clock-time>  <label>[ — <detail>]`.
- `wm-version` — `Word Meter v<x>` footer.

Every implementation must honor this contract. As behavior moves from the legacy build to the new build, the same tests verify both columns.

## Feature slices

| Slice | Feature                                                                                                 | Status     |
| ----- | ------------------------------------------------------------------------------------------------------- | ---------- |
| 1     | Start / stop recording works e2e (toggle status, button label, transcript-driven count)                 | ✅ Done    |
| 2     | Live captions panel (recent utterances strip that decays over a 30s window with opacity fade)           | ✅ Done    |
| 3     | Real, functioning stats dashboard (words/min over short + long windows, duration, totals)               | ✅ Done    |
| 4     | Event log with word histories (timeline of completed counting sessions: started, duration, words, wpm) | ✅ Done    |
| 5     | Fully functional diagnostics panel (collapsible drawer + copy-to-clipboard)                             | ✅ Done    |
| 6     | Reset + persistence (localStorage round-trip)                                                           | ✅ Done    |
| 7     | Wake lock + keep-awake toggle                                                                           | ⏳ Pending |
| 8     | Permission denied + transient-error banner                                                              | ⏳ Pending |
| 9     | On-device pre-flight + cloud fallback                                                                   | ⏳ Pending |
| 10    | Cutover — point `content/tools/word-meter.md` at the PureScript build, retire legacy JS + sandbox tests | ⏳ Pending |

## Build, test, bundle

- `npm run build:ps` — rebuild `quartz/static/word-meter-ps.js`.
- `npm run clean:ps` — wipe PureScript build artifacts.
- `npm run test:ps` — `spago test` unit suite (covers the pure rate math: `formatRate`, `formatDurationMs`, `ratePerMinute`, end-to-end reducer runs through `Toggle`/`InjectFinalTranscript`/`Tick`, the slice-4 event-log reducer behavior for completed counting sessions including stop pushes, stop/restart preservation and cap eviction, the slice-2 caption time-decay including pruning past the 30s window and the linear opacity fade, and the slice-5 diagnostics behavior: per-action entry recording, `diagnosticsLimit` cap, `formatDiagnostics` snapshot prefix and placeholder, and the `SetCopyStatus` reducer case).
- `npm run test:e2e` — Playwright suite against the current PureScript bundle.
