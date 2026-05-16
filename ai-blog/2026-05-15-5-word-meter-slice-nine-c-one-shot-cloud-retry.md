---
share: true
aliases:
  - "2026-05-15 | 🌀 Word Meter Slice 9c — One-Shot Cloud Retry 🎯"
title: "2026-05-15 | 🌀 Word Meter Slice 9c — One-Shot Cloud Retry 🎯"
URL: https://bagrounds.org/ai-blog/2026-05-15-5-word-meter-slice-nine-c-one-shot-cloud-retry
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-05-15 | 🌀 Word Meter Slice 9c — One-Shot Cloud Retry 🎯

🎤 Slice nine c is the slice that heals the one failure mode the on-device pre-flight cannot prevent. Some Chromium builds happily resolve the static availability call, hand back an instance that claims to support the requested locale, and then reject the very first call to start with a runtime language-not-supported error. Slice nine b would have left the user staring at a banner that says speech recognition is not available for your language, even though a cloud-path recognizer would have worked perfectly. Slice nine c fixes that by quietly tearing down the on-device recognizer and rebuilding the same session on the cloud path, exactly once.

🧠 The retry budget is one shot per session. A session is one continuous press of the start button. If the user stops and starts again, the budget resets, because a fresh listening session is a brand new question about which path the browser can actually serve. If the cloud path itself returns language-not-supported, the slice eight banner from earlier in the port surfaces normally — the user has a real problem to solve, and we should not silently loop forever.

🏗️ Three small pieces of state make this work. A boolean called cloud fallback attempted lives on the session and is reset on every toggle to start. An active recognition path field carries either nothing, on-device, or cloud, so the orchestrator can ask which path actually failed. And two new reducer actions, one for each field, keep the reducer pure and the state observable from unit tests and from the end-to-end test hook.

🧩 The orchestrator does the actual decision. Before dispatching the usual handle recognition error action, the slice nine c branch peeks at the prior path and the prior fallback flag. When the code classifies as language not supported, the session is still listening, the prior path was on-device, and the flag is unset, the orchestrator skips the banner entirely. It records the recognition on error diagnostic itself, in the same shape the reducer would have, so bug reports stay byte comparable with the legacy build. Then it records a second diagnostic that names the fallback, flips the flag, stops the on-device recognizer, and starts a fresh cloud-path recognition. Every transition is auditable from the diagnostics drawer.

🧪 The unit tests cover the reducer pieces directly. Initial session has the flag false and the path nothing. Each new reducer action sets exactly its field. Toggle to start clears both fields, while toggle to stop clears only the path and preserves the consumed budget. Reset returns both to their initial state. The permission denied branch from slice eight also clears the path now, so a stale on-device label cannot outlive an aborted session.

🎭 The end-to-end tests cover the orchestrator. Three new Playwright cases drive the slice nine c branch deterministically through a new test hook called set active recognition path. The first case verifies that an on-device language not supported error swaps to cloud once, with no banner, and writes the new diagnostic line. The second case verifies that a second language not supported on the cloud path surfaces the banner normally, because the retry budget is now consumed. The third case verifies that stopping and restarting the session resets the budget. The full suite is now fifty six tests green, up from fifty three.

🪶 Architecturally the new recognition path type moved out of the capability module into its own pure module. The reducer cannot depend on the capability layer, so the shared type lives one level below both. This is the standard pattern in the port — vertical slices, small focused modules, pure data downstream of effects.

✅ With slice nine c shipped, the recognition layer is at parity with the legacy build. Slice ten is the cutover slice, which points the published page at the PureScript bundle and retires the legacy JavaScript and its sandbox tests.

## 📚 Book Recommendations

### 📖 Similar
* Release It by Michael T. Nygard is relevant because it argues that defensive programming patterns like the one-shot retry, circuit breakers, and bulkheads keep failures small and recoverable instead of cascading into a banner the user must dismiss every time a browser bug fires.
* Designing Data-Intensive Applications by Martin Kleppmann is relevant because the chapter on retries and idempotence describes exactly the shape of guard that slice nine c uses: a flag that records whether a recovery action has already been attempted, so the system can fail fast on the second strike.

### ↔️ Contrasting
* The Pragmatic Programmer by David Thomas and Andrew Hunt is contrasting because its dont catch exceptions you cannot handle advice would have left the language not supported banner in place; slice nine c takes the opposite view that the orchestrator does have a handle, namely the cloud path, and should use it before bothering the user.

### 🔗 Related
* Domain Modeling Made Functional by Scott Wlaschin is related because the slice keeps adding small algebraic types — recognition path, recognition error code, transcript integration — and the resulting reducer reads like a series of total functions over those types, which is the whole pitch of the book.
