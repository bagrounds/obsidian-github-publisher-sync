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
- Keeping `SpeechRecognition` running on mobile Safari or Firefox. Document PiP is Chromium-only today.

## Feasibility

The browser API powering this is `window.documentPictureInPicture.requestWindow({ width, height })`, which returns a `Window` for a separate top-level browsing context that floats above other apps. It shipped in Chrome / Edge 116 in 2023.

Two constraints shape the design:

1. **User gesture required.** `requestWindow()` only resolves when called from a trusted user gesture (a click on a button is enough). A timer, a `visibilitychange` listener, or any other ambient handler cannot open a PiP window. There is no Permission-Policy that grants ambient PiP for documents — the autoPiP entitlements that exist (`autoPictureInPicture` on `<video>`) apply only to media-element PiP, not Document PiP.
2. **Document PiP is desktop-only.** Chromium ships Document Picture-in-Picture only on desktop platforms (Windows, macOS, Linux, ChromeOS). Android Chrome, iOS Safari, Firefox, Samsung Internet, and Android WebView all return `undefined` for `window.documentPictureInPicture`. This is documented on MDN as of 2026 and shows no signs of changing.

The honest answer to the original "auto-enter PiP when I switch apps" question is therefore **no — not without a prior user tap, and not on mobile at all**. The realistic desktop UX is a **manual pop-out**: the user taps a button once before switching apps, the PiP window stays on top, and the count keeps ticking.

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

The following table reflects browser-vendor compatibility data as of 2026. "Document PiP" refers to `window.documentPictureInPicture.requestWindow`; "Speech" refers to `SpeechRecognition` (cloud or on-device).

The Word Meter Pop-out button works in the green cells. On every other combination the button surfaces an explanatory unsupported message and the wake-lock toggle remains the only mitigation for "I want to switch apps without losing my count".

| Browser           | Desktop Document PiP | Mobile Document PiP | Speech available |
| ----------------- | -------------------- | ------------------- | ---------------- |
| Chrome 116+       | yes                  | no                  | yes              |
| Edge 116+         | yes                  | no                  | yes              |
| Opera 102+        | yes                  | no                  | yes              |
| Firefox           | no                   | no                  | no               |
| Safari            | no                   | no                  | partial          |
| Samsung Internet  | n/a                  | no                  | partial          |
| Chromium WebView  | n/a                  | no                  | partial          |

In prose, for TTS listeners: Document Picture-in-Picture is available on desktop Chrome, Edge, and Opera from version one hundred sixteen onward. It is not available on any mobile browser, including Chrome for Android and Safari on iOS. Firefox does not implement it on any platform. Therefore the Pop-out button is useful only on desktop Chromium, and on every other combination the meter shows a diagnostic explaining why the feature is missing.

### Why a video-PiP workaround on mobile is not pursued

A common hack for "I want any DOM rendered into PiP on Android" is to render content onto a `<canvas>`, capture the stream with `captureStream()`, attach it to a hidden `<video>`, and call `video.requestPictureInPicture()`. This path is technically open on Android Chrome.

But it does not actually solve the underlying problem the Pop-out button is trying to solve. The meter needs `SpeechRecognition` to keep running while the user is in another app, and Chromium suspends `SpeechRecognition` whenever the source page becomes hidden — regardless of whether a video element is in PiP. A floating video window on Android would therefore show a frozen number, not a live one. The wake-lock toggle (which keeps the screen on, which keeps the page visible) remains the only viable mitigation on mobile, and a video-PiP shim would simply add complexity without changing the outcome.

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
