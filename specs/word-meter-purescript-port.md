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
    Recording/
      Session.purs           session types (Session, Caption, WordEvent, LoggedInterval, PersistedData), WakeLockState ADT, initialSession, constants
      Math.purs              pure rate calculations (wordsPerMinute, shortRate, longRate, overallRate, captionOpacity) + formatters (formatRate, formatDurationMs)
      Reducer.purs           Action ADT, Dispatch / Handlers types, reduce, toPersistedData, private caption/event helpers
      View.purs              view entry point + all build* helpers + diagnosticsText
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
- `cloudFallbackAttempted` is also set whenever `startRecognitionForSession` settles on the cloud path without ever attempting the on-device recognizer (static `onDeviceLanguagePackApiAvailable = false`, or the pre-flight returned `Left`). Once set, the flag survives Toggle-to-stop / Toggle-to-start and a page reload via `Persistence`; only `Reset` clears it. This is the "only attempt on-device once at start up, do not try again until stats reset" rule from the v0.1.1 issue — without it, every auto-restart of the recognizer (every couple of seconds in normal use) would re-run the pre-flight and re-log the diagnostic.

When slice 9c lands, the port has full parity with the legacy build's recognition layer, and slice 10 (cutover) becomes safe to land.

### v0.1.1 fixes — live tick, post-reload stats, one-shot on-device

Three regressions reported against the PureScript build that ship in v0.1.1:

- **Live tick driver.** The legacy `word-meter.js` runs `setInterval(handleTick, 200)` while listening so the rate tiles, duration, and trailing-window calculations refresh against the real wall clock even when no transcript callback has fired in a while. The port did not install this interval, so the rate tiles only updated on the next user-driven dispatch. v0.1.1 introduces a `WordMeter.Capability.Ticker` typeclass with `startTickerInterval` / `stopTickerInterval`, backed by `FFI.Timer.scheduleAtIntervals` / `cancelInterval` and an `IntervalHandle` ref in `ApplicationEnvironment`. `handleToggle` starts the interval on the listening edge and cancels it on the idle edge; `handleReset` and the permission-denied branch also cancel.
- **Post-reload sanity.** `Session.completedActiveMs` and `Session.cloudFallbackAttempted` are now part of `PersistedData` and round-trip through `WordMeter.Persistence` (decoded with `.:?` so v1 payloads written before v0.1.1 still load, defaulting to `0.0` / `false`). After `LoadSession` runs in `startApplication`, the orchestrator immediately dispatches `Tick currentTimeMillis` so `Session.now` reflects the real wall clock rather than `epochInstant` (the Jan 1 1970 default). Without these two pieces, `overallRate` divided by a denominator of ~1 ms after a reload and the trailing-window rates blew up by similar factors.
- **One-shot on-device pre-flight.** As described above for slice 9c, `cloudFallbackAttempted` is now set in every branch of `startRecognitionForSession` that lands on the cloud path, persisted across reloads, and consulted at the very top of `startRecognitionForSession` to skip the pre-flight outright once the decision has been made. The `Toggle` reducer no longer clears the flag.

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

## Vdom scroll preservation

