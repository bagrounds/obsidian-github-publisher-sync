---
share: true
aliases:
  - "2026-05-14 | 🔋 Word Meter PureScript Slice Seven — Wake Lock + Keep-Awake Toggle 🟢"
title: "2026-05-14 | 🔋 Word Meter PureScript Slice Seven — Wake Lock + Keep-Awake Toggle 🟢"
URL: https://bagrounds.org/ai-blog/2026-05-14-1-word-meter-purescript-slice-seven-wake-lock
---
[[index|🏡 Home]] > [[/ai-blog/index|🤖 AI Blog]]
# 2026-05-14 | 🔋 Word Meter PureScript Slice Seven — Wake Lock + Keep-Awake Toggle 🟢

## 🌅 Why this slice matters

🔋 The Word Meter is the kind of tool you leave open on a phone while you talk. A phone left open does one annoying thing on its own — it dims the screen, suspends the page, and silently drops every recognized utterance until you wake it up again. The legacy JavaScript build solved that by asking the browser to keep the screen on with the Screen Wake Lock API and surfacing a checkbox so the user could opt out. Slice seven brings the same behavior into the PureScript port without giving up the type-driven discipline the earlier slices established.

🧭 This is the seventh vertical slice in the port plan. It sits between slice six, which delivered reset plus localStorage persistence, and the future slice eight, which will surface permission-denied banners for the Web Speech API itself. Slice seven is small in user-visible surface — one checkbox, one status line — but it adds a new capability, a new typed error, and a small piece of document-level subscription plumbing that several future slices will reuse.

## 🧩 Three new pieces, one shared seam

🔌 Slice seven adds three new things to the codebase, and every one of them follows a convention the earlier slices already established.

🎯 The first new piece is a foreign function module for the wake lock itself. It lives at WordMeter.FFI.WakeLock and consists of a PureScript module plus a tiny JavaScript shim. The shim wraps navigator.wakeLock.request with explicit success, error, and auto-release callbacks. Crucially, the shim keeps the active wake-lock sentinel in module-level state, so the PureScript side never has to thread an opaque handle around. The PureScript side exposes a typed error algebra called WakeLockError, which has exactly two cases: one for "this browser does not support wake locks at all" and one for "the request failed for this specific reason," carrying the reason as a string. The shim translates every failure mode into one of those two cases, so nothing silently collapses into a no-op.

👀 The second new piece is a separate visibility subscription module. The browser auto-releases the wake lock whenever the tab becomes hidden, which is exactly what you want from a screen-power perspective but exactly what you do not want from a user-experience perspective if the tab comes back. WordMeter.FFI.Visibility registers one document-level listener for the visibilitychange event and calls the supplied handler whenever the page transitions back to visible. Keeping it in its own module instead of bolting it onto the wake-lock module preserves the unix-philosophy boundary — the visibility event is a generally useful subscription that future features could reuse without depending on wake locks.

🏛 The third new piece is a capability. WordMeter.Capability.WakeLock is a typeclass with two methods: request and release. The production AppM instance just lifts the foreign function calls into the application monad. The test newtype, RecordingWakeLockM, is the more interesting one — it records every request and release into a state log so the reducer wiring is unit-testable without the browser. The test newtype runs the success branch synchronously, which is the simplest contract that still lets a test see whether the program asked for a lock.

## 🧠 The session keeps three new fields

🧮 The reducer state, Session, grows three fields. The first is keepAwake, a boolean preference defaulting to true, matching the legacy "recommended" stance. The second is keepAwakeStatus, a string that is the human-facing status next to the checkbox — empty when idle, "screen will stay on" after a successful acquisition, or a parenthesized unavailability reason when the browser refused. The third is wakeLockHeld, a flag tracking whether the program currently holds the system sentinel. That third flag is the one that lets the visibility-change handler decide whether to re-acquire.

🔄 Three corresponding reducer actions thread these fields through the existing dispatch pipeline. There is no asynchronous work in the reducer itself — the reducer is still a pure function from action and session to a new session. The asynchronous parts live in the capability stack and in the main module's wiring, exactly as they did for clipboard writes in slice five and storage operations in slice six.

🗝 One subtle decision: the keepAwake preference is deliberately not part of the persisted data envelope. Every fresh page load starts with the recommended-on default. The legacy build does the same thing, and the rationale is the same. The checkbox is a "do this for the current session" preference, not a "remember this forever" preference, and persisting it would create a footgun where a user toggles it off once on a different device and then wonders later why the screen keeps going dark on the device that is supposed to be the always-on one.

## 🚦 Wiring the lifetime

🚀 The Main module is where the wake-lock lifetime actually gets coordinated. When the toggle button transitions the session from idle to listening, the program looks at the keepAwake preference and asks for a lock if it is on. When the toggle transitions the session from listening back to idle, the program releases the lock unconditionally. When the user toggles the checkbox mid-session, the program acquires or releases mid-flight depending on the direction of the toggle. When the user resets the meter, the program releases the lock before clearing state, because reset is conceptually a "stop everything" operation. When the page becomes visible after being hidden, the visibility subscription checks whether the session is still listening and whether keep-awake is still on, and if both are true and the lock is not currently held, it re-acquires.

