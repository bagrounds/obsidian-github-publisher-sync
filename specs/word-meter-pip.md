---
share: true
title: "📺 Word Meter Picture-in-Picture Spec"
---

# 📺 Word Meter Picture-in-Picture Spec

The Word Meter offers an optional **Picture-in-Picture (PiP)** "pop-out" window so the user can keep an eye on their running word count after switching apps. This spec captures the feasibility analysis, the user-visible design, and the slice plan for layering the feature in over time.

## Goals

- Let the user pop a tiny always-on-top window out of the Word Meter that surfaces the **today's words** count and the listening status, so the meter stays glanceable when they put the phone in their pocket or open another app.
- Degrade gracefully on browsers and devices that don't support the Document Picture-in-Picture API — render the button, but disable it with an explanatory status when the API is missing.
- Keep the implementation surface tiny: a thin FFI shim, one capability, one session flag, one button. No changes to the recognition pipeline, the persistence layer, or the metrics grid.

## Non-goals

- Streaming the full UI into the PiP window. Slice 1 only shows the daily count and the status. Future slices may add rate / duration tiles.
- Automatically entering PiP when the user switches apps. The Document Picture-in-Picture API requires a **user gesture** for `requestWindow()`, so silent auto-entry is impossible from a pure web page (see Feasibility below).
- Keeping `SpeechRecognition` running while the source page is **fully backgrounded** on Android. Chromium suspends `SpeechRecognition` whenever the page becomes hidden, regardless of whether a video-PiP window is on top. The mobile fallback below floats the **last known count** above other apps, but live updates depend on the source page staying visible (e.g. split-screen view, or returning to the tab).

## Feasibility

The browser API powering this is `window.documentPictureInPicture.requestWindow({ width, height })`, which returns a `Window` for a separate top-level browsing context that floats above other apps. It shipped in Chrome / Edge 116 in 2023.

Two constraints shape the design:

1. **User gesture required.** `requestWindow()` only resolves when called from a trusted user gesture (a click on a button is enough). A timer, a `visibilitychange` listener, or any other ambient handler cannot open a PiP window. There is no Permission-Policy that grants ambient PiP for documents — the autoPiP entitlements that exist (`autoPictureInPicture` on `<video>`) apply only to media-element PiP, not Document PiP.
2. **Document PiP is desktop-only; mobile Chromium uses video PiP instead.** Chromium ships `window.documentPictureInPicture` only on desktop platforms (Windows, macOS, Linux, ChromeOS). Android Chrome, iOS Safari, Firefox, Samsung Internet, and Android WebView all return `undefined`. They do, however, expose the older `HTMLVideoElement.requestPictureInPicture` API. The Word Meter FFI now transparently falls through to that path when Document PiP is unavailable: a canvas-captured video is used as the floating surface and the count is painted onto it.

The honest answer to the original "auto-enter PiP when I switch apps" question is therefore **no — not without a prior user tap**. The realistic UX is a **manual pop-out** on desktop and on mobile. On desktop the floating count tracks live across app switches because the source page stays running; on mobile it tracks live while the source page is visible (split-screen, foreground tab) and freezes the count display when the page is fully backgrounded (because `SpeechRecognition` pauses).

## RCA — "picture-in-picture not supported on this browser" on mobile Chrome

The user reported tapping Pop-out on mobile Chrome and getting the "not supported" status, even though their Android Chrome app settings show a PiP permission toggle. Walking through five whys:

1. **Why does the button say "not supported" on mobile Chrome?** Because the `documentPipApiAvailable` foreign import returned `false`. The implementation checks for `window.documentPictureInPicture` and its `requestWindow` method.
2. **Why is that object missing on mobile Chrome?** Because Chromium intentionally gates Document Picture-in-Picture off on Android. The build artifact for Android Chrome simply does not register the API on the window object.
3. **Why is the API desktop-only?** Android already exposes a native PiP system that integrates with the platform task switcher, and Chromium routes the existing `HTMLVideoElement.requestPictureInPicture` API into it. The platform PiP model does not natively support arbitrary HTML documents, so Document PiP has not been ported.
4. **Why did the Android Chrome app settings suggest it should work?** Because Android's per-app PiP permission toggle controls *video* PiP — the legacy `HTMLVideoElement.requestPictureInPicture` API. There is no UI affordance on the device to distinguish video PiP from Document PiP, so seeing the toggle enabled is misleading.
5. **Why didn't the meter explain any of this?** Because the FFI returned a bare `Boolean` and the UI surfaced a single generic string. The user had no way to tell whether the API was missing, the call failed, or the device was simply not on the supported platform list.

### What this PR adds

