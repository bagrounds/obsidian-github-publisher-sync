---
share: true
title: 🎙️ Word Meter
aliases:
  - 🎙️ Word Meter
description: Count the ambient spoken words around you with a single tap, using your browser's built-in Web Speech API.
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_version: "2"
link_analysis_time: 2026-05-11T00:00:00Z
force_analyze_links: false
URL: https://bagrounds.org/tools/word-meter
updated: 2026-05-11T21:42:18
---
  
[🏡 Home](../index.md#) > [🧰 Tools](./index.md#)  
# 🎙️ Word Meter  
![tools-word-meter](../tools-word-meter.jpg)  
  
*One button. Counts every word spoken around you. Lives entirely in your browser.*  
  
<div id="word-meter"></div>  
  
<script src="/static/word-meter.js"></script>  
  
## How it works  
  
Tap **Start counting** and grant microphone access. The big number is the total words spoken since you started. The metrics row shows your words-per-minute over the last 1 minute, last 10 minutes, and overall. The captions panel shows the last 30 seconds of recognized speech. The timeline logs every start/stop interval. Stats are saved to your browser's local storage and survive reloads — only the **Reset** button clears them.  
  
For a long walk with the phone in your pocket, leave **🔋 Keep counting with screen on** checked. The page uses the [Screen Wake Lock API](https://developer.mozilla.org/docs/Web/API/Screen_Wake_Lock_API) to keep the screen lit so the browser does not suspend microphone capture — that is the closest a pure-web tool can get to background audio.  
  
If something looks wrong, expand the **🔧 Diagnostics** panel at the bottom of the meter and tap **📋 Copy diagnostics** to grab a paste-ready report.  
  
## Browser support  
  
Works on Chrome, Edge, Safari, and Samsung Internet. Firefox does not currently expose `SpeechRecognition`. The Screen Wake Lock API requires a recent Chromium build or Safari 16.4+.  
  
## 📚 Book Recommendations  
  
### 📖 Similar  
* Thirty Million Words by Dana Suskind is the direct inspiration for this tool. It documents the research showing that the sheer volume of words a child hears in the first years of life is a strong predictor of later language and academic outcomes, and it argues that simply being aware of that volume changes parents' behavior. Word Meter is a tiny instrument for exactly that awareness.  
* The Scientist In The Crib by Alison Gopnik, Andrew N. Meltzoff, and Patricia K. Kuhl is relevant because it grounds the case for talking richly to babies in the cognitive science of how infants extract structure from speech.  
  
### ↔️ Contrasting  
* Beyond Words: What Animals Think And Feel by Carl Safina is relevant because it pushes back on the idea that human linguistic input is the only kind of communication that shapes cognition, and reminds us that the count is not the whole story.  
  
### 🔗 Related  
* The Language Instinct by Steven Pinker is relevant because it argues that language acquisition is a biological capacity, not a count of inputs — useful counterweight to taking a word-counting meter too seriously.  
  
## 🦋 Bluesky    
<blockquote class="bluesky-embed" data-bluesky-uri="at://did:plc:i4yli6h7x2uoj7acxunww2fc/app.bsky.feed.post/3mlmajv7f4726" data-bluesky-cid="bafyreigchen2fxayvltl2e22u6le7js6bqxxu5akzyw5e7uhnf62tredmm"><p>🎙️ Word Meter  
  
#AI Q: 💬 Does word count or content shape communication more?  
  
👶 Child Development | 🎤 Speech Analytics | 📊 Quantified Self  
https://bagrounds.org/tools/word-meter</p>&mdash; <a href="https://bsky.app/profile/did:plc:i4yli6h7x2uoj7acxunww2fc?ref_src=embed">Bryan Grounds (@bagrounds.bsky.social)</a> <a href="https://bsky.app/profile/did:plc:i4yli6h7x2uoj7acxunww2fc/post/3mlmajv7f4726?ref_src=embed">2026-05-11T21:42:30.000Z</a></blockquote><script async src="https://embed.bsky.app/static/embed.js" charset="utf-8"></script>  
  
## 🐘 Mastodon    
<blockquote class="mastodon-embed" data-embed-url="https://mastodon.social/@bagrounds/116558121246643214/embed" style="background: #282c37; border-radius: 8px; border: 1px solid #393f4f; margin: 0; max-width: 540px; min-width: 270px; overflow: hidden; padding: 0;"> <a href="https://mastodon.social/@bagrounds/116558121246643214" target="_blank" style="align-items: center; color: #d9e1e8; display: flex; flex-direction: column; font-family: system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Oxygen, Ubuntu, Cantarell, 'Fira Sans', 'Droid Sans', 'Helvetica Neue', Roboto, sans-serif; font-size: 14px; justify-content: center; letter-spacing: 0.25px; line-height: 20px; padding: 24px; text-decoration: none;"> <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="32" height="32" viewBox="0 0 79 75"><path d="M63 45.3v-20c0-4.1-1-7.3-3.2-9.7-2.1-2.4-5-3.7-8.5-3.7-4.1 0-7.2 1.6-9.3 4.7l-2 3.3-2-3.3c-2-3.1-5.1-4.7-9.2-4.7-3.5 0-6.4 1.3-8.6 3.7-2.1 2.4-3.1 5.6-3.1 9.7v20h8V25.9c0-4.1 1.7-6.2 5.2-6.2 3.8 0 5.8 2.5 5.8 7.4V37.7H44V27.1c0-4.9 1.9-7.4 5.8-7.4 3.5 0 5.2 2.1 5.2 6.2V45.3h8ZM74.7 16.6c.6 6 .1 15.7.1 17.3 0 .5-.1 4.8-.1 5.3-.7 11.5-8 16-15.6 17.5-.1 0-.2 0-.3 0-4.9 1-10 1.2-14.9 1.4-1.2 0-2.4 0-3.6 0-4.8 0-9.7-.6-14.4-1.7-.1 0-.1 0-.1 0s-.1 0-.1 0 0 .1 0 .1 0 0 0 0c.1 1.6.4 3.1 1 4.5.6 1.7 2.9 5.7 11.4 5.7 5 0 9.9-.6 14.8-1.7 0 0 0 0 0 0 .1 0 .1 0 .1 0 0 .1 0 .1 0 .1.1 0 .1 0 .1.1v5.6s0 .1-.1.1c0 0 0 0 0 .1-1.6 1.1-3.7 1.7-5.6 2.3-.8.3-1.6.5-2.4.7-7.5 1.7-15.4 1.3-22.7-1.2-6.8-2.4-13.8-8.2-15.5-15.2-.9-3.8-1.6-7.6-1.9-11.5-.6-5.8-.6-11.7-.8-17.5C3.9 24.5 4 20 4.9 16 6.7 7.9 14.1 2.2 22.3 1c1.4-.2 4.1-1 16.5-1h.1C51.4 0 56.7.8 58.1 1c8.4 1.2 15.5 7.5 16.6 15.6Z" fill="currentColor"/></svg> <div style="color: #9baec8; margin-top: 16px;">Post by @bagrounds@mastodon.social</div> <div style="font-weight: 500;">View on Mastodon</div> </a> </blockquote> <script data-allowed-prefixes="https://mastodon.social/" async src="https://mastodon.social/embed.js"></script>