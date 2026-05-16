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
    Recording.purs             slices 1–8: session state + reducer + view + rate math + event log + diagnostics view + reset + persisted-data projection + recognition error banner
    Diagnostics.purs           slice 5: pure diagnostics log + environment-snapshot formatters
    RecognitionError.purs      slice 8: pure typed classification of `recognition.onerror` codes + banner-text rendering
    TestHook.purs / .js        window.__wordMeter test hook
    Capability/
      Clock.purs               class Clock + AppM instance + FixedClockM test newtype
      Clipboard.purs           class Clipboard + AppM instance + RecordingClipboardM test newtype
      Environment.purs         class Environment + AppM instance + StubEnvironmentM test newtype
      DomMount.purs            class DomMount + AppM instance + RecordingDomMountM test newtype
      SessionState.purs        class SessionState + AppM instance + StatefulSessionM test newtype
      Storage.purs             class Storage + AppM instance + InMemoryStorageM test newtype (slice 6)
      WakeLock.purs            class WakeLock + AppM instance + RecordingWakeLockM test newtype (slice 7)
    Persistence.purs           Argonaut-backed encode / decode for `Recording.PersistedData` (slice 6)
    FFI/
      Clock.purs / .js         currentTimeMillis :: Effect Number
      Clipboard.purs / .js     navigator.clipboard.writeText with success / error callbacks
      Environment.purs / .js   navigator.userAgent / navigator.language snapshot capture
      Storage.purs / .js       localStorage read / write / clear returning `Either StorageError a` (slice 6)
      StorageError.purs        `data StorageError = StorageUnavailable | StorageException | MissingKey` (slice 6)
      Confirm.purs / .js       window.confirm wrapper returning `Either ConfirmError Boolean` (slice 6)
      WakeLock.purs / .js      Thin shims over `navigator.wakeLock`: `wakeLockApiAvailable`, `requestScreenWakeLock`, `attachSentinelReleaseListener`, `releaseSentinel`, `sentinelsEqual`; opaque `WakeLockSentinel` + typed `WakeLockError` (slice 7)
      Visibility.purs / .js    document `visibilitychange` subscription (`onPageBecameVisible`) for wake-lock re-acquisition (slice 7)
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

The slice that survives across page reloads / tab unloads is `Recording.PersistedData`: `{ totalWords, firstStartedAt :: Maybe Number, wordEvents, eventLog }`. Diagnostics, captions, environment, listening flag, and clock are deliberately excluded — they are either ephemeral or rebuilt from environment on startup.

Encoding and decoding are delegated to **Argonaut** (`argonaut-core` + `argonaut-codecs`). `WordMeter.Persistence` defines `encodePersistedData :: PersistedData -> String`, `decodePersistedData :: String -> Either PersistenceError PersistedData`, and the `PersistenceError` ADT (`InvalidJson | SchemaMismatch | UnsupportedVersion`). The on-disk envelope embeds a `version` sentinel (currently `1`) and stores `firstStartedAt` as either a JSON number or `null` — Argonaut's `Maybe` instance handles both directions, so there is no NaN-sentinel hack.

Every fallible boundary returns `Either` rather than swallowing failures:

- `WordMeter.FFI.Storage` exposes `readPersistedString / writePersistedString / clearPersistedString :: ... -> Effect (Either StorageError ...)` where `StorageError = StorageUnavailable | StorageException String | MissingKey String`. The JS shim in `Storage.js` catches every `localStorage` exception, classifies it (unavailable vs. thrown vs. key missing), and hands the structured outcome back through a small record so the PureScript side can build the typed `Either`.
- `WordMeter.FFI.Confirm` exposes `askForConfirmation :: String -> Effect (Either ConfirmError Boolean)` with `ConfirmError = ConfirmUnavailable | ConfirmException String`.
- `WordMeter.Capability.Storage` lifts those errors into a `LoadError = LoadStorageError StorageError | LoadDecodeError PersistenceError` for the read side, and surfaces the raw `StorageError` for writes and clears.

`Main.persistAfterAction` writes after every `Toggle` and `InjectFinalTranscript`, clears after `Reset`, and is a no-op for `Tick` / `RecordDiagnostic` / `SetEnvironment` / `SetCopyStatus` / `LoadSession` / `SetKeepAwake` / `SetKeepAwakeStatus` / `SetWakeLockHeld`. Every `Left` from a load, persist, clear, or confirm call is recorded as a diagnostic entry (`persist load failure`, `persist save failure`, `persist clear failure`, `reset confirm failure`) so failures are visible in the diagnostics drawer rather than silently dropped.

