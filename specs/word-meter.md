---
share: true
title: "🎙️ Word Meter Spec"
---

# 🎙️ Word Meter Spec

The Word Meter is a single-page browser tool that listens to ambient speech via the Web Speech API and counts the words it hears. It lives at `/tools/word-meter` (rendered from `content/tools/word-meter.md`) and is served as `quartz/static/word-meter.js`, compiled from PureScript sources under `purs-ps/src/WordMeter/`. There is no server, no upload from this page, no account, and no cost.

## Goals

- Tap a single button to start/stop counting
- Show a big "words today" count plus a multi-tile metrics grid covering lifetime total, per-day average, sample-percent (the fraction of wall time the meter actually recorded), short/long/overall rates, listening duration, and first-start timestamp — backed by a 30-second caption strip for transparency
- Use only free, open browser APIs — no servers, no accounts, no model downloads
- Behave correctly on Android Chrome's continuous-mode recognition (cumulative-refinement deduplication)
- Support a long-running ambient session that survives a leisurely walk with the phone in a pocket

## Non-goals

- Speaker identification, transcription export, or persistent storage
- Operating with the device screen truly off — see "Background operation" below
- Supporting browsers without the Web Speech API (Firefox)

## Recognition strategy

The meter has one user-visible mode and no chooser. Internally it has two implementation paths:

- **On-device path**: sets the standardized `processLocally = true` hint and runs the pre-flight described below. Used on browsers that expose the static `SpeechRecognition.available` / `install` API (recent Chromium-family builds).
- **Cloud path**: streams audio to the browser vendor's speech service (Google in Chromium's case, the system service on Safari, etc.). Used on every other browser and on every browser where the on-device pre-flight reports the language pack is not viable.

At every Start, the meter tries the on-device path first when the static API is exposed; if anything other than `available` comes back from the pre-flight (`unavailable`, `install-failed`, or `unknown`), the meter silently builds a fresh recognition object with `processLocally = false` and starts that one instead. The user is not asked to choose, and the page does not surface a chooser. This is justified by field telemetry: on Android (Chrome and Brave) the static API exists but reports `unavailable` for `en-US`; on Samsung Internet the static API does not exist at all and the cloud path takes over by default. In both cases the user gets a working meter without ever seeing or thinking about modes.

The on-device path lives in `WordMeter.Capability.Recognition.prepareOnDeviceLanguagePack` plus the `OnDevicePath` branch of `WordMeter.Main.startRecognitionForSession`. If the on-device API is ever dropped (or proves never to work in practice), removing that branch and collapsing `startRecognitionForSession` to the cloud path is a small, local change.

### On-device language pack lifecycle

On Chromium-family browsers the standardized `processLocally` hint requires the page to explicitly *install* a language pack before `start()` will work. Skipping this step is precisely what made the on-device path fail with `language-not-supported` on Android Chrome before the fix. When the static API is exposed, the meter runs the following pre-flight before every Start:

1. Call `SpeechRecognition.available({ langs: [navigator.language], processLocally: true })`.
2. If the result is `available`, build a recognition object with `processLocally = true` and call `start()`.
3. If the result is `downloadable` or `downloading`, surface a `downloading on-device language pack…` status and call `SpeechRecognition.install({ langs, processLocally: true })`. On install success, start the on-device recognition object.
4. If the result is `unavailable`, or the install resolves to `false` or rejects, transparently fall back to the cloud path — no error is shown to the user.
5. If the browser does not expose the `available` / `install` static methods, the meter skips the pre-flight entirely and goes straight to the cloud path.

If the user hits **Stop** while a download is in flight, the pending start is cancelled by checking that `session.listening` is still true and `session.recognition` is still the same object before invoking `start()`.

### Runtime language-not-supported fallback

Some browsers expose the static API, report `available`, then reject `start()` with `language-not-supported` at runtime. When this happens, the meter detaches the failed recognition object, builds a fresh one on the cloud path, and starts it — exactly once. A second `language-not-supported` after the cloud retry surfaces a clear error and ends the session.

## Build version

The script declares a hard-coded `WORD_METER_VERSION` constant (currently `0.1.0`) which is rendered into the privacy footer as `Word Meter v<version>` and prefixed onto every console-logged diagnostic event. Bump it whenever served behavior changes in a user-visible way. There is intentionally no build-time content-hashing or cache-busting machinery — the markdown's `<script src>` reference is plain and the version constant is the only thing that identifies a release.

## Diagnostics panel

The meter renders a collapsible **🔧 Diagnostics** panel below the privacy footer. When expanded it shows, in order:

1. **Environment snapshot** — script build version, `navigator.userAgent`, `navigator.language`, whether `SpeechRecognition` and `webkitSpeechRecognition` are exposed, whether the static `available` / `install` methods are exposed, and whether the Screen Wake Lock API is available.
2. **Event log** — a rolling, capped-at-60 list of timestamped diagnostic events. Every step of the on-device pre-flight (`available()` call, its result, `install()` call, its result), every `recognition.start()` invocation, and every `onerror` event (with `error` code and `message`) is logged here.

Every entry is also echoed to the browser console prefixed with `[word-meter <version>]` so curious users can grep the devtools log. A **📋 Copy diagnostics** button at the top of the panel writes the snapshot and event log to the clipboard via `navigator.clipboard.writeText`, falling back to a hidden `<textarea>` + `document.execCommand('copy')` when the async Clipboard API is unavailable.

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

`buildPanel` composes, in order: status line, big count (today's words), count label, start/stop button, keep-awake toggle, metrics grid (lifetime total, per-day average, sample %, last-1-min rate, last-10-min rate, overall rate, listening duration, started time, top word and longest word for the current period), captions panel, error banner, privacy footer (including build version), and a collapsible diagnostics panel.

### Per-period word stats

Each counting period — one Start → Stop cycle — tracks two extra stats in addition to the word count:

- **Top word** — the single most-frequently-used word in the period, paired with its occurrence count. Words are compared case-insensitively after surrounding ASCII punctuation is stripped, so `"Hello,"` and `"hello"` collapse into the same bucket. Ties on count break alphabetically on the normalized key so reloads always show the same word.
- **Longest word** — the single longest word in the period, preserving the casing of its first occurrence. Length ties go to the first word seen.

Both stats accumulate live while the meter is listening and surface in the metrics grid (`wm-top-word`, `wm-longest-word`). On Stop, they are frozen into the closed `LoggedInterval` and rendered alongside the existing duration / word count / rate cells in the historical event log (`wm-event-log-entry-top-word`, `wm-event-log-entry-longest-word`). Starting a new period resets the live counters so each period stands on its own.

The frozen stats are stored as optional fields on `PersistedLoggedInterval` (`mostFrequentWord`, `mostFrequentWordCount`, `longestWord`) so existing localStorage payloads written by earlier builds keep decoding — every missing field defaults to `Nothing`.

### Multi-day stats

The big number reflects **today's** words, bucketed by the user's local calendar date (midnight-to-midnight). The session carries a `wordsToday :: Int` counter and a `todayLocalDate :: Maybe LocalDate` stamp. Every word-adding action and every live `Tick` runs `rolloverWordsToday`: if the local date of the timestamp differs from the stored `todayLocalDate`, `wordsToday` is reset to zero before the new words are added. `LocalDate` is a thin newtype wrapping a `YYYY-MM-DD` string produced by a tiny FFI shim that reads `Date.getFullYear` / `getMonth` / `getDate` in the browser's local timezone.

The metrics grid surfaces three multi-day stats alongside the existing rate tiles:

- **Total** — lifetime `totalWords` since the very first start (survives stop/start cycles and page reloads via localStorage).
- **Per day** — `totalWords / max(1, wallSpanDays)` where `wallSpanDays = (now - firstStartedAt) / 86_400_000`. The denominator is clamped to at least one day so a fresh session does not divide by zero.
- **Sample %** — `activeListeningMs / wallSpanMs` clamped to `[0, 1]`. Communicates what fraction of the wall-clock time since first start the meter has actually been recording. Twelve hours of listening in a 24-hour wall span surfaces as `50%`.

Both `wordsToday` and `todayLocalDate` are persisted in the localStorage envelope (`word-meter:state:v1`) as optional fields with safe defaults (`0` and `null`) so payloads written by earlier builds keep loading. The post-reload `Tick currentTimeMillis` re-checks the date, so a session loaded on a new calendar day shows the big number at zero while the Total tile preserves the full history.

## Lifecycle and cleanup

The whole app is a PureScript-built IIFE that re-inits on Quartz `nav` events. The cleanup hook stops listening, clears the tick interval, clears the restart timer, releases any active wake lock, and removes the `visibilitychange` listener.

## Tests

The PureScript implementation is exercised by two suites:

- **Unit tests** in `purs-ps/test/` (`npm run test:ps`) cover the pure reducer, the rate math, the recognition delta classifier, the recognition error classifier, and the persistence codec.
- **Playwright end-to-end tests** in `tests/e2e/word-meter.spec.ts` (`npm run test:e2e`) drive the live bundle through a stable `data-testid` selector contract — start/stop, transcript injection, captions, stats, event log, diagnostics drawer, persistence round-trip, wake lock, recognition error banner, on-device pre-flight, and the cloud-fallback retry path.

The wake-lock test cases cover: acquisition with the toggle on, no acquisition with the toggle off, release on stop, graceful no-op when the API is missing, and bounded re-acquisition on visibility change (never lose a request, never double-request while a lock is already held).
