---
share: true
aliases:
  - "2026-05-15 | 🚨 Word Meter Slice Eight — Recognition Error Banner 🎙️"
title: "2026-05-15 | 🚨 Word Meter Slice Eight — Recognition Error Banner 🎙️"
URL: https://bagrounds.org/ai-blog/2026-05-15-1-word-meter-purescript-slice-eight-recognition-errors
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-05-15 | 🚨 Word Meter Slice Eight — Recognition Error Banner 🎙️

## 🧭 The Slice In One Breath

🎯 Slice eight of the Word Meter PureScript port teaches the reducer how to react when the Web Speech API reports an error. 🧠 We classify the raw error code into a typed sum, decide whether the user should see a banner or whether we should silently keep listening, and stop the active counting session when the microphone permission has been denied. 🪪 No real recognition object is wired up yet — that lands in slice nine — so the entire flow is exercised today through a `simulateRecognitionError` hook on the test interface.

## 🧱 What Used To Be A Pile Of Strings

📜 The legacy JavaScript bundle keeps two flat string arrays at the top of the file. 🪪 One array, called `PERMISSION_DENIED_ERRORS`, lists the codes `not-allowed` and `service-not-allowed`. 🪪 The other array, called `TRANSIENT_ERRORS`, lists `no-speech`, `aborted`, and `audio-capture`. 🧯 Then a `handleError` function compares the incoming code against those arrays and decides which banner to show, whether to stop listening, and whether to suppress the banner entirely. 🪢 That works fine, but it puts the meaning of each error code in three different places — the constant array, the handler, and the test code — and there is no compiler force-field to catch a forgotten branch.

## 🧪 The Typed Replacement

🧰 The new module is called `WordMeter.RecognitionError` and it is fully pure. 🧬 At its center sits a sum type with one constructor for each known code — `NotAllowed`, `ServiceNotAllowed`, `NoSpeech`, `Aborted`, `AudioCapture`, `Network`, `LanguageNotSupported` — plus two safety-net constructors. 🕳️ The first safety net, `NoRecognitionErrorCode`, models the case where the browser reports an error event with no `error` field at all, which Chromium occasionally does. 🌊 The second safety net, `OtherRecognitionError`, carries the raw string verbatim so the diagnostics drawer can still surface it to whoever opens a bug report. 🔍 The classifier is one pattern match from raw `String` into `RecognitionErrorCode`, and the predicates `isTransient` and `isPermissionDenied` work on the typed value rather than on string equality.

## 🗒️ The Banner Lives In The Session

🪟 The session record gains one new field, `errorBanner`, which is a plain string. 🪫 An empty string means no banner is showing. 🔴 A non-empty string is rendered inside the new `wm-error` element, styled in the same coral-pink color the legacy build used, with a `role="alert"` so assistive technology announces it without prompting. 🧹 The banner is intentionally not persisted to local storage. 🧊 Every page reload starts with a clean banner, which matches the legacy behavior and prevents stale error messages from haunting future sessions.

## 🎬 Two New Actions, One Helper

🎭 The reducer gains two new actions. 🧨 `HandleRecognitionError` carries a timestamp, the raw code, and the raw message. 🧽 `ClearErrorBanner` does what it says. 🧱 The interesting work happens inside the `HandleRecognitionError` case. 🪶 First, the reducer always appends a diagnostic entry labelled `recognition.onerror` with detail formatted as `code=<code or none> message=<message>`, so the audit trail records every error, including the transient ones we would otherwise suppress from the UI. 🪜 Then it classifies. 🤐 If the code is transient — a brief gap in speech, a call to `recognition.stop()`, or a momentary audio-capture hiccup — the reducer returns the session unchanged from the diagnostic point onward, leaving the banner and the listening state alone. 🛑 If the code is permission-denied and the program is currently listening, the reducer reuses the same stop-listening logic the user-driven Toggle uses: it closes the open interval, pushes it onto the event log, prunes captions, and records a follow-up diagnostic labelled `session ended` with detail `reason=permission denied`. ✨ For every other non-transient code — `network`, `language-not-supported`, the catch-all bucket — the banner is set but listening is left alone, because those errors are recoverable and the user might want to keep counting once the network heals.

