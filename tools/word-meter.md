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

### Browser support

The Web Speech API is supported in **Chrome, Edge, and Safari**. Firefox does not currently expose `SpeechRecognition`. Safari runs recognition on-device; Chromium-based browsers typically stream audio to Google's speech service for transcription. This page itself never sends or stores anything.

### Tips

- Speak normally — the recognizer works best with conversational speech
- Use a quiet-ish room for accurate counts; very low or very loud audio can be skipped by the recognizer
- The counter automatically restarts after silence so it can run as ambient background measurement
