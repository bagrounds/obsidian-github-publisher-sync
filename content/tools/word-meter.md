---
share: true
title: 🎙️ Word Meter
aliases:
  - 🎙️ Word Meter
description: Count the ambient spoken words around you with a single tap, using your browser's built-in Web Speech API.
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_version: "2"
link_analysis_time: 2026-05-10T00:00:00Z
force_analyze_links: false
---
  
[🏡 Home](../index.md#) > [🧰 Tools](./index.md#)  
  
# 🎙️ Word Meter  
  
*One button. Counts every word spoken around you. Lives entirely in your browser.*  
  
<div id="word-meter"></div>  
  
<script src="/static/word-meter.js?t=0"></script>  
  
## About  
  
**Word Meter** uses the browser's built-in **Web Speech API** (`SpeechRecognition`) to listen to your microphone and count the words it hears. There is no server, no upload from this page, no account, and no cost.  
  
- 🟢 Tap **Start counting** and grant microphone access  
- 🔢 The big number is the total words spoken since you started  
- ⏱️ See your words-per-minute over the last 1 minute, last 10 minutes, and overall  
- 💬 The captions panel shows the last 30 seconds of recognized speech, fading as it ages  
- 🔒 Pick **On-device** (default) or **Cloud** recognition — see below  
- 🔋 Toggle **Keep counting with screen on** to keep listening through a long walk — see below  
  
### On-device vs. cloud  
  
The page exposes a small **Recognition** chooser. **On-device** is the default and asks the browser to keep audio handling local using the standardized `processLocally` hint. Recent Chromium and Safari can fulfill this request when the language pack is installed; otherwise the browser may fall back, or recognition may fail with a clear message you can act on. **Cloud** mode lets the browser stream audio to its vendor's speech service (Google, in Chromium's case) which usually offers wider language coverage at the cost of privacy.  
  
### Long-running sessions and the screen-off question  
  
If you want to start the meter, drop the phone in your pocket, and have a full count waiting after a long walk, leave the **🔋 Keep counting with screen on** toggle checked. When you tap **Start counting**, the page asks the browser for a [Screen Wake Lock](https://developer.mozilla.org/docs/Web/API/Screen_Wake_Lock_API), which prevents the screen from auto-locking while the meter runs. The screen stays lit (face-down in your pocket is fine), the page never gets suspended, and counting continues normally. The lock is released the moment you tap **Stop counting**.  
  
**Why not actually run with the screen off?** Web browsers — Android Chrome, iOS Safari, every other mainstream mobile browser — suspend a page's JavaScript and microphone capture as soon as the screen locks or the tab becomes hidden. There is no public web API that grants a webpage background microphone access with the screen truly off; that capability is reserved for native apps using Android foreground services or iOS background-audio entitlements. Service Workers, the only thing that runs while a page is hidden, cannot access the microphone. The Screen Wake Lock workaround above is the closest a pure-web tool can get, and it covers the actual use case (listen ambient speech for an hour while the phone is in a pocket) without compromising on privacy or installing a native app. If your browser doesn't support `wakeLock` (older Safari builds), the toggle gracefully no-ops and tells you so.  
  
### Browser support  
  
The Web Speech API is supported in **Chrome, Edge, and Safari**. Firefox does not currently expose `SpeechRecognition`. The on-device toggle is most meaningful on recent Chromium builds; older browsers ignore the hint and behave as they always have. The Screen Wake Lock API is supported in Chrome, Edge, and Safari 16.4+; on older browsers the keep-awake toggle quietly does nothing.  
  
### Tips  
  
- Speak normally — the recognizer works best with conversational speech  
- Use a quiet-ish room for accurate counts; very low or very loud audio can be skipped by the recognizer  
- The counter automatically restarts after silence so it can run as ambient background measurement  
- For long walks, leave **Keep counting with screen on** checked and put the phone in your pocket face-down or face-in to avoid stray taps  