`WordMeter.Vdom.mount` rebuilds the host's subtree from scratch on every reducer dispatch (no diff algorithm — the renderer is a function from `Session` to `Node` followed by a full DOM replacement). On its own, that strategy would reset every native scrollbar — for example the diagnostics `<pre>` (`wm-diagnostics-content`, `max-height: 320px; overflow-y: auto`) and the event-log timeline (`wm-event-log`, `max-height: 220px; overflow-y: auto`) — every time the model changes (a Tick, a transcript, a wake-lock state update, …). The view layer never opts elements in: `mount` walks the existing tree for descendants carrying a `data-testid` attribute, captures any non-zero `(scrollTop, scrollLeft)` into an opaque `ScrollSnapshot` handle, clears the host, renders the new tree, then restores each entry by looking up the matching testid in the new tree. This reuses the same stable-identity convention that the e2e test contract already relies on and means every current and future scrollable element with a testid is preserved automatically. The same mechanism is what keeps the `<details>` drawer open across rerenders mirrored through `Session.diagnosticsDrawerOpen` complete: model-level state for things the reducer cares about (drawer open/closed), DOM-level preservation for things that are purely view ephemera (scroll position).

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
| 10    | Cutover — point `content/tools/word-meter.md` at the PureScript build, retire legacy JS + sandbox tests | ⏳ Planned (see [Slice 10 — cutover plan](#slice-10--cutover-plan)) |

## Build, test, bundle

- `npm run build:ps` — rebuild `quartz/static/word-meter-ps.js`.
- `npm run clean:ps` — wipe PureScript build artifacts.
- `npm run test:ps` — `spago test` unit suite (covers the pure rate math: `formatRate`, `formatDurationMs`, `wordsPerMinute`, end-to-end reducer runs through `Toggle`/`InjectFinalTranscript`/`Tick`, the slice-4 event-log reducer behavior for completed counting sessions including stop pushes, stop/restart preservation and cap eviction, the slice-2 caption time-decay including pruning past the 30s window and the linear opacity fade, and the slice-5 diagnostics behavior: per-action entry recording, `diagnosticsLimit` cap, `formatDiagnostics` snapshot prefix and placeholder, and the `SetCopyStatus` reducer case).
- `npm run test:e2e` — Playwright suite against the current PureScript bundle.

## Optional improvement backlog

The following improvements are recommended based on a review against PureScript best practices (see [`specs/purescript-best-practices.md`](./purescript-best-practices.md)) and the repo's engineering principles. None are required for feature parity; they are listed here for future work with supporting rationale and trade-offs.

### ✅ Split `Recording.purs` into focused modules

**Done in this PR.** The monolithic `Recording.purs` (≈ 1 000 lines, five responsibilities) has been split into four focused modules under a `WordMeter.Recording.*` namespace:

- `WordMeter.Recording.Session` — session types (`Session`, `Caption`, `WordEvent`, `LoggedInterval`, `PersistedData`), the `WakeLockState` ADT, `initialSession`, all constants, and idle/default string values.
- `WordMeter.Recording.Math` — pure rate calculations (`wordsPerMinute`, `shortRate`, `longRate`, `overallRate`, `wordsInTrailingWindow`, `wallSpanMs`, `activeListeningMs`, `intervalDurationMs`, `intervalRate`, `captionOpacity`) and formatters (`formatRate`, `formatDurationMs`).
- `WordMeter.Recording.Reducer` — the `Action` ADT, `Dispatch` and `Handlers` type aliases, the `reduce` function, `toPersistedData`, and all private caption/event-pruning helpers.
- `WordMeter.Recording.View` — the `view` entry point, all `build*` helper functions, `diagnosticsText`, and `renderStatus`.

The old `WordMeter.Recording` module is deleted; consumers import directly from the appropriate sub-module. Imports in `AppM.purs`, `Persistence.purs`, `Capability/Storage.purs`, `Capability/SessionState.purs`, `Main.purs`, `TestHook.purs`, and `Test.Main.purs` are updated accordingly. No behavior change.

---

### ✅ Use `Data.DateTime.Instant` for timestamps

**Done in a previous PR.** Every `Action` that carries a timestamp (`Toggle`, `Tick`, `RecordDiagnostic`, `HandleRecognitionError`, `IntegrateFinalizedTranscript`, …) now takes `Data.DateTime.Instant` from the `purescript-datetime` package. `Data.Time.Duration.Milliseconds` carries durations (e.g. `Session.completedActiveMs`). `WordMeter.Recording.Math.millisecondsBetween :: Instant -> Instant -> Number` wraps `diff` + `unwrap` so rate expressions stay readable. The `FFI/Clock.purs` boundary converts the raw `Number` returned by `Date.now()` through `millisToInstant`, falling back to `epochInstant` only on the astronomical out-of-range corner case. Test helpers `testInstant`/`instantMs` cover the `Number ↔ Instant` round trip in `Test.Main`.

---

### ✅ Introduce a `Locale` newtype

**Done in this PR.** New `WordMeter.Locale` module exposes `newtype Locale = Locale String` with `deriving Eq` and `renderLocale :: Locale -> String`. `RecognitionHandlers.locale`, `prepareOnDeviceLanguagePack`, and `RecognitionEvent` record fields are now `Locale` instead of `String`. `Main.defaultLocale` and `sessionLocale` produce `Locale` values; every diagnostic log line that embeds the locale calls `renderLocale`. The FFI boundary (`FFI.constructRecognitionInstance`, `FFI.ensureOnDeviceLanguagePack`) unwraps via `renderLocale` immediately before crossing into JavaScript.

---

### ✅ Elide `persistAfterAction` with a `shouldPersist` predicate

**Done in this PR.** Extracted `shouldPersistSession :: Action -> Boolean` — an exhaustive, no-wildcard predicate that returns `true` only for `Toggle`, `InjectFinalTranscript`, and `IntegrateFinalizedTranscript`. `persistAfterAction` now guards on the predicate for persist, handles `Reset` (clear) in a single explicit case, and returns `pure unit` for everything else. The compiler still catches every new action constructor at the predicate level; no behavior change.

---

### ✅ Share `collapseWhitespaceToSpace` between `Words` and `Recognition.Delta`

**Done in a previous PR.** `Words.purs` contained a private `collapseWhitespaceToSpace` helper (tab/newline/carriage-return → space). `Recognition.Delta.normalizeTranscript` repeated the same three `replaceAll` calls inline. Both now import the function from the new `WordMeter.Text` module, eliminating the duplication. Any future whitespace-handling change (e.g. adding `\u00A0` non-breaking space) now has a single canonical location.

---

### ✅ Replace `Boolean` wake-lock + status flags with a `WakeLockState` ADT

**Done in this PR.** `Session` now has `wakeLockState :: WakeLockState` in place of the former `wakeLockHeld :: Boolean` + `keepAwakeStatus :: String` pair. The new `data WakeLockState = WakeLockIdle | WakeLockHeld | WakeLockFailed String` ADT makes impossible combinations (e.g. `held = false` while status reads "screen will stay on") unrepresentable. `renderWakeLockStatus :: WakeLockState -> String` drives the status text in the view. The `SetKeepAwakeStatus` and `SetWakeLockHeld` actions are replaced by a single `SetWakeLockState WakeLockState`. `TestHook.getWakeLockHeld` and `getKeepAwakeStatus` are derived from `wakeLockState` for e2e backward compatibility. The `keepAwake :: Boolean` user preference field is untouched.

---

### ✅ Add property-based tests for pure functions

**Done in this PR.** Added `purescript-quickcheck` to the test dependencies in `spago.yaml` and `spago.lock`. Seven new `quickCheck`-driven properties cover the pure functions with the most branching logic. Properties are iterated with `sequence_` over a list of `quickCheck propN` calls. Each property name describes the invariant it verifies; no inline comments are needed.

- `formatRateContainsDigit` — `formatRate` always returns a string containing at least one digit.
- `formatDurationContainsDigit` — `formatDurationMs` always returns a string containing at least one digit.
- `captionOpacityIsInRange` — `captionOpacity` always returns a value in `[minimumCaptionOpacity, 1.0]`.
- `captionOpacityAtSameTimestampIsOne` — `captionOpacity ts ts == 1.0` for all timestamps.
- `wordsPerMinuteIsZeroWhenNoWords` — `wordsPerMinute 0 elapsed == 0.0` for any elapsed time.
- `wordsPerMinuteIsNonNegative` — `wordsPerMinute` with non-negative inputs always returns a non-negative rate.
- `wordsPerMinuteAtOneMinuteEqualsWordCount` — `wordsPerMinute n 60000.0 == toNumber n` (the definitional identity at exactly one minute elapsed).

## Comparative analysis — JS vs. PureScript builds

A walk-through of the legacy `quartz/static/word-meter.js` against the current PureScript bundle reveals that every user-visible feature has parity. The differences below are catalogued so the cutover PR can address (or knowingly accept) each one rather than discover them in production.

### Parity matrix

- Start / stop counting, toggle button label, status text, listening / idle state machine: parity.
- Live word count and live rate tiles (short / long / overall): parity. The PureScript build drives them through the same 200 ms tick interval (`WordMeter.Capability.Ticker`).
- Captions strip with 30 s window and linear opacity fade: parity. Both prune past `captionWindowMs` on every action and clamp opacity to `minimumCaptionOpacity = 0.15`.
- Event log of completed counting sessions, capped at 200 entries, persisted: parity.
- Diagnostics drawer with collapsible `<details>`, environment snapshot prefix, rolling 60-entry log, and copy-to-clipboard button: parity.
- Wake lock + keep-awake checkbox, visibility-driven re-acquisition, status text after acquisition / failure / auto-release: parity.
- Recognition-error banner with the same code classification (`not-allowed`, `service-not-allowed`, `no-speech`, `aborted`, `audio-capture`, `network`, `language-not-supported`, generic): parity.
- Real cloud-path `SpeechRecognition` with 250 ms auto-restart on `onend`: parity.
- On-device pre-flight via `SpeechRecognition.available()` / `install()` with transparent cloud fallback: parity.
- One-shot cloud-fallback on runtime `language-not-supported`: parity.
- Reset button + `window.confirm` prompt + clears persisted snapshot: parity.
- Persistence round-trip: parity for shape (`totalWords`, `firstStartedAt`, word events, event log) plus the PureScript-only additions described below.

### Product-visible differences worth knowing at cutover

These are intentional improvements the PureScript build carries; they are not regressions, but they matter for the cutover plan.

1. **`localStorage` key**. The JavaScript build writes to `word-meter:state:v1`. The PureScript build writes to `word-meter-ps:state:v1` (to allow the two builds to coexist during the port). Without migration, every existing user starts at zero on the first page load after cutover. The cutover plan covers a one-shot read from the legacy key into the PureScript shape.
2. **Persisted fields**. The PureScript build persists `completedActiveMs` and `cloudFallbackAttempted` in addition to the legacy fields, so post-reload rates and on-device pre-flight obey the v0.1.1 rules. The legacy build silently lost `completedActiveMs` across reloads and re-ran the on-device pre-flight every recognizer auto-restart. Both PureScript-only fields decode with `.:?` defaults so legacy v1 payloads still load.
3. **Version string**. JS = `0.1.0`. PureScript = `0.1.1`. The bump captures the live-tick driver, post-reload sanity, and one-shot on-device pre-flight (the v0.1.1 fixes). The footer and diagnostics drawer render the value verbatim.
4. **Clipboard fallback path**. JS falls back to a hidden `<textarea>` + `document.execCommand('copy')` when `navigator.clipboard.writeText` is unavailable. PureScript surfaces a `Copy failed: Clipboard API unavailable` status instead. Modern Chromium / Safari / Firefox all support `navigator.clipboard.writeText` on `https://` origins, so this only matters for very old browsers — which already cannot use the Web Speech API the meter depends on.
5. **Copy-status copy**. JS = `copied!` / `copy failed — long-press the log to select`. PureScript = `Copied!` / `Copy failed: <reason>`. The information conveyed is equivalent; the wording differs in tone (sentence-case vs. lower-case) and the legacy build's mobile-only hint about long-pressing the log is not echoed.
6. **Per-event `console.log`**. JS mirrors every diagnostic entry to `console.log` so the devtools console doubles as a tail of the diagnostics drawer. The PureScript build does not. The diagnostics drawer itself still carries the full log, the copy button still hands it back, and the on-screen event log still records every counting session — only the devtools mirror is gone.

### Recommended follow-up work (in priority order)

1. **Persisted-state migration at cutover** (REQUIRED). Read the legacy `word-meter:state:v1` key once at startup when the PureScript key is absent, decode it through `WordMeter.Persistence` with `.:?` defaults for the new fields, write it back under the PureScript key, and delete the legacy key. Without this, every existing user resets their stats on the cutover deploy.
2. **Optional: console mirror of diagnostics**. Add a `console.log` call inside the `RecordDiagnostic` reducer path (or, more cleanly, a `Capability.Log` typeclass with an `AppM` instance that calls `Effect.Console.log` and a `RecordingLogM` test newtype). Helps with field debugging without opening the drawer.
3. **Optional: clipboard fallback parity**. If field reports show users on browsers without `navigator.clipboard`, add a one-shot `<textarea>` + `document.execCommand('copy')` fallback inside `FFI.Clipboard`. Likely never needed — the meter requires a recent browser to function at all.
4. **Optional: copy-status hint for long-press**. If mobile users report not knowing how to copy when the API fails, append the legacy build's `(long-press the log to select)` hint to the failure message.

## Reflection on the migration

### What we gained

- **A vocabulary of impossible states.** The headline win was deleting whole categories of bugs by making them unrepresentable. `WakeLockState = WakeLockIdle | WakeLockHeld | WakeLockFailed String` made it impossible for the held-flag and the status text to disagree. `RecognitionPath = OnDevicePath | CloudPath` made it impossible to forget which path a session is on. `RecognitionErrorCode` made `is-permission-denied?` a typed predicate instead of a string comparison the compiler cannot check. None of these are accidents — they came from listening to the bugs the JavaScript build had already shipped and then encoding the invariant we wanted into the type.
- **A capability stack that is genuinely swappable.** Every effect this app needs lives behind a typeclass with an `AppM` instance and at least one test newtype. The reducer + orchestrator code is generic in `m`; the test suite drives the whole orchestrator under deterministic test newtypes that never touch the browser. The cost of the abstraction is the boilerplate of two implementations per capability; the payoff is unit tests that cover code paths (visibility re-acquisition, wake-lock failure, recognition auto-restart) that were untestable in JavaScript without a real browser.
- **A pure reducer that is easy to reason about.** The `WordMeter.Recording.Reducer.reduce` function takes an `Action` and a `Session` and returns a new `Session`. Every transition is a pattern match on the action, every transition is verifiable in `Test.Main`, and every transition is small. The legacy build's `endListening`, `beginListening`, and `integrateFinalizedTranscript` were imperative routines that touched session, recognition, wake-lock, and UI state in a single function — easy to write, hard to test.
- **Property-based tests.** `quickCheck` covers seven invariants over the pure math (rate formatters, opacity range, words-per-minute definitional identity). These properties caught a divide-by-near-zero bug post-reload before it shipped — that fix became part of v0.1.1.
- **A typed FFI boundary.** Every JavaScript shim is thin (no state, no decisions), and every fallible boundary returns `Either <DomainError> a`. The `Storage`, `Clipboard`, `WakeLock`, `Recognition`, `Confirm`, and on-device pre-flight FFIs all hand structured outcomes back to PureScript. The diagnostics drawer carries every failure verbatim. The "never silently swallow errors" rule from `AGENTS.md` is enforced by the FFI contract, not by reviewer vigilance.

### What we learned

- **Slicing vertically pays.** Every slice from 1 through 9c delivered end-to-end user-visible functionality. We never built a horizontal layer (a Vdom library, a capability stack, a persistence module) as a slice on its own; each one grew in service of the feature that needed it. The Vdom started as a "render a button and a count" sketch in slice 1 and grew into typed scroll preservation by the time slice 9b needed `<details>` to stay open. The Storage capability appeared in slice 6 because that is when persistence shipped. This kept the port shippable every Friday.
- **The compiler is a refactoring tool.** Splitting `Recording.purs` into four modules, introducing `Instant` everywhere, introducing the `Locale` newtype, replacing two boolean flags with `WakeLockState`: every one of these refactors landed without a single runtime regression because the compiler walked us to every call site. The legacy build's equivalent refactor would have required a global grep and a prayer.
- **FFI shims must be thin.** Slice 7 originally shipped a JavaScript wake-lock shim that owned the active sentinel, decided what "auto-release" meant, and silently swallowed release failures. The code review caught it and the fix moved every decision into PureScript: the JavaScript shim now exposes five thin foreign imports with no state. The convention generalizes — every later FFI shim (`Recognition`, `Confirm`, `Storage`, `OnDeviceLanguagePack`) follows it.
- **Test newtypes are worth their weight.** `RecordingClipboardM`, `RecordingWakeLockM`, `RecordingRecognitionM`, `StubEnvironmentM`, `FixedClockM`, `StatefulSessionM`, `InMemoryStorageM` — every one of these started as a unit test and ended as a verification that the production wiring does exactly what we say it does. They are also the cheapest way to drive every branch of `Main.handleRecognitionError`'s 9c retry logic.
- **Capture the invariant in the type, not in the comment.** Wherever the port introduced a typed ADT for what JavaScript was modelling as a string or a pair of booleans, the comment that used to explain "remember, this is only valid when …" disappeared with the impossible state.

### What to carry forward

- **The capability pattern travels.** Any future browser-targeted PureScript app in this repo should start with the same shape: pure reducer over a typed `Action` ADT, capabilities behind typeclasses, `AppM = ReaderT Env Effect` newtype, test newtypes per capability. See `specs/purescript-capability-pattern.md` for the canonical walkthrough.
- **The Vdom is small enough to copy.** `WordMeter.Vdom` is ~250 lines and renders a full app with scroll preservation. Future tools that need a single-component browser surface can copy it rather than reach for a framework. The trade-off (full subtree replacement on every dispatch) is fine for an app this size and is genuinely simpler than diffing.
- **Vertical slices belong in every port.** When the next legacy module is ported, the slice plan should look exactly like this one: a numbered list of user-visible slices, each independently shippable, each independently testable through the same selector contract the legacy build honors.
- **Diagnostics drawer is non-negotiable.** Every web-facing tool in this repo should ship a rolling diagnostics log with a copy button. Field bug reports turn from "the meter is broken" into a stack of evidence that names the path the program took.
- **The cutover plan is part of the port spec.** The plan for slice 10 (below) is documented inside this spec rather than scattered across issue comments so the next person who reads the spec knows what is left to do.

## Slice 10 — cutover plan

Slice 10 is intentionally subtractive: the PureScript build already passes every Playwright contract, and the JavaScript build is the redundant copy. The plan below is the proposed shape for the cutover PR; the tracking issue lives separately so it can host discussion before the PR opens.

### Pre-flight checks

1. Confirm the current PureScript bundle still passes `npm run test:ps` and `npm run test:e2e` against the production fixture.
2. Confirm the version string in `WordMeter.Version` is at the value the cutover should ship (likely `0.1.2`, bumped to mark the cutover itself).

### Required behavior change before subtraction

3. Add a one-time legacy-key migration in `WordMeter.Main.startApplication`: before the regular `load`, check whether the PureScript key (`word-meter-ps:state:v1`) is absent **and** the legacy key (`word-meter:state:v1`) is present. If both, decode the legacy payload through `WordMeter.Persistence` (the v1 envelope matches; only the new `completedActiveMs` and `cloudFallbackAttempted` fields default), write it back under the PureScript key, delete the legacy key, and record a `persisted state migrated from legacy build` diagnostic. Single shot, runs once per user. Add a `RecordingStorageM` unit test that covers the three branches (no legacy key, legacy key present, both keys present).

### Subtractive changes

4. Update `content/tools/word-meter.md`: change the `<script src="/static/word-meter.js"></script>` line to `<script src="/static/word-meter-ps.js"></script>`. This is the single user-visible cutover line.
5. Delete `quartz/static/word-meter.js`. (`word-meter.css` stays — both builds use the same stylesheet.)
6. Delete `quartz/static/word-meter.test.mjs` if it exists and is the legacy-only sandbox suite (the Playwright suite at `tests/e2e/word-meter.spec.ts` is implementation-agnostic and stays).
7. Update `tests/e2e/fixtures/word-meter.html` to drop the `?build=js` branch. The fixture loader becomes a single unconditional `script` tag pointing at `word-meter-ps.js`. Delete the `?build=js` query-string handling from `tests/e2e/word-meter.spec.ts` if any tests still reference it.

### Documentation pass

8. Update this spec: change the slice 10 row to `✅ Shipped`, replace the "JavaScript build coexists" framing in the intro paragraph with the post-cutover wording (the PureScript build *is* Word Meter; the JS build is gone), and move the "Comparative analysis" section into past tense or delete it (since there is no longer a JS build to compare against).
9. Update `specs/word-meter.md` if it still mentions the dual-build coexistence.
10. Update `README.md` if it mentions either build by name.
11. Write the ai-blog post for the cutover in `ai-blog/`.

### Acceptance

The PR is ready to land when, on a fresh browser profile:

- `https://bagrounds.org/tools/word-meter` serves the PureScript bundle and only the PureScript bundle.
- An existing user's `localStorage` survives the upgrade: their `totalWords`, event log, and `firstStartedAt` are preserved.
- A fresh user starts at zero.
- The Playwright suite (`npm run test:e2e`) passes against the post-cutover fixture.
- The PureScript unit suite (`npm run test:ps`) passes, including the new migration test.