The FFI now returns a platform-aware diagnostic string instead of a boolean. The capability layer wraps it into a new `DocumentPipUnsupported String` variant of `DocumentPipError`, and the status line surfaces the detail next to the existing "not supported on this browser" prefix. The detail includes:

- The exact missing surface (`window`, `documentPictureInPicture` object, or `requestWindow` method).
- A platform classification using `navigator.userAgentData.mobile` where available (Chromium Client Hints) and a user-agent string fallback otherwise.
- An explicit note that "Document Picture-in-Picture is desktop-only on Chromium" when the mobile branch fires, so users understand that no setting change on their phone will unlock the API.
- The raw user-agent or `userAgentData` brands+platform string for bug reports.

A representative status message on mobile Chrome now reads:

```
picture-in-picture not supported on this browser — Document Picture-in-Picture is desktop-only on Chromium (no Android/iOS support as of 2026); user-agent=Google Chrome, Chromium on Android (mobile)
```

### Per-browser / per-platform expectations

The following table reflects browser-vendor compatibility data as of 2026. "Document PiP" refers to `window.documentPictureInPicture.requestWindow`; "Video PiP" refers to `HTMLVideoElement.requestPictureInPicture`; "Speech" refers to `SpeechRecognition` (cloud or on-device).

The Word Meter Pop-out button works on every combination where either column shows yes. The mobile Video-PiP path is a frozen-when-backgrounded display surface, not a live background counter (see "Honest limitations" above).

| Browser           | Desktop Document PiP | Mobile Document PiP | Desktop Video PiP | Mobile Video PiP | Speech available |
| ----------------- | -------------------- | ------------------- | ----------------- | ---------------- | ---------------- |
| Chrome 116+       | yes                  | no                  | yes               | yes              | yes              |
| Edge 116+         | yes                  | no                  | yes               | yes              | yes              |
| Opera 102+        | yes                  | no                  | yes               | yes              | yes              |
| Firefox           | no                   | no                  | yes (limited)     | no               | no               |
| Safari            | no                   | no                  | yes               | yes (iOS)        | partial          |
| Samsung Internet  | n/a                  | no                  | n/a               | yes              | partial          |
| Chromium WebView  | n/a                  | no                  | n/a               | partial          | partial          |

In prose, for TTS listeners: on desktop Chrome, Edge, and Opera the Pop-out button uses the rich Document Picture-in-Picture path, which renders a real HTML count inside the floating window. On mobile Chromium browsers — Android Chrome, Edge, Opera, and Samsung Internet — the button falls through to a video Picture-in-Picture path that paints the count onto a canvas and pipes it into a hidden video element. On mobile Safari (iOS), video Picture-in-Picture is available and the same fallback runs. On desktop Safari the video fallback also runs. Firefox supports neither Document Picture-in-Picture nor the canvas-capture variant reliably, so the button surfaces an explanatory diagnostic there.

### Why a video-PiP workaround on mobile is now pursued (Slice 1b)

A common path for "I want any DOM rendered into PiP on Android" is to render content onto a `<canvas>`, capture the stream with `captureStream()`, attach it to a hidden `<video>`, and call `video.requestPictureInPicture()`. This path is supported on Android Chrome, Samsung Internet, and other mobile Chromium browsers.

This PR adds that fallback inside the FFI shim. When `window.documentPictureInPicture` is missing, `requestPipWindow` transparently falls through to the video-PiP path:

1. A 320×220 offscreen `<canvas>` is allocated.
2. The canvas is painted with the same count + label + status as the Document-PiP body.
3. `canvas.captureStream(2)` produces a low-frame-rate MediaStream — two frames per second is enough to keep the PiP window alive without burning battery.
4. A hidden `<video>` element is attached to the page, its `srcObject` is wired to the stream, and `video.requestPictureInPicture()` is called from the user gesture.
5. On every meter dispatch, `writePipContent` repaints the canvas. The capture pipeline propagates the new pixels into the PiP window automatically.
6. Closing dispatches `document.exitPictureInPicture()` and tears down the stream tracks and hidden video element.

From PureScript's perspective the two paths are interchangeable: the opaque `PipWindow` handle hides which underlying API is in use, and all three FFI exports (`requestPipWindow`, `attachPipCloseListener`, `closePipWindow`, `writePipContent`) dispatch on a private `kind` field inside the handle.

#### Honest limitations of the mobile fallback

The fallback **does not** turn the meter into a true background counter on Android. Two truths sit underneath it:

