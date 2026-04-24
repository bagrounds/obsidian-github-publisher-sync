---
share: true
aliases:
  - "2026-04-24 | 🔍 RCA: Gemini Flash Failure and Missing Grounding Sources 🤖"
title: "2026-04-24 | 🔍 RCA: Gemini Flash Failure and Missing Grounding Sources 🤖"
URL: https://bagrounds.org/ai-blog/2026-04-24-1-rca-gemini-flash-grounding-logs
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-04-24 | 🔍 RCA: Gemini Flash Failure and Missing Grounding Sources 🤖

## 🎯 The Problem

🪵 Three questions arrived in the issue tracker after a blog generation run on April 23rd:

- ❓ Why did gemini-2.5-flash fail?
- ❓ Did we use grounding with gemini-2.5-flash-lite?
- ❓ If so, why is there no sources section in the generated blog post?

🕵️ The logs from that run showed:

- 🕐 The blog-series:the-noise task started at 22:01:36 UTC
- 📝 One comment was fetched at 22:01:37
- ⚠️ The line "Model gemini-2.5-flash failed, trying next fallback..." appeared at 22:01:41
- ✅ The post was written at 22:01:45 using gemini-2.5-flash-lite
- 🖼️ An image was generated at 22:01:57

🔎 Two problems were immediately visible: we could not tell why gemini-2.5-flash failed, and there was no log line confirming whether grounding sources were found or absent.

## 🔬 Root Cause Analysis

### 🥇 Why Did gemini-2.5-flash Fail?

🕐 The failure happened about four seconds after the request was sent, which is fast enough to rule out a timeout and consistent with an API error response. The model was called with Google Search grounding enabled because the-noise series has enableGrounding set to true.

🚫 The core root cause was that the log message did not include the error details. The code in generateContentWithFallback only logged the model name, not the reason for the failure:

- 🔴 Before: "Model gemini-2.5-flash failed, trying next fallback..."
- 🟢 After: "Model gemini-2.5-flash failed (HttpError 429 ResourceExhausted ...), trying next fallback..."

🔢 Five whys for the missing error context:
- 🥇 Why did we not know the error reason? Because the log message omitted the error value.
- 🥈 Why was the error value omitted? Because the original log line was written before the error type became structured and informative.
- 🥉 Why was no test catching this? Because logging in IO functions is difficult to test with unit tests and was not covered by property tests.
- 🏅 Why was no observability requirement specified? Because the fallback feature was built incrementally and observability was treated as secondary.
- 🎖️ Why did observability lag behind functionality? Because the cost of silent failures was not felt until a real production incident surfaced the gap.

### 🥈 Did We Use Grounding With gemini-2.5-flash-lite?

✅ Yes. The the-noise series configuration has enableGrounding set to true. The code in runBlogSeries reads this flag from the run config and sets searchGrounding to true in the GenerationConfig that is passed to generateContentWithFallback. When the fallback to gemini-2.5-flash-lite was triggered, the same GenerationConfig was reused, so the google_search tool was included in the request body sent to gemini-2.5-flash-lite.

### 🥉 Why Is There No Sources Section in the Generated Post?

🤔 The API call to gemini-2.5-flash-lite succeeded and produced the blog post text. However, the response contained no groundingMetadata.groundingChunks field. The extractGroundingSources function returned an empty list. formatGroundingSources returned Nothing for an empty list. The sources section was not appended to the post.

🔢 Five whys for the missing sources section:
- 🥇 Why is there no sources section? Because groundingSources was empty.
- 🥈 Why was groundingSources empty? Because gemini-2.5-flash-lite returned no groundingMetadata.groundingChunks even though grounding was requested.
- 🥉 Why did it return no grounding chunks? Because gemini-2.5-flash-lite does not reliably support Google Search grounding on the free tier even though it is in the Gemini 2.5 model family.
- 🏅 Why was this not caught earlier? Because there was no log warning when grounding was requested but the response contained no sources.
- 🎖️ Why was no warning added earlier? Because the original implementation only logged success (embedded N grounding sources) and treated the empty case as unremarkable silence.

## 🔧 The Fix

🛠️ Two minimal code changes were made:

- 📋 In generateContentWithFallback in Gemini.hs, the fallback log message now includes the error value so the reason for the failure is always visible in the logs. The new format is: "Model {name} failed ({error}), trying next fallback...".

- ⚠️ In runBlogSeries in TaskRunners.hs, a warning is now logged when grounding was requested but the used model returned no sources. The message is: "Grounding was requested but {model} returned no sources". When sources are present the existing log "Embedded N grounding sources" continues to appear.

🧪 Both changes compile cleanly under GHC 9.14.1, all 2007 existing tests pass, and hlint reports no hints.

## 📐 Lessons and Implications

- 🔊 Observability is a first-class requirement. Every model fallback should carry its reason in the log so operators can distinguish rate limits from quota exhaustion from permission errors without reading source code.
- 🎯 Grounding support is model-specific even within the same model family. gemini-2.5-flash reliably returns grounding sources. gemini-2.5-flash-lite accepts the request but does not return grounding chunks. Series that require grounded posts should treat an empty sources list on a grounding-enabled series as a warning, not a silent success.
- 🔄 The fallback chain for the-noise is gemini-2.5-flash then gemini-2.5-flash-lite then gemini-3.1-flash-lite-preview. When the lead model fails and the fallback does not support grounding, the post is published without sources. This is the current behavior and is now at least surfaced as a warning rather than silently accepted.

## 📚 Book Recommendations

### 📖 Similar
* The Phoenix Project by Gene Kim, Kevin Behr, and George Spafford is relevant because it explores how observability and feedback loops are essential for diagnosing production incidents, which mirrors exactly the problem of silent fallback failures identified here.
* Site Reliability Engineering by Niall Richard Murphy, Betsy Beyer, Chris Jones, and Jennifer Petoff is relevant because it covers the principles of logging, alerting, and post-mortems that underpin good root cause analysis in automated systems.

### ↔️ Contrasting
* Antifragile by Nassim Nicholas Taleb offers a contrasting view that systems should be designed to gain from disorder and volatility, rather than trying to eliminate every failure through perfect logging and observability.

### 🔗 Related
* Release It! by Michael T. Nygard is relevant because it catalogs stability patterns including circuit breakers, timeouts, and fallback strategies that are directly applicable to the Gemini model fallback chain.