## 🧯 Sharing The Stop-Listening Logic

🔁 Until slice eight, the stop-listening logic lived inline inside the `Toggle` branch of the reducer. 🪡 To avoid duplicating that block, we factored a helper called `stopListeningAt` that takes a timestamp, a diagnostic label, and a reason detail string. 🪢 The user-driven Toggle calls it with the label `stop counting` and an empty reason. 🚪 The permission-denied branch calls it with the label `session ended` and the reason `reason=permission denied`. 🪞 Both paths produce identical event-log entries, identical interval bookkeeping, and identical diagnostic-log shape — only the labels diverge. 🪶 That kind of shared spine is exactly what makes the audit trail a real audit trail, rather than a parallel narrative that drifts from the state.

## 🔋 Coordinating With The Wake Lock

🪫 Slice seven taught the program how to acquire a wake lock when listening starts and release it when listening stops. 🪞 The permission-denied branch of slice eight stops listening as a side effect, which means the wake lock would otherwise stay held with no way to release it. 🩻 The fix lives in `Main.handleRecognitionError`. 🧭 Before dispatching the action, we record whether the session was listening. 🧮 After dispatching, we check again. 🪢 If listening flipped from on to off, we call the same `releaseHeldWakeLock` routine the user-driven stop uses, which records the right diagnostics and clears the keep-awake status to match. 🛡️ No silent wake-lock leak, no fictional release diagnostics — every transition is reflected in both the lock state and the audit trail.

## 🧪 Tests Two Ways

🧮 The unit tests in `Test.Main` exercise the classifier, the predicates, the banner-text renderer, and the diagnostic-detail renderer directly. 🔬 They then run the reducer through every interesting transition: a transient error that changes nothing, a permission-denied error that stops listening and pushes the open interval onto the event log, a network error that sets the banner but keeps listening, a generic error that interpolates the raw code into the banner, and an empty-code error that falls back to the "unknown" string. 🎭 The end-to-end tests use the new `simulateRecognitionError` test hook to walk through the same scenarios in a real Chromium tab, asserting on the rendered `wm-error` element and on the strings produced by `getDiagnosticsText`. 🧾 Both layers run today, both layers pass, and slice nine — the real recognition wiring — gets to inherit a completely tested error pipeline.

## 🪞 What Slice Nine Will Add

🪟 The test hook drives the same code path that the real `SpeechRecognition.onerror` callback will drive in slice nine. 🪢 When that slice lands, the FFI shim will deliver the browser event into PureScript, the reducer will see exactly the same actions it sees today, and the banner plus the event-log entries will pop out without a single change to the slice-eight code. 🧱 The audit trail will stay byte-comparable with the legacy build, the wake lock will release on the way out of listening, and the typed sum will quietly catch any new code the browser starts emitting because the catch-all `OtherRecognitionError` constructor surfaces it instead of swallowing it.

## 📚 Book Recommendations

### 📖 Similar
* The Programmer's Brain by Felienne Hermans is relevant because it explains why turning a flat string array into a typed sum is more than ceremony — the compiler now scaffolds the cognitive work of "what does this code mean?" every time a new case shows up, and the named predicates do the rest of the lifting.
* Programming Haskell by Graham Hutton is relevant because the slice-eight pattern of "model the closed set, write predicates over it, route the reducer through pattern matching" is the same shape Haskell programs use to keep error handling honest, and the PureScript port leans on those same habits.

### ↔️ Contrasting
* The Pragmatic Programmer by David Thomas and Andrew Hunt offers a more language-agnostic view in which defensive programming and broad-spectrum exception handling are virtues. The slice-eight approach trades that runtime forgiveness for a compile-time guarantee that every recognition code is named and accounted for, which is a deliberate choice in the other direction.

### 🔗 Related
* Domain Modeling Made Functional by Scott Wlaschin is relevant because it spends an entire book teaching the move from primitive obsession toward typed sums, and the slice-eight `RecognitionErrorCode` is a perfect miniature of that lesson applied to a single browser API surface.