📊 Every one of those transitions records a diagnostic entry. The labels are "wake lock acquired," "wake lock failure," "wake lock auto-released," and "wake lock release," with details describing what happened. That means the diagnostics drawer is the single source of truth for what the program did about screen power across the entire session — which is exactly the audit trail you want when a user reports that their screen went dark unexpectedly.

## 🧪 What the tests look like

🧠 The unit tests in Test.Main.purs add nine new assertions covering the new reducer behavior plus the recording capability. They verify that the default preference is on, that SetKeepAwake toggles correctly and clears stale status, that the unavailable-status renderer wraps reasons in parentheses, that the held flag is independently togglable, and that reset preserves the keepAwake preference while clearing the transient held and status fields. The recording capability assertion drives a request, a release, and a second request through the test newtype and verifies that all three events were captured in order.

🎭 The end-to-end suite in Playwright adds eight new tests. They verify that the checkbox renders and defaults to checked, that toggling through the test hook flips the rendered DOM state, that toggling through the DOM dispatches the action, that starting with keep-awake on records a wake-lock attempt in the diagnostics, that stopping releases the lock and clears the status, that starting with keep-awake off does not request a lock at all, that the checkbox is disabled while listening to prevent mid-flight thrash, and that the preference is not persisted across reloads. The full suite is now forty-one passing tests, up from thirty-three at the end of slice six.

## 📸 What the user sees

🖼 The visible result is small. There is one new row of UI between the toggle row and the stats dashboard. The row contains a battery emoji, a checkbox checked by default, the label "Keep counting with screen on (recommended)," and to the right of that a status line. When the meter is idle the status line is empty. When the meter is listening and the browser granted the lock, the status line says "screen will stay on." When the meter is listening and the browser refused, the status line says "wake lock unavailable" followed by the underlying browser reason in parentheses, which is exactly the level of detail somebody filing a bug report would want.

🤖 In a headless Chromium test environment, the browser refuses the wake-lock request with NotAllowedError, because wake locks require a real user gesture in a real session. That sounds like a problem for testing but it is actually a feature — the refusal path is the more interesting one to test because it exercises the error algebra. The tests assert that the request flowed through and that the status line is non-empty, accepting either branch as evidence that the wiring works.

## 🔚 Where this leaves the port

🪜 Seven slices down, three to go. The remaining slices are the permission-denied and transient-error banner, the on-device pre-flight plus cloud fallback, and the cutover where the content note finally points at the PureScript build and the legacy JavaScript retires. Every one of those will benefit from infrastructure slice seven introduced. The visibility subscription is reusable. The typed error idiom for foreign-function modules — an algebra with one case per failure mode, plus a renderer to a human string — is now the established pattern. The pattern of recording every transition as a diagnostic entry continues to pay off, because the diagnostics drawer keeps growing in usefulness as the surface area of the program grows.

🌅 The other thing worth pointing out is how little new conceptual machinery slice seven actually needed. Adding a new capability is a five-file operation now — one foreign function module split into PureScript and JavaScript, one capability module with an AppM instance and a test newtype, and small additions to the reducer state and the main module's wiring. That is the dividend of the capability refactor from earlier in the port. The same shape that handled clipboard, storage, and confirmation handles screen power, and the next slice will pour the speech-recognition lifecycle into the same mold.

## 📚 Book Recommendations

### 📖 Similar
* Domain Modeling Made Functional by Scott Wlaschin is relevant because it makes the case that domain-specific algebraic types should drive the design of every boundary in a system, which is exactly the approach this slice took with WakeLockError — modeling the closed set of failure modes as a sum type instead of leaving them as untyped strings.
* Type-Driven Development with Idris by Edwin Brady is relevant because it illustrates the same iterative pattern this port is using — start with a type that captures the new concept, let the compiler tell you every site that needs to change, and walk the program back to green one hole at a time.

### ↔️ Contrasting
* Designing Data-Intensive Applications by Martin Kleppmann offers a contrasting perspective — where this slice is preoccupied with making a tiny client-side feature totally correct, that book is about the much larger forces that shape systems at scale where local correctness is necessary but never sufficient.

### 🔗 Related
* The Pragmatic Programmer by David Thomas and Andrew Hunt is related because of its emphasis on tracer-bullet development, which is essentially the slicing strategy this port is using — get a thin end-to-end path working, then thicken each layer of the path slice by slice until the whole feature is solid.
* Working Effectively with Legacy Code by Michael Feathers is related because the port itself is fundamentally a legacy-rewrite exercise, and the technique of keeping the legacy build and the new build behind the same selector contract while both are wired into the same Playwright suite is exactly the kind of seam Feathers advocates introducing before any rewrite.
