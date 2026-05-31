# Mechanism Decorator Cleanup Plan

## Why This Plan Exists

With the [single-letter variable cleanup](single-letter-variable-cleanup-plan.md)
complete, a fresh compliance audit against `AGENTS.md` found that the next most common
aberration across the active source code is the
**No mechanism decorators on identifiers** rule:

> 🪪 No mechanism decorators on identifiers (`Impl`, `Internal`, `Helper`, `Raw`,
> `Unsafe`): name the thing, not how it is implemented — the type system, module
> boundary, and `foreign import` keyword already say what kind of thing it is. A
> wrapper that adds behavior gets its own concept-level name (`currentTimeMillis`,
> not `nowMsImpl` alongside `nowMs`). Applies to every language in the repo.

The audit found 47 occurrences of decorated identifiers across 5 files. This document
is the single source of truth for cleaning them up across future PRs.

## Evidence

Whole-word identifiers ending in a banned mechanism decorator across `haskell/`,
`purs-ps/src`, and `purs-ps/test` at the time of the audit:

* `Helper` — 27 occurrences in `haskell/test/Automation/DailyUpdatesTest.hs`
  (a single test fixture builds its expected markdown table with five `*Helper`
  functions: `columnEmojiHelper`, `columnLabelHelper`, `cellHelper`, `buildRowHelper`,
  `computeStatHelper`).
* `Raw` — 10 occurrences in `purs-ps/test/Test.Main.purs` (QuickCheck property
  parameters such as `nowRaw`, `captionRaw`, `tsRaw`, `wallRaw`, `activeRaw`).
* `Impl` — 10 occurrences across `purs-ps/src/WordMeter/FFI/Confirm.purs`,
  `purs-ps/src/WordMeter/FFI/Storage.purs`, and
  `purs-ps/src/WordMeter/FFI/Recognition.purs`. The pattern is a `foreign import
  fooImpl` paired with a wrapper `foo` that interprets the FFI return value.

No occurrences of `Internal` or `Unsafe` were found as identifier suffixes — `Raw`
and `Impl` cover the wrapper-vs-foreign-import idiom and `Helper` covers
mechanism-named local helpers.

## Naming Guidance

Each decorator should be renamed to a concept-level name based on what the value
represents at the call site, not a mechanical drop of the suffix.

| Decorator | Concept-level rename |
| --- | --- |
| `Helper` | drop entirely — the function's own name describes what it does (`columnEmojiHelper` → `columnEmoji`, `buildRowHelper` → `buildRow`). |
| `Raw` | name the unit of the value being held (`nowRaw` and `tsRaw` → `nowMs` / `timestampMs` for raw millisecond doubles entering a property test). |
| `Impl` | give the wrapper the concept-level name and pick a different concept-level name for the foreign import. Per AGENTS.md: "A wrapper that adds behavior gets its own concept-level name (`currentTimeMillis`, not `nowMsImpl` alongside `nowMs`)." For the storage FFI, rename the foreign imports to describe what they do at the JS layer (for example `readJsRawString` / `writeJsRawString` / `clearJsRawKey`) and let the PureScript wrapper keep the public domain name. |

`Helper` collisions are easy to dodge — the production module
`Automation.DailyUpdates` already exports `columnEmoji` and `cellText`, so the test's
local `where`-clause functions can reuse those names without conflict.

## Incremental Plan

Each step is a self-contained PR that removes one decorator class repository-wide,
runs the linter and the full test suite, and ships its own AI blog post. Pure renames
must not change behavior, so the existing tests are the safety net — no new tests
are required unless a rename surfaces a latent bug.

1. ✅ **`Helper` → concept name** in `haskell/test/Automation/DailyUpdatesTest.hs`
   (done in this PR): renamed every `*Helper` in the
   `existingTableContent` fixture — `columnEmojiHelper` → `columnEmoji`,
   `columnLabelHelper` → `columnLabel`, `cellHelper` → `cellText`, `buildRowHelper`
   → `buildRow`, `computeStatHelper` → `computeStat`. The names match the
   production helpers in `Automation.DailyUpdates`, which is what the fixture is
   imitating. Pure rename — the `-Werror` build is clean,
   `hlint src/ app/ test/` reports no hints, and all 2025 Haskell tests still pass.
Steps 2 and 3 are tracked in GitHub issue #7102.

2. ✅ **`Raw` → unit-level name** in `purs-ps/test/Test.Main.purs`: renamed the
   QuickCheck property parameters that hold raw `Number` millisecond values to
   names that describe the value (`nowMs`, `captionMs`, `timestampMs`, `wallMs`,
   `activeMs`). The `abs ...` calls that turn the QuickCheck-generated `Number`
   into a non-negative count of milliseconds stay as is. Pure rename — the
   PureScript bundle still builds clean and every QuickCheck property still
   passes.
3. ✅ **`Impl` → concept-level wrapper/import names** in
   `purs-ps/src/WordMeter/FFI/Confirm.purs`, `…/Storage.purs`, and
   `…/Recognition.purs`: every `*Impl` foreign import was renamed to a
   concept-level name that describes the JavaScript-side capability it
   exposes, while the PureScript wrapper kept the public domain name.
   `askForConfirmationImpl` → `runWindowConfirm`,
   `readPersistedStringImpl` / `writePersistedStringImpl` /
   `clearPersistedStringImpl` → `readJsRawString` / `writeJsRawString` /
   `clearJsRawKey`, and `ensureOnDeviceLanguagePackImpl` →
   `runOnDeviceLanguagePackPreflight`. The companion `.js` FFI exports were
   updated in lockstep. Pure rename — `npm run test:ps` builds clean and all
   PureScript unit tests pass.

## Definition of Done Per Step

* Zero occurrences of the targeted decorator as an identifier suffix in the
  targeted scope.
* `hlint src/ app/ test/` reports zero hints from the `haskell/` directory.
* `npm run test:ps` and `cabal test` both pass.
* The change is verified against the full `AGENTS.md` checklist before submission.
