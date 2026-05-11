---
share: true
title: "🎙️ Word Meter"
aliases:
  - 🎙️ Word Meter
description: "Count the ambient spoken words around you with a single tap, using your browser's built-in Web Speech API."
---

[🏡 Home](../index.md) > [🧰 Tools](./index.md)

# 🎙️ Word Meter

*One button. Counts every word spoken around you. Lives entirely in your browser.*

<div id="word-meter"></div>

<script src="/static/word-meter.js"></script>

## About

**Word Meter** uses the browser's built-in **Web Speech API** (`SpeechRecognition`) to listen to your microphone and count the words it hears. There is no server, no upload from this page, no account, and no cost.

- 🟢 Tap **Start counting** and grant microphone access
- 🔢 The big number is the total words spoken since you started
- ⏱️ See your words-per-minute over the last 1 minute, last 10 minutes, and overall
- 💬 The captions panel shows the last 30 seconds of recognized speech, fading as it ages
- 🧮 The timeline at the bottom logs every start/stop interval with its word count and words-per-minute
- 💾 Stats are saved to your browser's local storage and survive app switches, screen locks, and reloads — only the **Reset** button clears them
- 🔒 Pick **On-device** (default) or **Cloud** recognition — see below
- 🔋 Toggle **Keep counting with screen on** to keep listening through a long walk — see below

### Persistence and the reset button

Word Meter writes its running stats to your browser's `localStorage` continuously — after every recognized utterance, every Start, every Stop, and again whenever the page is hidden or unloaded. When you switch apps and come back, the totals, the per-interval timeline, and the words-per-minute history are all still there, and the meter is simply paused until you tap **Start counting** again. Each Start appends a brand new interval to the timeline at the bottom of the page rather than wiping the previous one, so the running total grows across as many sessions as you like. The only way to clear the stats is to tap the **Reset** button next to Start/Stop, which prompts for confirmation before discarding everything. Storage is per-origin and stays entirely on your device — nothing leaves your browser.

### On-device vs. cloud

The page exposes a small **Recognition** chooser. **On-device** is the default and asks the browser to keep audio handling local using the standardized `processLocally` hint. Recent Chromium and Safari can fulfill this request when the language pack is installed; on first use the page asks the browser to download that pack and shows a brief *downloading on-device language pack…* status while it does so. **Cloud** mode lets the browser stream audio to its vendor's speech service (Google, in Chromium's case) which usually offers wider language coverage at the cost of privacy. If the on-device pack can't be downloaded or your language isn't supported on-device, the meter explains the situation and asks you to switch to Cloud mode.

### Long-running sessions and the screen-off question

If you want to start the meter, drop the phone in your pocket, and have a full count waiting after a long walk, leave the **🔋 Keep counting with screen on** toggle checked. When you tap **Start counting**, the page asks the browser for a [Screen Wake Lock](https://developer.mozilla.org/docs/Web/API/Screen_Wake_Lock_API), which prevents the screen from auto-locking while the meter runs. The screen stays lit (face-down in your pocket is fine), the page never gets suspended, and counting continues normally. The lock is released the moment you tap **Stop counting**.

**Why not actually run with the screen off?** Web browsers — Android Chrome, iOS Safari, every other mainstream mobile browser — suspend a page's JavaScript and microphone capture as soon as the screen locks or the tab becomes hidden. There is no public web API that grants a webpage background microphone access with the screen truly off; that capability is reserved for native apps using Android foreground services or iOS background-audio entitlements. Service Workers, the only thing that runs while a page is hidden, cannot access the microphone. The Screen Wake Lock workaround above is the closest a pure-web tool can get, and it covers the actual use case (listen ambient speech for an hour while the phone is in a pocket) without compromising on privacy or installing a native app. If your browser doesn't support `wakeLock` (older Safari builds), the toggle gracefully no-ops and tells you so.

### Build version and the diagnostics panel

The very bottom of the panel shows two things that make troubleshooting easy. First, a small line reads `Word Meter build <hash>` — the first 12 hex characters of the SHA-256 of the script. The build process injects that hash into the script itself and into the `<script>` URL on this page (`/static/word-meter.<hash>.js`), so even if your browser aggressively caches assets, the new version will have a new URL and the browser cannot serve the stale copy. If two devices show different build hashes, the device with the older hash is on a stale cache.

Second, a collapsible **🔧 Diagnostics** section expands to show a live event log: the user-agent string, whether the Web Speech API and its on-device static methods are present, the locale being requested, every `available()` and `install()` call and result, every `recognition.start()` invocation, and every recognition error event with its full error code and message. The same events also go to the browser console prefixed with `[word-meter <hash>]`. A **📋 Copy diagnostics** button at the top of the panel copies the snapshot and event log to your clipboard with one tap, so you can paste the whole thing straight into a bug report. If on-device mode is misbehaving on your browser, opening this panel and tapping copy is the fastest way to capture what is happening.

### Browser support

The Web Speech API is supported in **Chrome, Edge, and Safari**. Firefox does not currently expose `SpeechRecognition`. The on-device toggle is most meaningful on recent Chromium builds; older browsers ignore the hint and behave as they always have. The Screen Wake Lock API is supported in Chrome, Edge, and Safari 16.4+; on older browsers the keep-awake toggle quietly does nothing.

### Tips

- Speak normally — the recognizer works best with conversational speech
- Use a quiet-ish room for accurate counts; very low or very loud audio can be skipped by the recognizer
- The counter automatically restarts after silence so it can run as ambient background measurement
- For long walks, leave **Keep counting with screen on** checked and put the phone in your pocket face-down or face-in to avoid stray taps