1. **`SpeechRecognition` suspends when the source page hides.** The Web Speech API ties its microphone tap to the document's visibility lifecycle. The moment the user switches apps and the meter tab goes fully hidden, Chromium pauses recognition. The PiP window stays on top with the **last seen count and status**, but the number is frozen until the user returns to the tab.
2. **No setting on the device unlocks background recognition.** The Android per-app PiP permission toggle is unrelated; it governs whether *any* video PiP window is allowed at all. There is no Chromium flag that keeps Web Speech alive while the page is hidden.

For a real always-on mobile counter we would need to swap Web Speech for raw `navigator.mediaDevices.getUserMedia()` + an in-house or cloud STT pipeline. That would let us hold the microphone open across visibility changes (because `getUserMedia` is gated by tab activity, not document visibility, and a PiP video element keeps the tab active on Chromium). This is out of scope for this PR — it would require replacing the entire recognition module, the on-device language pack pre-flight, the cloud fallback path, and the dedup/restart machinery. It is tracked as a future slice in the spec.

What the user gets today on mobile:

- A floating count window on top of any other app, mirroring the meter's current count and status.
- Live updates while the meter tab is in the foreground (including split-screen, picture-in-picture-of-the-system-task-switcher, or when the user briefly checks another app and comes back).
- A frozen-but-visible count window during full background — useful as a "where was I" reference rather than a live counter.
- No setting change required and no extra microphone permission.

## UI

A new pill button sits between **Reset** and the **Keep counting with screen on** toggle, with `data-testid="wm-pip-toggle"`. It is rendered unconditionally so the layout is stable, and its label tracks the session's `pipOpen` flag:

- Idle: `📺 Pop out count`
- PiP open: `✕ Close pop-out`

A small status line beside it (`data-testid="wm-pip-status"`) explains the current state in plain language — empty when nothing notable is happening, populated with a `picture-in-picture not supported on this browser` style message when the API is missing, or with the underlying error name when `requestWindow()` rejects.

## PiP window content (Slice 1)

The PiP window holds a minimal HTML document, populated by a thin FFI helper. It surfaces, top-to-bottom:

1. A big number — `session.wordsToday`.
2. A small label — `words today`.
3. A status line — `Listening` / `Idle` / the recognition status override, mirroring the main panel's status text.

The window is sized at 320×220 logical pixels (small enough for a phone overlay, large enough for the big number to read at arm's length). The PiP document re-renders whenever the main app rerenders, so the count updates in lockstep with the host panel.

## Lifecycle

- **Open**: clicking the pop-out button calls `requestWindow` through `Capability.DocumentPip`. On success, the window handle is stored in `applicationEnvironment.pipWindowRef`, the session flips `pipOpen = true`, and a `pagehide` listener on the PiP window fires `SetPipOpen false` so the button label snaps back when the user closes the floating window.
- **Update**: after every dispatch / rerender, if `pipOpen` is true the main module writes the current `{ wordsToday, status }` snapshot into the PiP document.
- **Close**: clicking the pop-out button again (or closing the PiP window with the OS chrome) closes the window, clears `pipWindowRef`, and dispatches `SetPipOpen false`.
- **Reset / SPA nav**: the existing cleanup hook closes the PiP window before clearing other resources.

Errors from `requestWindow` — including the "not supported" branch for browsers without `documentPictureInPicture` — surface via `SetPipStatus` into `session.pipStatus` (and the diagnostics drawer), never as exceptions or silent failures.

## Slice plan

1. **Slice 1 — manual pop-out with daily count (this spec).** FFI + capability + button + count/status sync.
2. **Slice 2 — richer PiP content.** Add the duration tile and the last-1-minute rate to the PiP body for at-a-glance feedback while the screen is in the pocket.
3. **Slice 3 — re-open across SPA nav.** Persist `pipOpen` so a quartz `nav` event that re-inits the IIFE re-opens the window if it was open before. (Persistence currently treats `pipOpen` as ephemeral; revisit when there is evidence the user wants this.)
4. **Slice 4 — investigate "auto-enter on hide" workarounds.** Track whether the spec / Chromium ever expose an `autoPictureInPicture` opt-in for Document PiP; if so, gate it behind the keep-awake toggle. Until then, the manual button is the upper bound.

## Tests

A single Playwright case in `tests/e2e/word-meter.spec.ts` covers Slice 1:

- The pop-out button renders with the expected label when idle.
- Clicking it in a browser that lacks `documentPictureInPicture` updates `wm-pip-status` with the unsupported-API message rather than crashing.
- Clicking it in a browser that exposes the API (Chromium head) flips the button label to "Close pop-out" and back when clicked a second time.

Unit tests cover the reducer transitions for `SetPipOpen` and `SetPipStatus` and the recording capability instance for the open/close paths.
