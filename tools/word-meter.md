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
- 🔒 Pick **On-device** (default) or **Cloud** recognition — see below

### On-device vs. cloud

The page exposes a small **Recognition** chooser. **On-device** is the default and asks the browser to keep audio handling local using the standardized `processLocally` hint. Recent Chromium and Safari can fulfill this request when the language pack is installed; otherwise the browser may fall back, or recognition may fail with a clear message you can act on. **Cloud** mode lets the browser stream audio to its vendor's speech service (Google, in Chromium's case) which usually offers wider language coverage at the cost of privacy.

### Browser support

The Web Speech API is supported in **Chrome, Edge, and Safari**. Firefox does not currently expose `SpeechRecognition`. The on-device toggle is most meaningful on recent Chromium builds; older browsers ignore the hint and behave as they always have.

### Tips

- Speak normally — the recognizer works best with conversational speech
- Use a quiet-ish room for accurate counts; very low or very loud audio can be skipped by the recognizer
- The counter automatically restarts after silence so it can run as ambient background measurement
