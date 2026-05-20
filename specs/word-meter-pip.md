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
2. **Mic capture only survives where the window does.** On desktop Chrome, the PiP window stays user-visible after the source tab hides, which keeps `SpeechRecognition` running. On Android Chrome the PiP rollout is still partial — when present it behaves the same way, but absence is the common case today.

The honest answer to the original "auto-enter PiP when I switch apps" question is therefore **no — not without a prior user tap**. The realistic UX is a **manual pop-out**: the user taps a button once before pocketing the phone, the PiP window stays on top, and the count keeps ticking.

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
