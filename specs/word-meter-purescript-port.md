---
share: true
title: 🎙️ Word Meter PureScript Port Spec
---

# 🎙️ Word Meter PureScript Port Spec

This spec covers the **incremental** port of the Word Meter browser tool from `quartz/static/word-meter.js` (≈1,600 lines of imperative JavaScript) to PureScript, compiling to `quartz/static/word-meter-ps.js`. The two builds live side by side until the port is complete, at which point the legacy JavaScript build and its `vm`-sandbox unit tests are retired.

The companion spec at `specs/word-meter.md` is the source of truth for **what** the Word Meter does; this document covers **how** the PureScript port is structured.

## Goals

- Port the Word Meter to a strongly-typed PureScript codebase organized around the capability design pattern.
- Keep the legacy `word-meter.js` running on the live site at every step — never break the user-facing tool to make progress on the port.
- Ship as a single browser-friendly IIFE that mounts on `#word-meter`, so the markdown at `content/tools/word-meter.md` can keep its `<script src="/static/word-meter-ps.js"></script>` form without further machinery.
- Use a single end-to-end test suite that targets either implementation through a stable selector contract, so feature parity is asserted against the **same** specifications.

## Non-goals

- New Word Meter features during the port. New behaviour is added only after the cutover (slice 9 below).
- Byte-for-byte parity with `word-meter.js`. We care about features and visible behavior. If preserving an implementation detail forces ugly PureScript, we deviate and document it here.
- A general-purpose PureScript build for the rest of the Quartz site. This project is scoped to a single static script.

## Toolchain

- Compiler: `purescript@0.15.16` (latest stable as of this writing) via the official npm package.
- Build tool: `spago@1.0.4` (the rewritten-in-PureScript spago, distributed via npm).
- Bundler: spago's built-in `bundle --platform browser --bundle-type app` (esbuild under the hood). Produces a self-invoking IIFE.
- End-to-end tests: `@playwright/test` against a tiny static-fixture page served by `http-server`.

### Userspace PureScript dependencies

The PR direction was *"don't import any user space PureScript dependencies — they tend to not be well supported"*. The pragmatic interpretation in this project is:

- The official **core libraries** maintained by the `purescript/` GitHub organization (`prelude`, `effect`, `console`, and a small handful of close cousins such as `maybe`, `either`, `arrays`, `strings`, `transformers`) are treated as the language standard library and are allowed.
- Anything outside that set — for example Halogen, Argonaut, ReactBasic, web-html — is **not** added without an explicit decision documented here.

Today the project depends on exactly `prelude`, `effect`, and `console`. The FFI layer covers everything else.

## Project layout

```
purs-ps/
  spago.yaml                       # package + workspace config
  src/
    WordMeter/
      Main.purs                    # entry point (Effect Unit)
      Version.purs                 # WORD_METER_VERSION constant
      FFI.purs                     # DOM/native FFI surface (narrow on purpose)
      FFI.js                       # JS side of the FFI surface
  test/
    Test.Main.purs                 # `spago test` entry point
scripts/
  build-word-meter-ps.mjs          # spago bundle → quartz/static/word-meter-ps.js
tests/
  e2e/
    playwright.config.ts           # Playwright config (webServer + projects)
    word-meter.spec.ts             # implementation-agnostic behavior suite
    fixtures/
      word-meter.html              # ?impl=js|ps fixture page
```

The repo-root npm scripts surface this:

- `npm run build:ps` — rebuild `word-meter-ps.js`.
- `npm run clean:ps` — wipe PureScript build artifacts.
- `npm run test:ps` — run the PureScript `spago test` suite.
- `npm run test:e2e` — run the Playwright suite against the current `word-meter-ps.js` bundle.

## Capability design pattern

The port follows the same shape as `bagrounds/domination`'s capability layout: every external effect has a typeclass with the form

```purescript
class Monad m <= Cap m where
  someEffect :: Args -> m Result
```

Production code uses an `AppM` newtype (a `ReaderT Env Effect`) with one instance per capability. Tests use per-capability test newtypes (`StorageM`, `LogM`, etc.) that swap in deterministic implementations. Pure logic stays in plain functions that take whatever capabilities they need as type-class constraints — no concrete `Effect` references in domain modules.

Capabilities planned for the port (one slice per row, roughly):

- `Clock` — `now :: m Int` (milliseconds since epoch).
- `Log` — `log`, `error` (mirrors the prefixed-console-output pattern).
- `Dom` — `getElementById`, `setInnerHtml`, `addEventListener`, etc.
- `Storage` — typed `save`/`load` over `localStorage`.
- `Timer` — interval emitters.
- `Recognition` — Web Speech API.
- `WakeLock` — Screen Wake Lock API.
- `Clipboard` — `writeText` with execCommand fallback.

## Implementation-agnostic test suite

`tests/e2e/word-meter.spec.ts` is intentionally written **without** referencing PureScript or JavaScript. It loads the fixture page with `?impl=js` or `?impl=ps`, then drives the UI through a stable selector contract:

| Selector | Purpose |
| --- | --- |
| `[data-testid="wm-root"]` | The container the script mounts into. |
| `[data-testid="wm-count"]` | The big total-words number. |
| `[data-testid="wm-count-label"]` | The descriptor below the number. |
| `[data-testid="wm-toggle"]` | The start/stop button. |
| `[data-testid="wm-version"]` | The `Word Meter v<x>` footer line. |
| `[data-testid="wm-impl"]` | The "PureScript build" / "JavaScript build" tag. |

Every implementation must honor this contract. The legacy JavaScript build picks up its share of the tests as soon as we extend its template to emit the same data-testid attributes — that work is queued behind the cutover, since the legacy tests in `quartz/static/word-meter.test.mjs` already pin its behavior at the unit level.

## Vertical slices

| Slice | Scope | Status |
| --- | --- | --- |
| 1 | Toolchain, hello-world bundle, gitignore, npm scripts. | ✅ Done |
| 2 | Playwright fixture + selector contract + first behavior tests. | ✅ Done |
| 3 | Pure-utility port + capability scaffolding (`Clock`, `Log`, `Dom`, `Storage`). Unit tests for `countWords`, normalize, dedup classifier, rate math. | ⏳ Pending |
| 4 | UI rendering — buildPanel-equivalent. | ⏳ Pending |
| 5 | Session lifecycle + cumulative-refinement dedup state machine. | ⏳ Pending |
| 6 | SpeechRecognition path (cloud + on-device pre-flight + runtime fallback). | ⏳ Pending |
| 7 | Wake-lock + visibilitychange. | ⏳ Pending |
| 8 | Diagnostics panel + clipboard copy. | ⏳ Pending |
| 9 | Cutover: swap `content/tools/word-meter.md` to `word-meter-ps.js`, retire legacy JS + its sandbox tests. | ⏳ Pending |

## Tests

- **PureScript unit tests** in `purs-ps/test/Test.Main.purs`, run via `npm run test:ps`. Empty for slice 1; grows from slice 3 onward.
- **End-to-end behavior tests** in `tests/e2e/`, run via `npm run test:e2e`. Five tests in slice 1 cover the hello-world mount, count display, toggle button, version label, and implementation tag.
