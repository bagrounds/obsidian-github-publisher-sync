---
share: true
title: "🎙️ Word Meter Spec"
---

# 🎙️ Word Meter Spec

The Word Meter is a single-page browser tool that listens to ambient speech via the Web Speech API and counts the words it hears. It lives at `/tools/word-meter` (rendered from `content/tools/word-meter.md`) and is implemented entirely in `quartz/static/word-meter.js`. There is no server, no upload from this page, no account, and no cost.

## Goals

- Tap a single button to start/stop counting
- Show a giant total word count, a few rate metrics (last 1 min, last 10 min, overall), and a 30-second caption strip for transparency
- Use only free, open browser APIs — no servers, no accounts, no model downloads
- Behave correctly on Android Chrome's continuous-mode recognition (cumulative-refinement deduplication)
- Support a long-running ambient session that survives a leisurely walk with the phone in a pocket

## Non-goals

- Speaker identification, transcription export, or persistent storage
- Operating with the device screen truly off — see "Background operation" below
- Supporting browsers without the Web Speech API (Firefox)

## Recognition modes

A small **Recognition** chooser exposes two modes:

- **On-device** (default): sets the standardized `processLocally = true` hint. Recent Chromium and Safari can fulfill this with an installed language pack; older browsers ignore the hint.
- **Cloud**: streams audio to the browser vendor's speech service (Google in Chromium's case). Wider language coverage at the cost of privacy.

The chooser is disabled while listening so the choice can't change mid-session.

### On-device language pack lifecycle

On Chromium-family browsers the standardized `processLocally` hint requires the page to explicitly *install* a language pack before `start()` will work. Skipping this step is precisely what made the on-device path fail with `language-not-supported` on Android Chrome before the fix. The meter now runs the following pre-flight before every on-device session:

1. Call `SpeechRecognition.available({ langs: [navigator.language], processLocally: true })`.
2. If the result is `available`, start immediately.
3. If the result is `downloadable` or `downloading`, surface a `downloading on-device language pack…` status and call `SpeechRecognition.install({ langs, processLocally: true })`. Start after the install promise resolves to `true`.
4. If the result is `unavailable`, or the install resolves to `false` or rejects, show a clear error and end the session — no `start()` is attempted.
5. If the browser does not expose the `available` / `install` static methods (older Chromium and Safari), skip the pre-flight and fall back to calling `start()` directly. The existing `onerror` handler still surfaces `language-not-supported` and `network` errors with actionable text.

Cloud mode skips the pre-flight entirely. If the user hits **Stop** while a download is in flight, the pending start is cancelled by checking that `session.listening` is still true and `session.recognition` is still the same object before invoking `start()`.

## Build version and cache busting

Every served copy of `word-meter.js` carries an embedded build identifier — the first 12 hex chars of SHA-256 of the source file — substituted at build time for the `__WORD_METER_VERSION__` placeholder. The version is rendered into the privacy footer (`Word Meter build <hash>`) and logged to the browser console with every diagnostic event, so the user can confirm at a glance which build the browser is actually running.

To prevent stale-cache surprises, the Static emitter writes a second copy of the script at `<basename>.<hash>.js`, and a small rehype HTML transformer (`CacheBustStaticAssets`) rewrites every `<script src="/static/*.js">` reference in the rendered HTML to point at the hashed URL. Because the URL changes with every byte of the source, the browser cannot serve a stale cached copy after a deploy. The un-versioned filename is also written with the same substituted bytes so direct visits to the old URL keep working. The hashing module lives in `quartz/util/staticAssetHash.ts` and is shared by the emitter and the transformer so the hash on the URL always matches the hash baked into the file.

## Diagnostics panel

The meter renders a collapsible **🔧 Diagnostics** panel below the privacy footer. When expanded it shows, in order:

1. **Environment snapshot** — script build version, `navigator.userAgent`, `navigator.language`, whether `SpeechRecognition` and `webkitSpeechRecognition` are exposed, whether the static `available` / `install` methods are exposed, and whether the Screen Wake Lock API is available.
2. **Event log** — a rolling, capped-at-60 list of timestamped diagnostic events. Every step of the on-device pre-flight (`available()` call, its result, `install()` call, its result), every `recognition.start()` invocation, and every `onerror` event (with `error` code and `message`) is logged here.

Every entry is also echoed to the browser console prefixed with `[word-meter <version>]` so curious users can grep the devtools log. This makes "it didn't work on my browser" reports diagnosable: the user can copy the diagnostics text directly into a bug report.

## Cumulative-refinement deduplication

Android Chrome's continuous mode + `interimResults` emits each refinement of one utterance as a *separate* finalized `SpeechRecognitionResult` carrying the *full cumulative transcript*. Naive index-based deduplication over-counts dramatically (issue #6897). The meter instead routes every finalized transcript into one of four cases relative to the most recent finalized transcript:

1. **Exact duplicate** → ignore; refresh the latest caption's timestamp
2. **Word-boundary extension** (refinement) → add only the word delta, replace the latest caption in place
3. **Earlier snapshot** of the same utterance → ignore
4. **Otherwise** → new utterance segment; add full word count and push a new caption

Comparison is case-insensitive on a whitespace-collapsed normalized form. A boundary extension requires a space at the join, so `twinkle` → `twinkles` is *not* treated as a refinement.

## Background operation: keep-awake toggle

A user-toggleable **🔋 Keep counting with screen on** checkbox (default ON) gates a Screen Wake Lock that keeps the device's screen from auto-locking while the meter runs. Without it, screen lock suspends the page and `SpeechRecognition` stops, ending the count.

### Lifecycle

- On `start`, if the toggle is checked, the meter calls `navigator.wakeLock.request('screen')`. If the request fails or the API is missing, the toggle's status text explains and the session continues without the lock.
- On `stop`, the meter releases the wake lock.
- On `visibilitychange` to `visible`, if the meter is still listening with keep-awake on but no lock is currently held (because the browser silently released it on hide), the meter re-requests it. This makes brief tab switches non-fatal to long sessions.
- On Quartz `nav` (SPA navigation away from the tool), the cleanup hook releases the wake lock and removes the visibility listener.

### Why not run with the screen off?

Pure-web browsers do not allow microphone capture once the page becomes hidden or the screen locks. There is no public web API that grants a webpage background mic access — that capability is reserved for native apps via Android foreground services or iOS background-audio entitlements. Service Workers can run in the background but cannot access the microphone. Silent-audio-loop hacks no longer keep `SpeechRecognition` alive on modern Android Chrome / iOS Safari when the screen actually locks. The Screen Wake Lock workaround is the closest a pure-web tool can get to the user's stated use case (start meter → put in pocket → walk for an hour → check count when home).

## UI structure

`buildPanel` composes, in order: status line, big count, count label, start/stop button, recognition mode chooser, keep-awake toggle, metrics grid (started time, last-1-min rate, last-10-min rate, overall rate), captions panel, error banner, privacy footer (including build version), and a collapsible diagnostics panel.

## Lifecycle and cleanup

The whole app is wrapped in an IIFE that re-inits on Quartz `nav` events. The cleanup hook stops listening, clears the tick interval, clears the restart timer, releases any active wake lock, and removes the `visibilitychange` listener.

## Tests

`quartz/static/word-meter.test.mjs` loads the source into a Node `vm` sandbox and exercises the production code paths via the `__WM_TEST_HOOK__` test hook. Two loaders are provided:

- `loadWordMeter` — minimal sandbox for the finalized-result integration tests (no DOM, no SpeechRecognition).
- `loadWordMeterWithLifecycle` — richer sandbox with mocked SpeechRecognition, navigator (with optional `wakeLock`), and a DOM that exposes the keep-awake checkbox so the wake-lock lifecycle can be driven end-to-end.

The wake-lock test cases cover: acquisition with the toggle on, no acquisition with the toggle off, release on stop, graceful no-op when the API is missing, and bounded re-acquisition on visibility change (never lose a request, never double-request while a lock is already held).