## Wake lock + keep-awake toggle (slice 7)

The keep-awake feature mirrors the legacy build's "🔋 Keep counting with screen on (recommended)" checkbox. Slice 7 keeps the preference and the wake-lock lifetime fully inside the reducer + capability stack:

- `Session.keepAwake :: Boolean` (default `true`) is the user's preference. It is **not** persisted across reloads — every fresh page load starts with the recommended-on default, matching legacy behavior. The reducer responds to a `SetKeepAwake` action; turning it off also clears any lingering `keepAwakeStatus` so the UI does not contradict the new preference.
- `Session.keepAwakeStatus :: String` is the human-facing status next to the checkbox: empty when idle, `"screen will stay on"` after a successful acquisition, `"(wake lock not supported on this browser)"` or `"(wake lock unavailable: <reason>)"` on failure. Driven by `SetKeepAwakeStatus`.
- `Session.wakeLockHeld :: Boolean` tracks whether we currently hold the system sentinel. The browser can auto-release on visibility-hidden; when it does, `onAutoReleased` fires and `SetWakeLockHeld false` flips the flag without changing the user preference.
- `WordMeter.FFI.WakeLock` exposes the Screen Wake Lock API as five **thin** foreign imports — `wakeLockApiAvailable :: Effect Boolean`, `requestScreenWakeLock` (sentinel callback / error callback), `attachSentinelReleaseListener`, `releaseSentinel` (success callback / error callback), `sentinelsEqual` — plus the typed error ADT `WakeLockError = WakeLockUnsupported | WakeLockUnavailable String`. The JS shim does **no** state management and **no** decisions about what "auto-release" means — `WakeLockSentinel` is an opaque PureScript handle. All lifetime management (which sentinel is currently held, telling browser-initiated auto-release apart from program-initiated explicit release) lives in PureScript in `WordMeter.Capability.WakeLock`, which threads a `Ref (Maybe WakeLockSentinel)` through the `ApplicationEnvironment`. `requestScreenWakeLock` (on the capability) takes three continuations (`onAcquired`, `onError`, `onAutoReleased`) — the same shape as `Clipboard` — and `releaseScreenWakeLock` takes two (`onReleased`, `onError`) so release failures surface as diagnostics the same way acquisition failures do (never silently swallowed).
- `WordMeter.FFI.Visibility.onPageBecameVisible` registers a single document-level `visibilitychange` listener that fires the supplied handler whenever the page becomes visible. The handler re-acquires the wake lock if (and only if) the session is currently listening, keep-awake is on, and no lock is currently held.
- `Main` wires it all together: `handleToggle` acquires on the listening edge / releases on the idle edge, `handleSetKeepAwake` acquires/releases when the user toggles the checkbox mid-session, and `handleReset` releases the lock before clearing state. `releaseHeldWakeLock` is a no-op (just resets the UI status) when `wakeLockHeld` is `false`, so the audit trail never contains fictional release events. Every real success, error, auto-release, and explicit release is recorded as a diagnostic entry (`wake lock acquired`, `wake lock failure`, `wake lock auto-released`, `wake lock release`, `wake lock release failure`), keeping the diagnostics drawer the single source of truth for what the program did.

The `WakeLock` capability ships a `RecordingWakeLockM` test newtype that captures every request/release as a `WakeLockEvent` so the reducer + capability wiring is unit-testable without touching the browser.

## Recognition error banner (slice 8)

The reducer learns to handle `recognition.onerror` events without yet owning the actual `SpeechRecognition` instance (that wiring lands in slice 9). Slice 8 ships the pure classification logic, the reducer transitions, and the `wm-error` banner so the rest of the port can be exercised by the test hook today and dropped in as the real callback tomorrow.

