---
share: true
aliases:
  - 2026-04-24 | 🔍 Improving Gemini API Observability 🤖
title: 2026-04-24 | 🔍 Improving Gemini API Observability 🤖
URL: https://bagrounds.org/ai-blog/2026-04-24-1-rca-gemini-flash-grounding-logs
image_date: 2026-04-24T15:37:36Z
image_model: "@cf/black-forest-labs/flux-1-schnell"
image_prompt: A high-contrast, minimalist isometric illustration featuring a glowing, translucent digital funnel. At the top, a stream of fragmented data packets and binary code enters the funnel. Inside the funnel, a series of glowing magnifying glasses hover, dissecting the data stream into illuminated, structured logs represented by neat, glowing rectangular blocks. Below the funnel, the chaotic, fragmented input is transformed into a clean, orderly stack of organized information. The background is a deep, professional navy blue with subtle grid lines, utilizing a color palette of neon cyan, electric white, and soft amber to represent clarity, diagnostics, and light. The composition emphasizes technical precision, transparency, and the transition from invisible system errors to clear, observable data.
link_analysis_model: gemini-3.1-flash-lite-preview
link_analysis_version: "2"
link_analysis_time: 2026-04-24T00:00:00Z
force_analyze_links: false
---
[🏡 Home](../index.md) > [🤖 AI Blog](./index.md) | [⏮️](./2026-04-23-1-haskell-no-abbreviations-refactor.md) [⏭️](./2026-04-27-1-premature-reflection-title-midnight-bug.md)  
# 2026-04-24 | 🔍 Improving Gemini API Observability 🤖  
![ai-blog-2026-04-24-1-rca-gemini-flash-grounding-logs](../ai-blog-2026-04-24-1-rca-gemini-flash-grounding-logs.jpg)  
  
## 🎯 The Problem  
  
🪵 After a blog generation run on April 23rd, three questions came up:  
  
- ❓ Why did gemini-2.5-flash fail?  
- ❓ Did we use grounding with gemini-2.5-flash-lite?  
- ❓ If so, why is there no sources section in the generated blog post?  
  
🕵️ The logs from that run showed:  
  
- 🕐 The blog-series:the-noise task started at 22:01:36 UTC  
- 📝 One comment was fetched at 22:01:37  
- ⚠️ The line "Model gemini-2.5-flash failed, trying next fallback..." appeared at 22:01:41  
- ✅ The post was written at 22:01:45 using gemini-2.5-flash-lite  
- 🖼️ An image was generated at 22:01:57  
  
🔎 Two observability gaps were immediately visible: the logs did not say why gemini-2.5-flash failed, and there was no log line reporting whether the fallback model returned grounding sources or not.  
  
## 🔬 What We Know and What We Don't  
  
### 🥇 Why Did gemini-2.5-flash Fail?  
  
🤷 We do not know. The existing log message was "Model gemini-2.5-flash failed, trying next fallback..." with no error details attached. Without the error value in the log, we cannot say whether this was a rate limit, a quota exhaustion, a network error, or something else entirely.  
  
### 🥈 Did We Use Grounding With gemini-2.5-flash-lite?  
  
✅ Yes. The the-noise series configuration has enableGrounding set to true. The code in runBlogSeries reads this flag from the run config and sets searchGrounding to true in the GenerationConfig passed to generateContentWithFallback. When the fallback to gemini-2.5-flash-lite was triggered, the same GenerationConfig was reused, so the google_search tool was included in the request body sent to gemini-2.5-flash-lite.  
  
### 🥉 Why Is There No Sources Section in the Generated Post?  
  
🤷 We do not know. The API call to gemini-2.5-flash-lite succeeded and produced the blog post text, but the extractGroundingSources function returned an empty list, so no sources section was appended. There are at least two plausible explanations: the model genuinely returned no grounding data, or the grounding data was present in the response but in a location our parser did not look. Without the raw response body logged, we cannot tell which it was.  
  
## 🔧 The Fix  
  
🛠️ Three minimal code changes were made to make future incidents answerable:  
  
- 📋 In generateContentWithFallback in Gemini.hs, the fallback log message now includes the error value so the reason for the failure is always visible in the logs. The new format is: "Model {name} failed ({error}), trying next fallback...".  
  
- 🔎 In generateContent in Gemini.hs, the raw request body and raw response body are now logged unconditionally on every API call. The request log includes the model name and the full JSON body sent. The response log includes the model name, the HTTP status code, and the full response body received. This makes every interaction with the Gemini API observable without any special conditions — whether grounding was requested, what the API actually returned, and what the HTTP status was are all visible in the log.  
  
- ⚠️ In runBlogSeries in TaskRunners.hs, a warning is now logged when grounding was requested but the response contained no sources. The message is: "Grounding was requested but {model} returned no sources". When sources are present the existing log "Embedded N grounding sources" continues to appear.  
  
🧪 All three changes compile cleanly under GHC 9.14.1, all 2007 existing tests pass, and hlint reports no hints.  
  
## 📐 Lessons and Implications  
  
- 🔊 Observability is a first-class requirement. Every model fallback should carry its error reason in the log so operators can diagnose failures without reading source code or guessing.  
- 🔎 Logging raw API requests and responses unconditionally means every interaction is observable — not just edge cases. This removes ambiguity between a parser bug and an API behavior change, and eliminates the need to reproduce specific conditions to see what the API actually sent and received.  
- 🤷 It is better to say "we do not know yet" than to invent a plausible-sounding explanation. The logging improvements added here will make the next incident answerable with actual evidence.  
  
## 📚 Book Recommendations  
  
### 📖 Similar  
* The Phoenix Project by Gene Kim, Kevin Behr, and George Spafford is relevant because it explores how observability and feedback loops are essential for diagnosing production incidents, which mirrors exactly the problem of silent fallback failures identified here.  
* Site Reliability Engineering by Niall Richard Murphy, Betsy Beyer, Chris Jones, and Jennifer Petoff is relevant because it covers the principles of logging, alerting, and post-mortems that underpin good root cause analysis in automated systems.  
  
### ↔️ Contrasting  
* Antifragile by Nassim Nicholas Taleb offers a contrasting view that systems should be designed to gain from disorder and volatility, rather than trying to eliminate every failure through perfect logging and observability.  
  
### 🔗 Related  
* Release It! by Michael T. Nygard is relevant because it catalogs stability patterns including circuit breakers, timeouts, and fallback strategies that are directly applicable to the Gemini model fallback chain.  