- `WordMeter.RecognitionError` is a pure module that turns the raw browser error code into a typed `RecognitionErrorCode` ADT (`NotAllowed`, `ServiceNotAllowed`, `NoSpeech`, `Aborted`, `AudioCapture`, `Network`, `LanguageNotSupported`, `NoRecognitionErrorCode`, or `OtherRecognitionError String` for the long tail). Predicates `isTransient` and `isPermissionDenied` give the reducer named, testable decisions instead of string comparisons, and `recognitionErrorBannerText` renders the user-facing banner string (empty for the transient bucket, matching the legacy build's "show nothing, keep listening" behavior).
- `Session.errorBanner :: String` carries the rendered banner. It is **not** persisted — every page reload starts with an empty banner, matching the legacy build.
- The reducer adds two actions: `HandleRecognitionError Number String String` (timestamp, code, message) and `ClearErrorBanner`. `HandleRecognitionError` always records a `recognition.onerror` diagnostic with detail `code=<code or "(none)"> message=<message>`, then branches on the classified code: transient codes change nothing else, permission-denied codes also stop listening (reusing the same interval-close + event-log push the user-driven Toggle uses, with a follow-up `session ended — reason=permission denied` diagnostic), and any other non-transient code sets the banner without changing listening state. Starting a fresh counting session (the start branch of `Toggle`) and `Reset` both clear `errorBanner`, so the audit trail does not bleed across sessions.
- `Main.handleRecognitionError` dispatches the action with a clock-provided timestamp. If the dispatch flipped listening off (today: the permission-denied branch), it also releases any held wake lock so the UI does not look like it is still holding the screen.

The test hook exposes `simulateRecognitionError(code, message)` (the same code path the real `recognition.onerror` will use in slice 9a) and a `getErrorBanner()` accessor for the e2e suite.

## Real `SpeechRecognition` wiring (slice 9)

Up through slice 8 the port has no real `SpeechRecognition` instance — every transcript reaches the reducer through the test hook's `simulateFinalTranscript`. Slice 9 is the slice that actually wires up the Web Speech API so the meter counts speech in a real browser. Because the legacy build rolls three distinct features into one chunk of code (real recognition wiring, on-device language-pack pre-flight, runtime cloud fallback for `language-not-supported`), the PureScript port deliberately splits slice 9 into three smaller end-to-end slices. Each sub-slice is still independently user-visible: 9a makes the meter actually work, 9b makes it prefer the on-device path when the browser supports it, and 9c heals the one runtime failure mode that can sneak past the pre-flight.

### Slice 9a — Real cloud-path `SpeechRecognition` wired up ✅

The smallest end-to-end deliverable in slice 9: replace the test-hook-only transcript path with a real `SpeechRecognition` instance configured for cloud recognition. No on-device pre-flight, no transparent fallback path, no `processLocally` hint — just the simplest configuration that already works in every browser exposing the Web Speech API today.

- New `WordMeter.FFI.Recognition` exposes thin shims over the constructor lookup (`window.SpeechRecognition || window.webkitSpeechRecognition`), the configurable knobs (`continuous = true`, `interimResults = true`, `lang = <locale>`), the three event subscriptions (`onresult`, `onerror`, `onend`), and the `start()` / `stop()` calls. The shim never owns lifetime: the active `RecognitionInstance` lives in `ApplicationEnvironment.recognitionRef :: Ref (Maybe RecognitionInstance)`, alongside the existing `wakeLockSentinelRef`.
- New `WordMeter.Capability.Recognition` is the typeclass production code uses. `startRecognition` builds an instance, attaches the three handlers, stashes it in the env ref, and invokes `start()`; `stopRecognition` detaches the handlers, calls `stop()` (swallowing the synchronous `stop-on-stopped` exception is **not** allowed — it surfaces through a typed `RecognitionError` continuation), and clears the ref. A `RecordingRecognitionM` test newtype captures every `startRecognition` / `stopRecognition` call so the reducer wiring is unit-testable without touching the browser. The capability also exposes `recognitionApiAvailable :: m Boolean` so the rest of the program can degrade gracefully when no constructor is present (the meter still loads, the toggle still ticks, but the diagnostics drawer records `recognition unavailable` and the count never moves).
- `WordMeter.Recognition.Delta` (pure module) reproduces the legacy `integrateFinalizedTranscript` dedup logic from issue #6897. The Android Chrome bug — where continuous + interimResults emits each refinement of one utterance as a fresh finalized result carrying the cumulative transcript — is encoded as a typed decision: `classifyFinalizedTranscript :: { previous :: String, incoming :: String } -> TranscriptIntegration` returning `IgnoreDuplicate | ExtendUtterance { wordDelta :: Int, caption :: String } | StartNewUtterance { wordCount :: Int, caption :: String } | IgnoreEarlierSnapshot`. Slice 9a wires this into a new reducer action `IntegrateFinalizedTranscript Number String` that replaces the test-hook path on the production wire (the test hook keeps `InjectFinalTranscript` for tests that want to bypass dedup).
- `Main.handleToggle` becomes the orchestration boundary: on the listening edge it calls `startRecognition`, and on the idle edge it calls `stopRecognition`. The same callbacks that slice 8 plumbed for `simulateRecognitionError` are reused — `onerror` now dispatches `HandleRecognitionError` for real. `onend` schedules a 250ms restart through `Effect.Timer` if the session is still listening (legacy `RESTART_DELAY_MILLISECONDS`); the timer handle is kept in another env ref so `stopRecognition` and `Reset` can cancel it cleanly.
- The keep-awake / wake lock flow from slice 7 is unchanged: it already runs off the listening flag in the reducer, which slice 9a still owns.

When slice 9a lands, the meter counts real speech in any browser exposing `SpeechRecognition` or `webkitSpeechRecognition`. The Playwright suite continues to drive the deterministic path through the test hook, but a new sub-suite covers the `Recognition` capability wiring through a `RecordingRecognitionM` unit test.

### Slice 9b — On-device pre-flight with transparent cloud fallback

Once 9a is in production, 9b teaches `Main.handleToggle` to prefer the on-device path whenever Chromium exposes the static `SpeechRecognition.available()` / `SpeechRecognition.install()` API.

- `WordMeter.FFI.Recognition` grows two new thin shims: `onDeviceLanguagePackApiAvailable :: Effect Boolean` and `ensureOnDeviceLanguagePack :: { locale :: String, onProgress :: Effect Unit } -> Effect (Either OnDeviceUnavailable OnDeviceAvailable)` where the typed `OnDeviceUnavailable = OnDeviceApiAbsent | OnDeviceUnsupportedLanguage | OnDeviceInstallFailed String | OnDeviceAvailabilityRejected String`. The shim catches every promise rejection and packs the failure into the `Either` rather than silently resolving — same rule as `FFI.Storage` and `FFI.WakeLock`.
- The `Recognition` capability gains `prepareOnDeviceLanguagePack` (returning the same typed `Either`) and `startOnDeviceRecognition` (the on-device variant of `startRecognition` that sets `processLocally = true`).
- `Main.handleToggle` orchestrates: if the on-device API is absent, go straight to the cloud path; if it is present, call `prepareOnDeviceLanguagePack` and branch — `Right OnDeviceAvailable` starts on-device, anything else logs a diagnostic (`on-device pre-flight non-viable — falling back to cloud`) and falls through to the cloud path. The status row briefly shows `downloading on-device language pack…` while `install()` is in flight.
- The user-visible difference is silent: counts and behavior look identical, but the on-device path keeps speech off the network for users on a recent Chromium build. The diagnostics drawer is the proof that the pre-flight ran.

When slice 9b ships, the recognition status row temporarily reads `downloading on-device language pack…` while the model is being installed, and the diagnostics drawer carries a `recognition` entry naming the path that was selected (`on-device pre-flight viable — starting on-device`, `on-device pre-flight non-viable — falling back to cloud`, or `on-device API absent — falling back to cloud`). The `Session.recognitionStatusOverride` field carries the transient status text and is cleared by every stop transition (Toggle-stop, permission-denied error, Reset) so a stale `downloading…` cannot outlive a listening session. In test environments, setting `window.__WM_DISABLE_ON_DEVICE_PREFLIGHT__ = true` before loading the bundle short-circuits the pre-flight to the cloud path, keeping the Playwright suite deterministic; the e2e fixture sets that flag.

### Slice 9c — Runtime `language-not-supported` retry

The on-device pre-flight cannot catch every browser bug — some Chromium builds resolve `available({langs, processLocally: true})` to `'available'` and then reject `start()` at runtime with `error = 'language-not-supported'`. Slice 9c teaches the reducer + recognition layer to retry exactly once on the cloud path when this happens.

- A new `Session.cloudFallbackAttempted :: Boolean` field guards the retry so a misbehaving browser cannot enter an infinite reconfiguration loop.
- `HandleRecognitionError` keeps its existing classification (it already handles `LanguageNotSupported` through the banner path in slice 8). Slice 9c adds a `Main.handleRecognitionError` branch: when the code classifies as `LanguageNotSupported`, the session is currently listening, the active recognition path is on-device, and `cloudFallbackAttempted` is `false`, the orchestrator stops the current recognition, sets the flag, and starts a fresh cloud-path recognition — all without the user seeing an error banner. Every step is diagnostic-logged (`language-not-supported at runtime — falling back to cloud`).
- The legacy build resets `cloudFallbackAttempted` on every Toggle-to-start; the PureScript port does the same through the `Toggle` reducer branch.

When slice 9c lands, the port has full parity with the legacy build's recognition layer, and slice 10 (cutover) becomes safe to land.

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
- `getDiagnosticsDrawerOpen()` — whether the diagnostics drawer is currently open (mirrors `Session.diagnosticsDrawerOpen`).
- `toggleDiagnosticsDrawer()` — dispatches `SetDiagnosticsDrawerOpen (not current)` through `handleToggleDiagnosticsDrawer`; same code path the summary click takes.
- `reset()` — same code path the reset button takes, including the `window.confirm` prompt; tests that want to skip the prompt should use `resetAt` instead.
- `resetAt(timestamp)` — dispatches a `Reset` action at the given clock value, bypassing the confirmation dialog; clears persisted state via the `Storage` capability.
- `persistNow()` — force-persists the current session through the `Storage` capability without waiting for the next reducer action.
- `getKeepAwake()` / `setKeepAwake(boolean)` — read or write the keep-awake preference; `setKeepAwake` goes through the same `handleSetKeepAwake` path the rendered checkbox uses, so it also acquires or releases the wake lock if the session is currently listening.
- `getKeepAwakeStatus()` — current value of the keep-awake status span (empty, `"screen will stay on"`, or an `(unavailable: …)` reason).
- `getWakeLockHeld()` — whether the program currently holds a wake-lock sentinel.
- `simulateVisibilityVisible()` — same code path the document-level `visibilitychange → 'visible'` listener takes; lets tests verify re-acquisition without driving real visibility events.
- `simulateRecognitionError(code, message)` — pushes a `recognition.onerror` event through the reducer; same code path the real `SpeechRecognition.onerror` callback will use in slice 9.
- `getErrorBanner()` — current value of the `wm-error` banner span; `""` when idle.

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
- `wm-diagnostics` — collapsible `<details>` drawer; collapsed by default, opens on a tap of the summary. The open/closed state is tracked in `Session.diagnosticsDrawerOpen` (action `SetDiagnosticsDrawerOpen Boolean`) so it survives rerenders triggered by word-count updates or other state changes.
- `wm-diagnostics-toggle` — the `<summary>` row labelled `🔧 Diagnostics`. Clicking it dispatches `SetDiagnosticsDrawerOpen (not session.diagnosticsDrawerOpen)` so the open/closed state is held in the reducer, not only in the browser's native `<details>` toggle (which is reset on every full DOM replacement).
- `wm-diagnostics-copy` — the `📋 Copy diagnostics` button. On click the meter calls `navigator.clipboard.writeText` with the rendered text and updates `wm-diagnostics-copy-status` with `Copied!` on success or `Copy failed: <reason>` on failure (including when the Clipboard API is unavailable).
- `wm-diagnostics-copy-status` — a span next to the copy button, empty until the first copy attempt completes.
- `wm-diagnostics-content` — a `<pre>` containing the formatted diagnostics text: an environment snapshot prefix (`version`, `userAgent`, `navigator.language`) followed by the rolling event log capped at `diagnosticsLimit` (60) entries. Each event line is `<clock-time>  <label>[ — <detail>]`.
- `wm-keep-awake` — `<input type="checkbox">` controlling whether the meter requests a Screen Wake Lock when listening starts. Defaults to **checked** on every page load (the preference is deliberately not persisted — the legacy build behaves the same way). Disabled while listening.
- `wm-keep-awake-label` — the surrounding `<label>` (also acts as the click target for the checkbox).
- `wm-keep-awake-status` — a status span next to the checkbox. Empty when idle; `"screen will stay on"` after a successful acquisition; `"(wake lock not supported on this browser)"` or `"(wake lock unavailable: <reason>)"` when the request fails.
- `wm-error` — `role="alert"` banner that surfaces non-transient recognition errors. Empty when idle; populated with `"Microphone permission denied. Allow microphone access and try again."` on `not-allowed` / `service-not-allowed`, `"Network error reaching the speech service. Check your connection and try again."` on `network`, `"Recognition error: <code>"` on any other code (and `"Recognition error: unknown"` when the browser supplied no code), and stays empty for the transient codes `no-speech` / `aborted` / `audio-capture`. Cleared on the next Start (Toggle on→idle→on) and on Reset.
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
| 7     | Wake lock + keep-awake toggle                                                                           | ✅ Done    |
| 8     | Permission denied + transient-error banner                                                              | ✅ Done    |
| 9a    | Real cloud-path `SpeechRecognition` wired up (start / stop / result / error / end + auto-restart)       | ✅ Shipped |
| 9b    | On-device pre-flight with transparent cloud fallback (static `available()` / `install()` API)           | ✅ Shipped |
| 9c    | Runtime `language-not-supported` retry on the cloud path (one-shot per session)                         | ✅ Shipped |
| 10    | Cutover — point `content/tools/word-meter.md` at the PureScript build, retire legacy JS + sandbox tests | ⏳ Pending |

## Build, test, bundle

- `npm run build:ps` — rebuild `quartz/static/word-meter-ps.js`.
- `npm run clean:ps` — wipe PureScript build artifacts.
- `npm run test:ps` — `spago test` unit suite (covers the pure rate math: `formatRate`, `formatDurationMs`, `ratePerMinute`, end-to-end reducer runs through `Toggle`/`InjectFinalTranscript`/`Tick`, the slice-4 event-log reducer behavior for completed counting sessions including stop pushes, stop/restart preservation and cap eviction, the slice-2 caption time-decay including pruning past the 30s window and the linear opacity fade, and the slice-5 diagnostics behavior: per-action entry recording, `diagnosticsLimit` cap, `formatDiagnostics` snapshot prefix and placeholder, and the `SetCopyStatus` reducer case).
- `npm run test:e2e` — Playwright suite against the current PureScript bundle.

## Optional improvement backlog

The following improvements are recommended based on a review against PureScript best practices (see [`specs/purescript-best-practices.md`](./purescript-best-practices.md)) and the repo's engineering principles. None are required for feature parity; they are listed here for future work with supporting rationale and trade-offs.

### Split `Recording.purs` into focused modules

**What:** `Recording.purs` currently owns session types, the `Action` ADT, the pure reducer, the view function, all `build*` view helpers, rate math, duration formatting, caption helpers, caption opacity, and persisted-data projection. This is roughly 1 000 lines and five distinct responsibilities in one file.

**Why:** The module boundary is the unit of reuse and discoverability. A reader looking for rate math must scan through view helpers. A reader looking for the reducer must scroll past formatting functions. Splitting into `Recording.Session` (types + `initialSession`), `Recording.Reducer` (actions + `reduce`), `Recording.View` (view + all `build*`), and `Recording.Math` (rate calculations + formatters) gives each concern its own search space and allows future changes to land in a smaller diff.

**Trade-offs:** Pure rename refactor — no behavior change. Adds several module files. Imports in `Main.purs`, `TestHook.purs`, and `Test.Main.purs` will need updating. PureScript's structural typing means the split is safe as long as all re-used types (like `Session`) stay in one canonical location.

**Complexity:** Medium. Safe automated refactor; most of the work is reorganizing imports.

---

### Introduce a `Timestamp` newtype

**What:** Replace raw `Number` timestamps (the argument to `Toggle`, `Tick`, `RecordDiagnostic`, etc.) with a `newtype Timestamp = Timestamp Number` defined in a dedicated module.

**Why:** `Number` is used for multiple distinct concepts in the codebase — timestamps, durations, word rates, and opacity fractions. A `Timestamp` newtype makes function signatures self-documenting and prevents accidentally passing a duration (also `Number`) where a timestamp is expected. Cost at runtime: zero (newtypes are erased).

**Trade-offs:** Requires touching every Action constructor and every reduce case that pattern-matches on a timestamp. Tests that hardcode numeric timestamps would need `Timestamp` wrappers. The benefit compounds as the codebase grows.

**Complexity:** Medium. Mechanical transformation; the compiler guides every change site.

---

### Introduce a `Locale` newtype

**What:** Replace raw `String` locale values with `newtype Locale = Locale String`.

**Why:** Locale strings are passed from `captureEnvironmentSnapshot` through `sessionLocale` to every `startRecognition` call. Wrapping them in a newtype documents their role, prevents silent coercion with unrelated strings (e.g. diagnostic labels), and makes the type signature of `recognitionHandlersFor` self-explanatory.

**Trade-offs:** Small lift; the locale string is produced in one place and consumed in a few. The `Locale` newtype would need `renderLocale :: Locale -> String` for the diagnostic log lines that embed the locale in detail strings.

**Complexity:** Low.

---

### Elide `persistAfterAction` with a `shouldPersist` predicate

**What:** `persistAfterAction` is an exhaustive case dispatch where 17 of 19 branches return `pure unit`. An alternative is a pure predicate `shouldPersist :: Action -> Boolean` (returning `true` only for `Toggle`, `InjectFinalTranscript`, `IntegrateFinalizedTranscript`, and `Reset`) plus a single `when (shouldPersist action) persistCurrentSession` call.

**Why:** The current exhaustive match is intentional — the compiler forces a decision for every new action. A `shouldPersist` predicate preserves the exhaustiveness guarantee if it is also an exhaustive case expression, and collapses 19 lines into 5.

**Trade-offs:** The exhaustive match is a living checklist that tells readers exactly what each action does to storage. The predicate style is more concise but slightly less explicit. Either approach is safe as long as the new `Action` variant gets a case in the predicate.

**Complexity:** Low.

---

### Share `collapseWhitespaceToSpace` between `Words` and `Recognition.Delta`

**What:** `Words.purs` contains a private `collapseWhitespaceToSpace` helper (tab/newline/carriage-return → space). `Recognition.Delta.normalizeTranscript` repeats the same three `replaceAll` calls inline. Exporting `collapseWhitespaceToSpace` from `Words.purs` (or moving it to a shared `WordMeter.Text` module) removes the duplication.

**Why:** Two copies of the same transformation can drift independently. If a new whitespace character (e.g. `\u00A0` non-breaking space) needs handling, it must be added in two places. A single canonical function eliminates the risk.

**Trade-offs:** Exporting a helper from `Words` slightly widens its public API. Alternatively, a small `WordMeter.Text` module could own both the whitespace helper and `countWords`, giving `Words` a natural home. Either approach is safe — both modules are pure, with no FFI dependencies.

**Complexity:** Low.

---

### Replace `Boolean` wake-lock + status flags with a `WakeLockState` ADT

**What:** `Session` currently uses `wakeLockHeld :: Boolean` combined with `keepAwakeStatus :: String` to encode the wake-lock lifecycle. Replace both with a single `data WakeLockState = WakeLockIdle | WakeLockHeld | WakeLockFailed String` field.

**Why:** A `Boolean` combined with a `String` can represent impossible states (e.g. `held = false` + status `"screen will stay on"`). The ADT makes impossible states unrepresentable and gives the reducer a single field to update on each transition instead of two fields that must be kept in sync.

**Trade-offs:** Requires updating the reducer, the view (`keepAwakeAttributes`, the status span), the test hook (`getWakeLockHeld`, `getKeepAwakeStatus`), and all e2e tests that read those selectors. The `keepAwake :: Boolean` preference field (user-controlled) is separate and unaffected.

**Complexity:** Medium. Pure rename; no behavior change once the ADT is wired.

---

### Add property-based tests for pure functions

**What:** The pure functions `formatRate`, `formatDurationMs`, `ratePerMinute`, `captionOpacity`, `normalizeTranscript`, and `classifyFinalizedTranscript` all have clear algebraic properties that are currently tested only with a handful of specific examples.

**Why:** Property-based tests (via `purescript-quickcheck`) find edge cases that hand-written examples miss. For instance, `formatRate (ratePerMinute n d) >= 0` for all finite `n` and `d`, and `normalizeTranscript (normalizeTranscript s) == normalizeTranscript s` (idempotence).

**Trade-offs:** Requires adding `purescript-quickcheck` to `spago.yaml`. Test run time increases modestly. The investment pays off most in functions with complex case splits (`formatRate` has four branches, `classifyFinalizedTranscript` has four).

**Complexity:** Low to medium depending on how many generators need to be written.
